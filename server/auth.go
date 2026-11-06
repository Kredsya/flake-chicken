package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"time"
)

const identityPrefix = "flake-chicken-identity-v1\x00"
const sessionCookie = "__Host-flake-session"

func identityHash(salt, publicKey []byte) string {
	hash := sha256.New()
	hash.Write([]byte(identityPrefix))
	hash.Write(salt)
	hash.Write(publicKey)
	return hex.EncodeToString(hash.Sum(nil))
}

func hashToken(token string) string {
	value := sha256.Sum256([]byte(token))
	return hex.EncodeToString(value[:])
}

func parsePublicKey(data []byte) (*ecdsa.PublicKey, error) {
	parsed, err := x509.ParsePKIXPublicKey(data)
	if err != nil {
		return nil, err
	}
	key, ok := parsed.(*ecdsa.PublicKey)
	if !ok || key.Curve != elliptic.P256() {
		return nil, fmt.Errorf("P-256 public key required")
	}
	return key, nil
}

func verifySignature(key *ecdsa.PublicKey, payload string, signature []byte) bool {
	digest := sha256.Sum256([]byte(payload))
	// WebCrypto uses IEEE P1363; Android Keystore uses ASN.1 DER.
	if len(signature) == 64 {
		return ecdsa.Verify(key, digest[:], new(big.Int).SetBytes(signature[:32]), new(big.Int).SetBytes(signature[32:]))
	}
	return len(signature) <= 80 && ecdsa.VerifyASN1(key, digest[:], signature)
}

func (b *backend) challenge(w http.ResponseWriter, r *http.Request) {
	if !b.limit(w, r, "auth", 10) {
		return
	}
	var input struct{ UID, Salt, PublicKey, Platform string }
	if !decode(w, r, &input) {
		return
	}
	salt, err := base64.StdEncoding.DecodeString(input.Salt)
	if err != nil || len(salt) != 32 {
		fail(w, 400, "invalid_identity", "기기 식별 정보를 확인해주세요.")
		return
	}
	publicKey, err := base64.StdEncoding.DecodeString(input.PublicKey)
	if err != nil || len(publicKey) > 256 {
		fail(w, 400, "invalid_identity", "기기 키를 확인해주세요.")
		return
	}
	if _, err = parsePublicKey(publicKey); err != nil || identityHash(salt, publicKey) != input.UID || (input.Platform != "android" && input.Platform != "web") {
		fail(w, 400, "invalid_identity", "기기 식별 정보를 확인해주세요.")
		return
	}
	var saved []byte
	var platform string
	err = b.db.QueryRow(`SELECT public_key,platform FROM users WHERE uid=?`, input.UID).Scan(&saved, &platform)
	if err != nil && err != sql.ErrNoRows {
		b.internal(w, err)
		return
	}
	if err == nil && (subtle.ConstantTimeCompare(saved, publicKey) != 1 || platform != input.Platform) {
		fail(w, 409, "identity_conflict", "등록된 기기 키가 일치하지 않아요.")
		return
	}
	id := randomHex(16)
	expires := b.now().Add(2 * time.Minute).Unix()
	payload := "flake-chicken-auth-v1\n" + b.cfg.PublicOrigin + "\n" + id + "\n" + randomToken() + "\n" + input.UID
	_, err = b.db.Exec(`INSERT INTO challenges(id,uid,salt,public_key,platform,payload,expires_at) VALUES(?,?,?,?,?,?,?)`, id, input.UID, salt, publicKey, input.Platform, payload, expires)
	if err != nil {
		b.internal(w, err)
		return
	}
	respond(w, 200, map[string]any{"id": id, "payload": payload, "expiresAt": expires})
}

func (b *backend) authenticate(w http.ResponseWriter, r *http.Request) {
	if !b.limit(w, r, "auth_verify", 20) {
		return
	}
	var input struct{ ID, Signature string }
	if !decode(w, r, &input) {
		return
	}
	var uid, platform, payload string
	var salt, publicKey []byte
	var expires int64
	err := b.db.QueryRow(`SELECT uid,salt,public_key,platform,payload,expires_at FROM challenges WHERE id=?`, input.ID).Scan(&uid, &salt, &publicKey, &platform, &payload, &expires)
	if err != nil || expires <= b.now().Unix() {
		fail(w, 401, "invalid_challenge", "기기 인증을 다시 시도해주세요.")
		return
	}
	signature, err := base64.StdEncoding.DecodeString(input.Signature)
	key, keyErr := parsePublicKey(publicKey)
	if err != nil || keyErr != nil || !verifySignature(key, payload, signature) {
		fail(w, 401, "invalid_signature", "기기 인증에 실패했어요.")
		return
	}
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	result, err := tx.Exec(`DELETE FROM challenges WHERE id=? AND expires_at>?`, input.ID, b.now().Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	changed, _ := result.RowsAffected()
	if changed != 1 {
		fail(w, 401, "challenge_used", "이미 사용한 인증 요청이에요.")
		return
	}
	_, err = tx.Exec(`INSERT INTO users(uid,salt,public_key,platform,created_at) VALUES(?,?,?,?,?) ON CONFLICT(uid) DO NOTHING`, uid, salt, publicKey, platform, b.now().Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	var stored []byte
	if err = tx.QueryRow(`SELECT public_key FROM users WHERE uid=?`, uid).Scan(&stored); err != nil || subtle.ConstantTimeCompare(stored, publicKey) != 1 {
		fail(w, 409, "identity_conflict", "기기 등록을 확인해주세요.")
		return
	}
	token := randomToken()
	expires = b.now().Add(30 * time.Minute).Unix()
	_, err = tx.Exec(`INSERT INTO sessions(token_hash,uid,expires_at) VALUES(?,?,?)`, hashToken(token), uid, expires)
	if err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	cookieName := sessionCookie
	if b.cfg.Development {
		cookieName = "flake-session"
	}
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: token, Path: "/", Secure: !b.cfg.Development, HttpOnly: true, SameSite: http.SameSiteStrictMode, MaxAge: 1800})
	response := map[string]any{"uid": uid, "expiresAt": expires}
	if platform == "android" && r.Header.Get("Origin") == "" {
		response["token"] = token
	}
	respond(w, 200, response)
}

type identity struct {
	UID     string
	Expires int64
}

func (b *backend) session(r *http.Request) (identity, bool) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	bearer := strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !bearer {
		name := sessionCookie
		if b.cfg.Development {
			name = "flake-session"
		}
		cookie, err := r.Cookie(name)
		if err != nil {
			return identity{}, false
		}
		token = cookie.Value
		if r.Method != "GET" && r.Method != "HEAD" && r.Header.Get("Origin") != b.cfg.PublicOrigin {
			return identity{}, false
		}
	}
	if len(token) < 32 || len(token) > 128 {
		return identity{}, false
	}
	var user identity
	err := b.db.QueryRow(`SELECT uid,expires_at FROM sessions WHERE token_hash=? AND expires_at>?`, hashToken(token), b.now().Unix()).Scan(&user.UID, &user.Expires)
	return user, err == nil
}

func decode(w http.ResponseWriter, r *http.Request, destination any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 16*1024)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		fail(w, 400, "invalid_request", "입력 내용을 확인해주세요.")
		return false
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		fail(w, 400, "invalid_request", "입력 내용을 확인해주세요.")
		return false
	}
	return true
}
