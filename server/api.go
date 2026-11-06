package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

type serverConfig struct {
	PublicOrigin   string
	Development    bool
	JusoKey        string
	MapsKey        string
	MapsDailyLimit int
	ProjectID      string
	HTTPClient     *http.Client
}

type backend struct {
	db                        *sql.DB
	cfg                       serverConfig
	now                       func() time.Time
	events                    eventHub
	wakeup                    chan struct{}
	limitsMu                  sync.Mutex
	limits                    map[string]rateWindow
	vapidPublic, vapidPrivate string
}

type rateWindow struct {
	Start time.Time
	Count int
}

func newBackend(path string, cfg serverConfig) (*backend, error) {
	db, err := openDatabase(path)
	if err != nil {
		return nil, err
	}
	if cfg.MapsDailyLimit == 0 {
		cfg.MapsDailyLimit = 100
	}
	if cfg.HTTPClient == nil {
		cfg.HTTPClient = &http.Client{Timeout: 15 * time.Second}
	}
	b := &backend{db: db, cfg: cfg, now: time.Now, wakeup: make(chan struct{}, 1), limits: map[string]rateWindow{}}
	if err = b.setupVAPID(); err != nil {
		db.Close()
		return nil, err
	}
	return b, nil
}

func respond(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func fail(w http.ResponseWriter, status int, code, message string) {
	respond(w, status, map[string]string{"code": code, "message": message})
}

func (b *backend) internal(w http.ResponseWriter, err error) {
	log.Printf("backend operation failed: %v", err)
	fail(w, 500, "internal_error", "잠시 후 다시 시도해주세요.")
}

func (b *backend) limit(w http.ResponseWriter, r *http.Request, kind string, maximum int) bool {
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	if forwarded := r.Header.Get("X-Forwarded-For"); (ip == "127.0.0.1" || ip == "::1") && forwarded != "" {
		ip = strings.TrimSpace(strings.Split(forwarded, ",")[0])
	}
	key := kind + ":" + ip
	b.limitsMu.Lock()
	defer b.limitsMu.Unlock()
	if len(b.limits) > 10000 {
		for k, v := range b.limits {
			if b.now().Sub(v.Start) > time.Minute {
				delete(b.limits, k)
			}
		}
	}
	window := b.limits[key]
	if b.now().Sub(window.Start) >= time.Minute {
		window = rateWindow{Start: b.now()}
	}
	window.Count++
	b.limits[key] = window
	if window.Count > maximum {
		w.Header().Set("Retry-After", "60")
		fail(w, 429, "rate_limited", "잠시 후 다시 시도해주세요.")
		return false
	}
	return true
}

type authenticatedHandler func(http.ResponseWriter, *http.Request, identity)

func (b *backend) authenticated(handler authenticatedHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.session(r)
		if !ok {
			fail(w, 401, "unauthorized", "기기 인증이 필요해요.")
			return
		}
		handler(w, r, user)
	}
}

func (b *backend) handler(webDir string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/auth/challenge", b.challenge)
	mux.HandleFunc("POST /api/auth/verify", b.authenticate)
	mux.HandleFunc("GET /api/config", func(w http.ResponseWriter, r *http.Request) {
		respond(w, 200, map[string]any{
			"webPushPublicKey": b.vapidPublic, "mapsAvailable": b.cfg.MapsKey != "", "androidPushAvailable": b.cfg.ProjectID != "", "minParticipants": 2, "addressSearchAvailable": b.cfg.JusoKey != "",
		})
	})
	mux.HandleFunc("POST /api/address-popup", b.authenticated(b.createAddressPopup))
	mux.HandleFunc("GET /api/address-popup/{id}", b.authenticated(b.addressPopupStatus))
	mux.HandleFunc("DELETE /api/address-popup/{id}", b.authenticated(b.deleteAddressPopup))
	mux.HandleFunc("GET /address-popup/{id}/{token}", b.addressPopupPage)
	mux.HandleFunc("POST /address-popup/{id}/{token}", b.addressPopupPage)
	mux.HandleFunc("GET /api/appointments", b.authenticated(b.listAppointments))
	mux.HandleFunc("POST /api/appointments", b.authenticated(b.createAppointment))
	mux.HandleFunc("GET /api/invitations/{code}", b.authenticated(b.previewInvitation))
	mux.HandleFunc("POST /api/invitations/{code}/join", b.authenticated(b.joinAppointment))
	mux.HandleFunc("PATCH /api/appointments/{id}", b.authenticated(b.updateAppointment))
	mux.HandleFunc("PUT /api/appointments/{id}/choice", b.authenticated(b.setChoice))
	mux.HandleFunc("POST /api/appointments/{id}/hall-of-fame", b.authenticated(b.archiveAppointment))
	mux.HandleFunc("DELETE /api/appointments/{id}/owned", b.authenticated(b.deleteOwnedAppointment))
	mux.HandleFunc("DELETE /api/appointments/{id}", b.authenticated(b.hideAppointment))
	mux.HandleFunc("GET /api/appointments/{id}/route", b.authenticated(b.route))
	mux.HandleFunc("GET /api/events", b.authenticated(b.stream))
	mux.HandleFunc("PUT /api/push", b.authenticated(b.registerPush))
	mux.HandleFunc("DELETE /api/push/{kind}", b.authenticated(b.removePush))
	mux.Handle("/", newHandler(webDir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")
		w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
		w.Header().Set("X-Frame-Options", "DENY")
		if strings.HasPrefix(r.URL.Path, "/api/") {
			if origin := r.Header.Get("Origin"); origin != "" && origin != b.cfg.PublicOrigin {
				fail(w, 403, "origin_rejected", "허용되지 않은 요청이에요.")
				return
			}
			if !b.limit(w, r, "api", 240) {
				return
			}
		}
		mux.ServeHTTP(w, r)
	})
}

type appointmentView struct {
	IsArchived       bool   `json:"isArchived"`
	ID               string `json:"id"`
	Title            string `json:"title"`
	StartsAt         string `json:"startsAt"`
	Destination      string `json:"destination"`
	InvitationCode   string `json:"invitationCode"`
	DisplayName      string `json:"displayName"`
	Origin           string `json:"origin"`
	ParticipantCount int    `json:"participantCount"`
	IsOwner          bool   `json:"isOwner"`
	MyChoice         bool   `json:"myChoice"`
	IsCancelled      bool   `json:"isCancelled"`
	Version          int    `json:"version"`
	RouteVariant     int    `json:"routeVariant"`
	DurationMinutes  *int   `json:"durationMinutes"`
}

type rowScanner interface{ Scan(...any) error }
type queryer interface{ QueryRow(string, ...any) *sql.Row }

const appointmentSelect = `SELECT a.id,a.title,a.starts_at,a.destination,a.code,m.display_name,m.origin,
 (SELECT COUNT(*) FROM members c WHERE c.appointment_id=a.id),a.owner=?,m.choice,a.cancelled_at IS NOT NULL,a.version,EXISTS(SELECT 1 FROM hall_of_fame h WHERE h.appointment_id=a.id AND h.uid=m.uid)
 FROM appointments a JOIN members m ON m.appointment_id=a.id WHERE m.uid=? AND m.hidden=0`

func scanAppointment(row rowScanner) (appointmentView, error) {
	var a appointmentView
	err := row.Scan(&a.ID, &a.Title, &a.StartsAt, &a.Destination, &a.InvitationCode, &a.DisplayName, &a.Origin, &a.ParticipantCount, &a.IsOwner, &a.MyChoice, &a.IsCancelled, &a.Version, &a.IsArchived)
	return a, err
}

func ownAppointment(q queryer, id, uid string) (appointmentView, error) {
	return scanAppointment(q.QueryRow(appointmentSelect+` AND a.id=?`, uid, uid, id))
}

func (b *backend) listAppointments(w http.ResponseWriter, r *http.Request, user identity) {
	rows, err := b.db.Query(appointmentSelect+` ORDER BY a.cancelled_at IS NOT NULL,a.starts_at`, user.UID, user.UID)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer rows.Close()
	items := []appointmentView{}
	for rows.Next() {
		a, err := scanAppointment(rows)
		if err != nil {
			b.internal(w, err)
			return
		}
		items = append(items, a)
	}
	if err = rows.Err(); err != nil {
		b.internal(w, err)
		return
	}
	respond(w, 200, map[string]any{"appointments": items})
}

type createInput struct {
	Title       string    `json:"title"`
	StartsAt    time.Time `json:"startsAt"`
	Destination string    `json:"destination"`
	DisplayName string    `json:"displayName"`
	Origin      string    `json:"origin"`
	Choice      bool      `json:"choice"`
	RequestID   string    `json:"requestId"`
}

func validText(text string, max int) bool {
	if strings.TrimSpace(text) == "" || utf8.RuneCountInString(text) > max {
		return false
	}
	for _, value := range text {
		if unicode.IsControl(value) {
			return false
		}
	}
	return true
}

func validAppointment(title, destination string, at time.Time) bool {
	return validText(title, 40) && validText(destination, 120) && at.Year() >= 2020 && at.Year() <= 2100
}

func (b *backend) createAppointment(w http.ResponseWriter, r *http.Request, user identity) {
	var input createInput
	if !decode(w, r, &input) {
		return
	}
	requestBytes, requestErr := hex.DecodeString(input.RequestID)
	if !validAppointment(input.Title, input.Destination, input.StartsAt) || !validText(input.DisplayName, 20) || !validText(input.Origin, 120) || requestErr != nil || len(requestBytes) != 16 {
		fail(w, 400, "invalid_appointment", "약속 이름·시간·장소와 프로필을 확인해주세요.")
		return
	}
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	var existingID, existingHash string
	data, _ := json.Marshal(input)
	digest := sha256.Sum256(data)
	requestHash := hex.EncodeToString(digest[:])
	err = tx.QueryRow(`SELECT id,request_hash FROM appointments WHERE owner=? AND request_id=?`, user.UID, input.RequestID).Scan(&existingID, &existingHash)
	if err == nil {
		if existingHash != requestHash {
			fail(w, 409, "request_conflict", "요청을 다시 확인해주세요.")
			return
		}
		a, err := ownAppointment(tx, existingID, user.UID)
		if err != nil {
			b.internal(w, err)
			return
		}
		respond(w, 200, a)
		return
	}
	if err != sql.ErrNoRows {
		b.internal(w, err)
		return
	}
	var count int
	if err = tx.QueryRow(`SELECT COUNT(*) FROM members WHERE uid=? AND hidden=0`, user.UID).Scan(&count); err != nil {
		b.internal(w, err)
		return
	}
	if count >= 200 {
		fail(w, 409, "appointment_limit", "약속은 최대 200개까지 보관할 수 있어요.")
		return
	}
	id, code := randomHex(16), randomCode()
	for attempts := 0; attempts < 5; attempts++ {
		var exists int
		err = tx.QueryRow(`SELECT 1 FROM appointments WHERE code=?`, code).Scan(&exists)
		if err == sql.ErrNoRows {
			break
		}
		if err != nil {
			b.internal(w, err)
			return
		}
		code = randomCode()
	}
	_, err = tx.Exec(`INSERT INTO appointments(id,code,owner,title,starts_at,destination,request_id,request_hash,created_at) VALUES(?,?,?,?,?,?,?,?,?)`, id, code, user.UID, strings.TrimSpace(input.Title), input.StartsAt.UTC().Format(time.RFC3339Nano), strings.TrimSpace(input.Destination), input.RequestID, requestHash, b.now().Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	_, err = tx.Exec(`INSERT INTO members(appointment_id,uid,display_name,origin,choice,joined_at) VALUES(?,?,?,?,?,?)`, id, user.UID, strings.TrimSpace(input.DisplayName), strings.TrimSpace(input.Origin), input.Choice, b.now().Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	a, err := ownAppointment(tx, id, user.UID)
	if err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	b.events.publish([]string{user.UID})
	respond(w, 201, a)
}

func (b *backend) previewInvitation(w http.ResponseWriter, r *http.Request, user identity) {
	if !b.limit(w, r, "invite", 15) {
		return
	}
	code := strings.ToUpper(strings.TrimSpace(r.PathValue("code")))
	var a appointmentView
	err := b.db.QueryRow(`SELECT id,title,starts_at,destination,code,cancelled_at IS NOT NULL,version,(SELECT COUNT(*) FROM members WHERE appointment_id=a.id) FROM appointments a WHERE code=?`, code).Scan(&a.ID, &a.Title, &a.StartsAt, &a.Destination, &a.InvitationCode, &a.IsCancelled, &a.Version, &a.ParticipantCount)
	if err == sql.ErrNoRows {
		fail(w, 404, "invitation_not_found", "초대 코드를 확인해주세요.")
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	if appointmentHasPassed(a.StartsAt, b.now()) {
		fail(w, 410, "appointment_completed", "이미 시간이 지난 약속이에요.")
		return
	}
	if a.IsCancelled {
		fail(w, 410, "appointment_cancelled", "이미 파토난 약속이에요.")
		return
	}
	var exists int
	err = b.db.QueryRow(`SELECT 1 FROM members WHERE appointment_id=? AND uid=?`, a.ID, user.UID).Scan(&exists)
	if err == nil {
		fail(w, 409, "already_joined", "이미 참여 중인 약속이에요.")
		return
	}
	if err != sql.ErrNoRows {
		b.internal(w, err)
		return
	}
	respond(w, 200, a)
}

func consensus(tx *sql.Tx, id string, now int64) (bool, error) {
	var count, choices int
	if err := tx.QueryRow(`SELECT COUNT(*),COALESCE(SUM(choice),0) FROM members WHERE appointment_id=?`, id).Scan(&count, &choices); err != nil {
		return false, err
	}
	if count < 2 || choices != count {
		return false, nil
	}
	result, err := tx.Exec(`UPDATE appointments SET cancelled_at=?,version=version+1 WHERE id=? AND cancelled_at IS NULL`, now, id)
	if err != nil {
		return false, err
	}
	changed, _ := result.RowsAffected()
	if changed != 1 {
		return false, nil
	}
	var title string
	if err = tx.QueryRow(`SELECT title FROM appointments WHERE id=?`, id).Scan(&title); err != nil {
		return false, err
	}
	_, err = tx.Exec(`INSERT OR IGNORE INTO notifications(id,appointment_id,uid,title,body,created_at)
	 SELECT ? || ':' || uid,appointment_id,uid,?,?,? FROM members WHERE appointment_id=?`, id, "약속이 파토났어요", "‘"+title+"’ 약속이 취소됐어요.", now, id)
	if err != nil {
		return false, err
	}
	_, err = tx.Exec(`INSERT OR IGNORE INTO push_outbox(notification_id,target_id,next_attempt)
	 SELECT n.id,p.id,? FROM notifications n JOIN push_targets p ON p.uid=n.uid WHERE n.appointment_id=? AND p.active=1`, now, id)
	return true, err
}

func memberUIDs(q interface {
	Query(string, ...any) (*sql.Rows, error)
}, id string) ([]string, error) {
	rows, err := q.Query(`SELECT uid FROM members WHERE appointment_id=?`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []string
	for rows.Next() {
		var uid string
		if err = rows.Scan(&uid); err != nil {
			return nil, err
		}
		users = append(users, uid)
	}
	return users, rows.Err()
}

func (b *backend) changed(users []string) {
	b.events.publish(users)
	select {
	case b.wakeup <- struct{}{}:
	default:
	}
}

func (b *backend) joinAppointment(w http.ResponseWriter, r *http.Request, user identity) {
	var input struct {
		DisplayName string `json:"displayName"`
		Origin      string `json:"origin"`
		Choice      bool   `json:"choice"`
	}
	if !decode(w, r, &input) {
		return
	}
	if !validText(input.DisplayName, 20) || !validText(input.Origin, 120) {
		fail(w, 400, "invalid_profile", "이름과 출발 주소를 확인해주세요.")
		return
	}
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	var id string
	var cancelled bool
	var startsAt string
	err = tx.QueryRow(`SELECT id,cancelled_at IS NOT NULL,starts_at FROM appointments WHERE code=?`, strings.ToUpper(r.PathValue("code"))).Scan(&id, &cancelled, &startsAt)
	if err == sql.ErrNoRows {
		fail(w, 404, "invitation_not_found", "초대 코드를 확인해주세요.")
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	if current, err := ownAppointment(tx, id, user.UID); err == nil {
		respond(w, 200, current)
		return
	} else if err != sql.ErrNoRows {
		b.internal(w, err)
		return
	}
	if appointmentHasPassed(startsAt, b.now()) {
		fail(w, 410, "appointment_completed", "이미 시간이 지난 약속이에요.")
		return
	}
	if cancelled {
		fail(w, 410, "appointment_cancelled", "이미 파토난 약속이에요.")
		return
	}
	var count int
	if err = tx.QueryRow(`SELECT COUNT(*) FROM members WHERE appointment_id=?`, id).Scan(&count); err != nil {
		b.internal(w, err)
		return
	}
	if count >= 50 {
		fail(w, 409, "member_limit", "최대 참여 인원에 도달했어요.")
		return
	}
	_, err = tx.Exec(`INSERT INTO members(appointment_id,uid,display_name,origin,choice,joined_at) VALUES(?,?,?,?,?,?)`, id, user.UID, strings.TrimSpace(input.DisplayName), strings.TrimSpace(input.Origin), input.Choice, b.now().Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	if _, err = tx.Exec(`UPDATE appointments SET version=version+1 WHERE id=?`, id); err != nil {
		b.internal(w, err)
		return
	}
	if _, err = consensus(tx, id, b.now().Unix()); err != nil {
		b.internal(w, err)
		return
	}
	a, err := ownAppointment(tx, id, user.UID)
	if err != nil {
		b.internal(w, err)
		return
	}
	uids, err := memberUIDs(tx, id)
	if err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	b.changed(uids)
	respond(w, 200, a)
}

func (b *backend) setChoice(w http.ResponseWriter, r *http.Request, user identity) {
	var input struct {
		Choice *bool `json:"choice"`
	}
	if !decode(w, r, &input) {
		return
	}
	if input.Choice == nil {
		fail(w, 400, "invalid_choice", "파토 선택을 확인해주세요.")
		return
	}
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	id := r.PathValue("id")
	a, err := ownAppointment(tx, id, user.UID)
	if err == sql.ErrNoRows {
		fail(w, 404, "not_found", "약속을 찾을 수 없어요.")
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	if a.IsCancelled {
		if *input.Choice && a.MyChoice {
			respond(w, 200, a)
		} else {
			fail(w, 409, "appointment_cancelled", "파토가 확정된 약속은 변경할 수 없어요.")
		}
		return
	}
	if appointmentHasPassed(a.StartsAt, b.now()) {
		fail(w, 409, "appointment_completed", "시간이 지난 약속은 변경할 수 없어요.")
		return
	}
	_, err = tx.Exec(`UPDATE members SET choice=? WHERE appointment_id=? AND uid=?`, *input.Choice, id, user.UID)
	if err != nil {
		b.internal(w, err)
		return
	}
	final, err := consensus(tx, id, b.now().Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	a, err = ownAppointment(tx, id, user.UID)
	if err != nil {
		b.internal(w, err)
		return
	}
	// Before consensus, only the voter's own sessions are notified. No timing
	// event, count or other member's vote is sent to the remaining participants.
	uids := []string{user.UID}
	if final {
		uids, err = memberUIDs(tx, id)
		if err != nil {
			b.internal(w, err)
			return
		}
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	b.changed(uids)
	respond(w, 200, a)
}

func (b *backend) updateAppointment(w http.ResponseWriter, r *http.Request, user identity) {
	var input struct {
		Title       string    `json:"title"`
		StartsAt    time.Time `json:"startsAt"`
		Destination string    `json:"destination"`
		Version     int       `json:"version"`
	}
	if !decode(w, r, &input) {
		return
	}
	if !validAppointment(input.Title, input.Destination, input.StartsAt) {
		fail(w, 400, "invalid_appointment", "약속 정보를 확인해주세요.")
		return
	}
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	a, err := ownAppointment(tx, r.PathValue("id"), user.UID)
	if err == sql.ErrNoRows {
		fail(w, 404, "not_found", "약속을 찾을 수 없어요.")
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	if !a.IsOwner {
		fail(w, 403, "owner_required", "약속을 만든 사람만 수정할 수 있어요.")
		return
	}
	if a.IsCancelled {
		fail(w, 409, "appointment_cancelled", "이미 파토난 약속이에요.")
		return
	}
	if appointmentHasPassed(a.StartsAt, b.now()) {
		fail(w, 409, "appointment_completed", "시간이 지난 약속은 변경할 수 없어요.")
		return
	}
	if a.Version != input.Version {
		fail(w, 409, "version_conflict", "다른 변경사항이 있어요. 약속을 다시 확인해주세요.")
		return
	}
	_, err = tx.Exec(`UPDATE appointments SET title=?,starts_at=?,destination=?,version=version+1 WHERE id=?`, strings.TrimSpace(input.Title), input.StartsAt.UTC().Format(time.RFC3339Nano), strings.TrimSpace(input.Destination), a.ID)
	if err != nil {
		b.internal(w, err)
		return
	}
	uids, err := memberUIDs(tx, a.ID)
	if err != nil {
		b.internal(w, err)
		return
	}
	a, err = ownAppointment(tx, a.ID, user.UID)
	if err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	b.events.publish(uids)
	respond(w, 200, a)
}

func (b *backend) hideAppointment(w http.ResponseWriter, r *http.Request, user identity) {
	result, err := b.db.Exec(`UPDATE members SET hidden=1 WHERE appointment_id=? AND uid=? AND
	 EXISTS(SELECT 1 FROM appointments WHERE id=members.appointment_id AND (cancelled_at IS NOT NULL OR EXISTS(SELECT 1 FROM hall_of_fame h WHERE h.appointment_id=members.appointment_id AND h.uid=members.uid)))`, r.PathValue("id"), user.UID)
	if err != nil {
		b.internal(w, err)
		return
	}
	changed, _ := result.RowsAffected()
	if changed == 0 {
		fail(w, 409, "cannot_delete", "파토난 약속이나 명예의 전당에 있는 약속만 삭제할 수 있어요.")
		return
	}
	b.events.publish([]string{user.UID})
	w.WriteHeader(http.StatusNoContent)
}

func appointmentHasPassed(at string, now time.Time) bool {
	parsed, err := time.Parse(time.RFC3339Nano, at)
	return err == nil && !parsed.After(now)
}
func (b *backend) archiveAppointment(w http.ResponseWriter, r *http.Request, user identity) {
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	a, err := ownAppointment(tx, r.PathValue("id"), user.UID)
	if err == sql.ErrNoRows {
		fail(w, 404, "not_found", "약속을 찾을 수 없어요.")
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	if a.IsCancelled || !appointmentHasPassed(a.StartsAt, b.now()) {
		fail(w, 409, "not_completed", "파토 없이 시간이 지난 약속만 명예의 전당에 옮길 수 있어요.")
		return
	}
	if _, err = tx.Exec(`INSERT OR IGNORE INTO hall_of_fame(appointment_id,uid) VALUES(?,?)`, a.ID, user.UID); err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	b.events.publish([]string{user.UID})
	respond(w, 200, map[string]bool{"archived": true})
}

func (b *backend) deleteOwnedAppointment(w http.ResponseWriter, r *http.Request, user identity) {
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	a, err := ownAppointment(tx, r.PathValue("id"), user.UID)
	if err == sql.ErrNoRows {
		w.WriteHeader(204)
		return
	}
	if err != nil {
		b.internal(w, err)
		return
	}
	if !a.IsOwner {
		fail(w, 403, "owner_required", "약속을 만든 사람만 삭제할 수 있어요.")
		return
	}
	if a.IsCancelled || appointmentHasPassed(a.StartsAt, b.now()) {
		fail(w, 409, "appointment_finished", "종료된 약속은 목록에서 삭제해주세요.")
		return
	}
	users, err := memberUIDs(tx, a.ID)
	if err != nil {
		b.internal(w, err)
		return
	}
	for _, query := range []string{
		`DELETE FROM push_outbox WHERE notification_id IN (SELECT id FROM notifications WHERE appointment_id=?)`,
		`DELETE FROM notifications WHERE appointment_id=?`,
		`DELETE FROM hall_of_fame WHERE appointment_id=?`,
		`DELETE FROM members WHERE appointment_id=?`,
		`DELETE FROM appointments WHERE id=?`,
	} {
		if _, err = tx.Exec(query, a.ID); err != nil {
			b.internal(w, err)
			return
		}
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	b.events.publish(users)
	w.WriteHeader(204)
}
