package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	webpush "github.com/SherClockHolmes/webpush-go"
	"golang.org/x/oauth2/google"
)

func (b *backend) setupVAPID() error {
	var encoded string
	err := b.db.QueryRow(`SELECT value FROM settings WHERE key='vapid'`).Scan(&encoded)
	if err == nil {
		var keys []string
		if err = json.Unmarshal([]byte(encoded), &keys); err != nil || len(keys) != 2 {
			return fmt.Errorf("invalid VAPID configuration")
		}
		b.vapidPrivate, b.vapidPublic = keys[0], keys[1]
		return nil
	}
	if err != sql.ErrNoRows {
		return err
	}
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	if err != nil {
		return err
	}
	data, _ := json.Marshal([]string{privateKey, publicKey})
	if _, err = b.db.Exec(`INSERT INTO settings(key,value) VALUES('vapid',?)`, string(data)); err != nil {
		return err
	}
	b.vapidPrivate, b.vapidPublic = privateKey, publicKey
	return nil
}

func validSubscription(subscription webpush.Subscription) bool {
	u, err := url.Parse(subscription.Endpoint)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Fragment != "" || (u.Port() != "" && u.Port() != "443") || len(subscription.Endpoint) > 4096 {
		return false
	}
	host := strings.ToLower(u.Hostname())
	if host != "fcm.googleapis.com" && host != "updates.push.services.mozilla.com" && host != "web.push.apple.com" && !strings.HasSuffix(host, ".notify.windows.com") {
		return false
	}
	key, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(subscription.Keys.P256dh, "="))
	if err != nil || len(key) != 65 || key[0] != 4 {
		return false
	}
	auth, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(subscription.Keys.Auth, "="))
	return err == nil && len(auth) == 16
}

func (b *backend) registerPush(w http.ResponseWriter, r *http.Request, user identity) {
	var input struct {
		Kind    string          `json:"kind"`
		Payload json.RawMessage `json:"payload"`
	}
	if !decode(w, r, &input) {
		return
	}
	if input.Kind == "web" {
		var subscription webpush.Subscription
		if json.Unmarshal(input.Payload, &subscription) != nil || !validSubscription(subscription) {
			fail(w, 400, "invalid_push_target", "푸시 등록 정보를 확인해주세요.")
			return
		}
	} else if input.Kind == "android" {
		var target struct {
			Token string `json:"token"`
		}
		if json.Unmarshal(input.Payload, &target) != nil || len(target.Token) < 20 || len(target.Token) > 4096 {
			fail(w, 400, "invalid_push_target", "푸시 등록 정보를 확인해주세요.")
			return
		}
	} else {
		fail(w, 400, "invalid_push_target", "지원하지 않는 알림 종류예요.")
		return
	}
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	id := hashToken(user.UID + ":" + input.Kind)
	_, err = tx.Exec(`INSERT INTO push_targets(id,uid,kind,payload,updated_at,active) VALUES(?,?,?,?,?,1)
	 ON CONFLICT(uid,kind) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at,active=1`, id, user.UID, input.Kind, string(input.Payload), b.now().Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	_, err = tx.Exec(`INSERT OR IGNORE INTO push_outbox(notification_id,target_id,next_attempt)
	 SELECT n.id,?,? FROM notifications n JOIN members m ON m.appointment_id=n.appointment_id AND m.uid=n.uid
	 WHERE n.uid=? AND n.created_at>? AND m.hidden=0`, id, b.now().Unix(), user.UID, b.now().Add(-24*time.Hour).Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	_, err = tx.Exec(`UPDATE push_outbox SET expired=0,next_attempt=? WHERE target_id=? AND delivered_at IS NULL
	 AND notification_id IN (SELECT id FROM notifications WHERE uid=? AND created_at>?)`, b.now().Unix(), id, user.UID, b.now().Add(-24*time.Hour).Unix())
	if err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	select {
	case b.wakeup <- struct{}{}:
	default:
	}
	respond(w, 200, map[string]bool{"registered": true})
}

func (b *backend) removePush(w http.ResponseWriter, r *http.Request, user identity) {
	kind := r.PathValue("kind")
	if kind != "android" && kind != "web" {
		fail(w, 400, "invalid_push_target", "알림 종류를 확인해주세요.")
		return
	}
	tx, err := b.db.BeginTx(r.Context(), nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`UPDATE push_targets SET active=0 WHERE uid=? AND kind=?`, user.UID, kind); err != nil {
		b.internal(w, err)
		return
	}
	if _, err = tx.Exec(`UPDATE push_outbox SET expired=1 WHERE target_id IN (SELECT id FROM push_targets WHERE uid=? AND kind=?) AND delivered_at IS NULL`, user.UID, kind); err != nil {
		b.internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		b.internal(w, err)
		return
	}
	w.WriteHeader(204)
}

type pushMessage struct {
	ID            string `json:"id"`
	AppointmentID string `json:"appointmentId"`
	Title         string `json:"title"`
	Body          string `json:"body"`
}
type pushJob struct {
	Message                 pushMessage
	TargetID, Kind, Payload string
	Attempts                int
}
type deliveryError struct{ status int }

func (e deliveryError) Error() string { return fmt.Sprintf("push service status=%d", e.status) }

func (b *backend) sendPush(ctx context.Context, job pushJob) error {
	if job.Kind == "web" {
		var subscription webpush.Subscription
		if err := json.Unmarshal([]byte(job.Payload), &subscription); err != nil {
			return err
		}
		if !validSubscription(subscription) {
			return deliveryError{410}
		}
		payload, _ := json.Marshal(job.Message)
		response, err := webpush.SendNotificationWithContext(ctx, payload, &subscription, &webpush.Options{
			Subscriber: b.cfg.PublicOrigin, VAPIDPublicKey: b.vapidPublic, VAPIDPrivateKey: b.vapidPrivate, TTL: 3600, HTTPClient: b.cfg.HTTPClient,
		})
		if err != nil {
			return err
		}
		defer response.Body.Close()
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		if response.StatusCode < 200 || response.StatusCode >= 300 {
			return deliveryError{response.StatusCode}
		}
		return nil
	}
	if b.cfg.ProjectID == "" {
		return fmt.Errorf("FCM project is not configured")
	}
	var target struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal([]byte(job.Payload), &target); err != nil {
		return err
	}
	tokens, err := google.DefaultTokenSource(ctx, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return fmt.Errorf("FCM credentials unavailable")
	}
	token, err := tokens.Token()
	if err != nil {
		return fmt.Errorf("FCM credential refresh failed")
	}
	body, _ := json.Marshal(map[string]any{"message": map[string]any{
		"token": target.Token, "notification": map[string]string{"title": job.Message.Title, "body": job.Message.Body},
		"data":    map[string]string{"appointmentId": job.Message.AppointmentID, "notificationId": job.Message.ID},
		"android": map[string]any{"priority": "high", "notification": map[string]string{"channel_id": "appointment_changes", "tag": job.Message.ID, "icon": "ic_stat_notification"}},
	}})
	request, err := http.NewRequestWithContext(ctx, "POST", "https://fcm.googleapis.com/v1/projects/"+url.PathEscape(b.cfg.ProjectID)+"/messages:send", bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+token.AccessToken)
	request.Header.Set("Content-Type", "application/json")
	response, err := b.cfg.HTTPClient.Do(request)
	if err != nil {
		return fmt.Errorf("FCM request failed")
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return deliveryError{response.StatusCode}
	}
	return nil
}

func (b *backend) deliverDue(ctx context.Context, send func(context.Context, pushJob) error) error {
	rows, err := b.db.Query(`SELECT n.id,n.appointment_id,n.title,n.body,p.id,p.kind,p.payload,o.attempts FROM push_outbox o
	 JOIN notifications n ON n.id=o.notification_id JOIN push_targets p ON p.id=o.target_id
	 WHERE o.delivered_at IS NULL AND o.expired=0 AND o.next_attempt<=? AND p.active=1 AND n.created_at>?
	 ORDER BY o.next_attempt LIMIT 20`, b.now().Unix(), b.now().Add(-24*time.Hour).Unix())
	if err != nil {
		return err
	}
	jobs := []pushJob{}
	for rows.Next() {
		var job pushJob
		if err = rows.Scan(&job.Message.ID, &job.Message.AppointmentID, &job.Message.Title, &job.Message.Body, &job.TargetID, &job.Kind, &job.Payload, &job.Attempts); err != nil {
			rows.Close()
			return err
		}
		jobs = append(jobs, job)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, job := range jobs {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		result, err := b.db.Exec(`UPDATE push_outbox SET attempts=attempts+1,next_attempt=? WHERE notification_id=? AND target_id=? AND next_attempt<=? AND delivered_at IS NULL AND expired=0`, b.now().Add(time.Minute).Unix(), job.Message.ID, job.TargetID, b.now().Unix())
		if err != nil {
			return err
		}
		count, _ := result.RowsAffected()
		if count != 1 {
			continue
		}
		deliveryCtx, cancel := context.WithTimeout(ctx, 12*time.Second)
		err = send(deliveryCtx, job)
		cancel()
		if err == nil {
			_, err = b.db.Exec(`UPDATE push_outbox SET delivered_at=? WHERE notification_id=? AND target_id=?`, b.now().Unix(), job.Message.ID, job.TargetID)
			if err != nil {
				return err
			}
			continue
		}
		log.Printf("push retry kind=%s attempt=%d: %v", job.Kind, job.Attempts+1, err)
		if failure, ok := err.(deliveryError); ok && (failure.status == 404 || failure.status == 410) {
			_, err = b.db.Exec(`UPDATE push_targets SET active=0 WHERE id=? AND payload=?`, job.TargetID, job.Payload)
			if err != nil {
				return err
			}
		}
		delay := time.Duration(15*(1<<min(job.Attempts, 8))) * time.Second
		_, err = b.db.Exec(`UPDATE push_outbox SET next_attempt=? WHERE notification_id=? AND target_id=?`, b.now().Add(delay).Unix(), job.Message.ID, job.TargetID)
		if err != nil {
			return err
		}
	}
	return nil
}

func (b *backend) runPushWorker(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		if err := b.deliverDue(ctx, b.sendPush); err != nil && ctx.Err() == nil {
			log.Printf("push worker: %v", err)
		}
		_, _ = b.db.Exec(`DELETE FROM challenges WHERE expires_at<?`, b.now().Unix())
		_, _ = b.db.Exec(`DELETE FROM sessions WHERE expires_at<?`, b.now().Unix())
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		case <-b.wakeup:
		}
	}
}
