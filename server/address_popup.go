package main

import (
	"database/sql"
	"encoding/json"
	"html/template"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
)

const jusoPopupURL = "https://business.juso.go.kr/addrlink/addrMobileLinkUrl.do"

type selectedAddress struct {
	RoadAddress string `json:"roadAddress"`
	ZipCode     string `json:"zipCode"`
}

func (b *backend) createAddressPopup(w http.ResponseWriter, r *http.Request, user identity) {
	if !b.limit(w, r, "address_popup", 15) {
		return
	}
	var input struct{}
	if !decode(w, r, &input) {
		return
	}
	if b.cfg.JusoKey == "" {
		fail(w, 503, "address_unavailable", "주소 검색을 사용할 수 없어요. 잠시 후 다시 시도해주세요.")
		return
	}
	id, token := randomHex(16), randomToken()
	expires := b.now().Add(10 * time.Minute).Unix()
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`DELETE FROM address_popups WHERE expires_at<=?`, b.now().Unix()); err != nil {
		b.internal(w, err)
		return
	}
	var count int
	if err = tx.QueryRow(`SELECT COUNT(*) FROM address_popups WHERE uid=?`, user.UID).Scan(&count); err != nil {
		b.internal(w, err)
		return
	}
	if count >= 4 {
		fail(w, 429, "too_many_address_popups", "열려 있는 주소 검색창을 닫고 다시 시도해주세요.")
		return
	}
	if _, err = tx.Exec(`INSERT INTO address_popups(id,uid,token_hash,expires_at) VALUES(?,?,?,?)`, id, user.UID, hashToken(token), expires); err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	respond(w, 200, map[string]any{"id": id, "url": b.cfg.PublicOrigin + "/address-popup/" + id + "/" + token, "expiresAt": expires})
}

func (b *backend) addressPopupStatus(w http.ResponseWriter, r *http.Request, user identity) {
	var result sql.NullString
	err := b.db.QueryRow(`SELECT result_json FROM address_popups WHERE id=? AND uid=? AND expires_at>?`, r.PathValue("id"), user.UID, b.now().Unix()).Scan(&result)
	if err == sql.ErrNoRows {
		fail(w, 410, "address_popup_expired", "주소 검색을 다시 열어주세요.")
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	var address *selectedAddress
	if result.Valid {
		address = &selectedAddress{}
		if err = json.Unmarshal([]byte(result.String), address); err != nil {
			b.internal(w, err)
			return
		}
	}
	respond(w, 200, map[string]any{"ready": address != nil, "address": address})
}

func (b *backend) deleteAddressPopup(w http.ResponseWriter, r *http.Request, user identity) {
	if _, err := b.db.Exec(`DELETE FROM address_popups WHERE id=? AND uid=?`, r.PathValue("id"), user.UID); err != nil {
		b.internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

var addressLaunchTemplate = template.Must(template.New("address-launch").Parse(`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>주소 검색</title><body><p>주소 검색창을 불러오는 중이에요.</p><form id="address-form" method="post" action="{{.PopupURL}}" accept-charset="UTF-8"><input type="hidden" name="confmKey" value="{{.Key}}"><input type="hidden" name="returnUrl" value="{{.ReturnURL}}"><input type="hidden" name="resultType" value="4"></form><script nonce="{{.Nonce}}">document.getElementById('address-form').submit();</script></body></html>`))
var addressDoneTemplate = template.Must(template.New("address-done").Parse(`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>주소 선택 완료</title><body><p>주소를 선택했어요. 원래 화면으로 돌아가주세요.</p><button id="close">닫기</button><script nonce="{{.Nonce}}">window.flakeAddressFinished=true;document.getElementById('close').onclick=()=>window.close();if(window.opener){window.opener.postMessage({type:'flake-address-ready',id:{{.ID}}},{{.Origin}});window.close();}</script></body></html>`))

func popupHeaders(w http.ResponseWriter, nonce string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; form-action https://business.juso.go.kr; script-src 'nonce-"+nonce+"'; base-uri 'none'; frame-ancestors 'none'")
}

func (b *backend) addressPopupPage(w http.ResponseWriter, r *http.Request) {
	if !b.limit(w, r, "address_page", 60) {
		return
	}
	id, token := r.PathValue("id"), r.PathValue("token")
	if len(id) != 32 || len(token) != 43 {
		http.Error(w, "주소 검색을 다시 열어주세요.", 403)
		return
	}
	var saved sql.NullString
	err := b.db.QueryRow(`SELECT result_json FROM address_popups WHERE id=? AND token_hash=? AND expires_at>?`, id, hashToken(token), b.now().Unix()).Scan(&saved)
	if err == sql.ErrNoRows {
		http.Error(w, "주소 검색 시간이 지났어요. 창을 닫고 다시 검색해주세요.", 410)
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	if r.Method == http.MethodPost {
		origin := r.Header.Get("Origin")
		if origin != "" && origin != "https://business.juso.go.kr" && origin != "https://www.juso.go.kr" && origin != "https://juso.go.kr" {
			http.Error(w, "주소 검색 결과를 확인하지 못했어요.", 403)
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, 16*1024)
		if err = r.ParseForm(); err != nil {
			http.Error(w, "주소 검색 결과를 확인하지 못했어요.", 400)
			return
		}
		for _, name := range []string{"inputYn", "roadAddrPart1", "addrDetail", "zipNo"} {
			if len(r.PostForm[name]) > 1 {
				http.Error(w, "주소 검색 결과를 확인하지 못했어요.", 400)
				return
			}
		}
		road := strings.TrimSpace(r.PostForm.Get("roadAddrPart1"))
		detail := strings.TrimSpace(r.PostForm.Get("addrDetail"))
		if detail != "" {
			road += " " + detail
		}
		zip := r.PostForm.Get("zipNo")
		validZip := len(zip) == 5
		for _, c := range zip {
			if c < '0' || c > '9' {
				validZip = false
			}
		}
		if r.PostForm.Get("inputYn") != "Y" || !utf8.ValidString(road) || !validText(road, 120) || !validZip {
			http.Error(w, "주소 검색 결과를 확인하지 못했어요. 창을 닫고 다시 검색해주세요.", 400)
			return
		}
		data, _ := json.Marshal(selectedAddress{RoadAddress: road, ZipCode: zip})
		if _, err = b.db.Exec(`UPDATE address_popups SET result_json=? WHERE id=? AND token_hash=? AND expires_at>? AND result_json IS NULL`, string(data), id, hashToken(token), b.now().Unix()); err != nil {
			b.internal(w, err)
			return
		}
		saved.Valid = true
	}
	nonce := randomToken()
	popupHeaders(w, nonce)
	if saved.Valid {
		// No address is interpolated into executable HTML. The original authenticated
		// client retrieves the result, including when a mobile browser loses opener.
		err = addressDoneTemplate.Execute(w, map[string]string{"Nonce": nonce, "ID": id, "Origin": b.cfg.PublicOrigin})
	} else {
		err = addressLaunchTemplate.Execute(w, map[string]string{"Nonce": nonce, "PopupURL": jusoPopupURL, "Key": b.cfg.JusoKey, "ReturnURL": b.cfg.PublicOrigin + r.URL.EscapedPath()})
	}
	if err != nil {
		return
	} // Client disconnected; never log the launch form or its key.
}
