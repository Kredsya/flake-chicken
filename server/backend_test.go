package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

const testOrigin = "https://35.212.249.154"

type testDevice struct {
	key                      *ecdsa.PrivateKey
	uid, token, salt, public string
	cookie                   *http.Cookie
	platform                 string
}

func newTestDevice(t *testing.T, platform string) *testDevice {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	public, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	salt := make([]byte, 32)
	rand.Read(salt)
	return &testDevice{key: key, uid: identityHash(salt, public), salt: base64.StdEncoding.EncodeToString(salt), public: base64.StdEncoding.EncodeToString(public), platform: platform}
}
func testBackend(t *testing.T) *backend {
	t.Helper()
	b, err := newBackend(filepath.Join(t.TempDir(), "app.db"), serverConfig{PublicOrigin: testOrigin})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { b.db.Close() })
	return b
}
func callAPI(b *backend, d *testDevice, method, path string, body any) *httptest.ResponseRecorder {
	data, _ := json.Marshal(body)
	r := httptest.NewRequest(method, testOrigin+path, bytes.NewReader(data))
	r.RemoteAddr = "192.0.2.1:1234"
	if d != nil {
		if d.token != "" {
			r.Header.Set("Authorization", "Bearer "+d.token)
		} else if d.cookie != nil {
			r.AddCookie(d.cookie)
		}
		if d.platform == "web" {
			r.Header.Set("Origin", testOrigin)
		}
	}
	w := httptest.NewRecorder()
	b.handler("").ServeHTTP(w, r)
	return w
}
func expectStatus(t *testing.T, w *httptest.ResponseRecorder, expected int) {
	t.Helper()
	if w.Code != expected {
		t.Fatalf("status %d want %d: %s", w.Code, expected, w.Body.String())
	}
}
func decodeBody[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var out T
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out
}
func login(t *testing.T, b *backend, d *testDevice) {
	t.Helper()
	w := callAPI(b, d, "POST", "/api/auth/challenge", map[string]string{"uid": d.uid, "salt": d.salt, "publicKey": d.public, "platform": d.platform})
	expectStatus(t, w, 200)
	challenge := decodeBody[map[string]any](t, w)
	digest := sha256.Sum256([]byte(challenge["payload"].(string)))
	var signature []byte
	if d.platform == "web" {
		r, s, err := ecdsa.Sign(rand.Reader, d.key, digest[:])
		if err != nil {
			t.Fatal(err)
		}
		signature = make([]byte, 64)
		r.FillBytes(signature[:32])
		s.FillBytes(signature[32:])
	} else {
		signature, _ = ecdsa.SignASN1(rand.Reader, d.key, digest[:])
	}
	proof := map[string]string{"id": challenge["id"].(string), "signature": base64.StdEncoding.EncodeToString(signature)}
	w = callAPI(b, d, "POST", "/api/auth/verify", proof)
	expectStatus(t, w, 200)
	response := decodeBody[map[string]any](t, w)
	if d.platform == "android" {
		d.token = response["token"].(string)
	} else {
		if response["token"] != nil {
			t.Fatal("web token exposed")
		}
		d.cookie = w.Result().Cookies()[0]
		if !d.cookie.HttpOnly || !d.cookie.Secure || d.cookie.SameSite != http.SameSiteStrictMode || d.cookie.Name != sessionCookie {
			t.Fatal("unsafe cookie")
		}
	}
	expectStatus(t, callAPI(b, d, "POST", "/api/auth/verify", proof), 401)
}
func createTestAppointment(t *testing.T, b *backend, d *testDevice, choice bool) appointmentView {
	t.Helper()
	body := createInput{Title: "저녁", StartsAt: time.Now().Add(48 * time.Hour).Truncate(time.Second), Destination: "서울역", DisplayName: "나", Origin: "강남역", Choice: choice, RequestID: randomHex(16)}
	w := callAPI(b, d, "POST", "/api/appointments", body)
	expectStatus(t, w, 201)
	a := decodeBody[appointmentView](t, w)
	replay := callAPI(b, d, "POST", "/api/appointments", body)
	expectStatus(t, replay, 200)
	if decodeBody[appointmentView](t, replay).ID != a.ID {
		t.Fatal("duplicate create")
	}
	return a
}
func joinTest(t *testing.T, b *backend, d *testDevice, a appointmentView, choice bool) appointmentView {
	t.Helper()
	w := callAPI(b, d, "POST", "/api/invitations/"+a.InvitationCode+"/join", map[string]any{"displayName": "친구", "origin": "부산역", "choice": choice})
	expectStatus(t, w, 200)
	return decodeBody[appointmentView](t, w)
}
func countRows(t *testing.T, b *backend, table string) int {
	t.Helper()
	var n int
	if err := b.db.QueryRow("SELECT COUNT(*) FROM " + table).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestInstallationProofAndWebCSRF(t *testing.T) {
	b := testBackend(t)
	native := newTestDevice(t, "android")
	web := newTestDevice(t, "web")
	login(t, b, native)
	login(t, b, web)
	expectStatus(t, callAPI(b, native, "GET", "/api/appointments", nil), 200)
	expectStatus(t, callAPI(b, web, "GET", "/api/appointments", nil), 200)
	stolen := newTestDevice(t, "android")
	stolen.uid = native.uid
	expectStatus(t, callAPI(b, stolen, "POST", "/api/auth/challenge", map[string]string{"uid": stolen.uid, "salt": stolen.salt, "publicKey": stolen.public, "platform": "android"}), 400)
	w := callAPI(b, native, "POST", "/api/auth/challenge", map[string]string{"uid": native.uid, "salt": native.salt, "publicKey": native.public, "platform": "android"})
	expectStatus(t, w, 200)
	c := decodeBody[map[string]any](t, w)
	digest := sha256.Sum256([]byte(c["payload"].(string)))
	wrong, _ := ecdsa.SignASN1(rand.Reader, stolen.key, digest[:])
	expectStatus(t, callAPI(b, nil, "POST", "/api/auth/verify", map[string]any{"id": c["id"], "signature": base64.StdEncoding.EncodeToString(wrong)}), 401)
	r := httptest.NewRequest("PUT", testOrigin+"/api/push", strings.NewReader(`{}`))
	r.AddCookie(web.cookie)
	r.Header.Set("Origin", "https://attacker.example")
	out := httptest.NewRecorder()
	b.handler("").ServeHTTP(out, r)
	expectStatus(t, out, 403)
	r.Header.Del("Origin")
	out = httptest.NewRecorder()
	b.handler("").ServeHTTP(out, r)
	expectStatus(t, out, 401)
	var stored string
	if err := b.db.QueryRow(`SELECT token_hash FROM sessions WHERE uid=?`, native.uid).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored == native.token {
		t.Fatal("raw token stored")
	}
	b.now = func() time.Time { return time.Now().Add(31 * time.Minute) }
	expectStatus(t, callAPI(b, native, "GET", "/api/appointments", nil), 401)
}

func TestGMGRequiresTwoAndCancellationIsFinal(t *testing.T) {
	b := testBackend(t)
	owner := newTestDevice(t, "android")
	guest := newTestDevice(t, "android")
	login(t, b, owner)
	login(t, b, guest)
	a := createTestAppointment(t, b, owner, true)
	if a.IsCancelled || !a.MyChoice || a.ParticipantCount != 1 {
		t.Fatal("solo GMG cancelled")
	}
	if countRows(t, b, "notifications") != 0 {
		t.Fatal("solo notification")
	}
	a = joinTest(t, b, guest, a, true)
	if !a.IsCancelled || a.ParticipantCount != 2 {
		t.Fatal("both GMG not cancelled")
	}
	if countRows(t, b, "notifications") != 2 {
		t.Fatal("notifications must be per member")
	}
	joinTest(t, b, guest, a, true)
	expectStatus(t, callAPI(b, owner, "PUT", "/api/appointments/"+a.ID+"/choice", map[string]bool{"choice": false}), 409)
	expectStatus(t, callAPI(b, owner, "DELETE", "/api/appointments/"+a.ID, nil), 204)
	var list struct {
		Appointments []appointmentView `json:"appointments"`
	}
	list = decodeBody[struct {
		Appointments []appointmentView `json:"appointments"`
	}](t, callAPI(b, owner, "GET", "/api/appointments", nil))
	if len(list.Appointments) != 0 {
		t.Fatal("owner not hidden")
	}
	list = decodeBody[struct {
		Appointments []appointmentView `json:"appointments"`
	}](t, callAPI(b, guest, "GET", "/api/appointments", nil))
	if len(list.Appointments) != 1 || !list.Appointments[0].IsCancelled {
		t.Fatal("delete affected other member")
	}
	if countRows(t, b, "notifications") != 2 {
		t.Fatal("duplicate notification")
	}
}

func TestPrivateVotesCreatorEditsAndConcurrentConsensus(t *testing.T) {
	b := testBackend(t)
	owner := newTestDevice(t, "android")
	guest := newTestDevice(t, "android")
	other := newTestDevice(t, "android")
	login(t, b, owner)
	login(t, b, guest)
	login(t, b, other)
	a := createTestAppointment(t, b, owner, false)
	joinTest(t, b, guest, a, false)
	ownEvents, closeOwn, _ := b.events.subscribe(owner.uid)
	defer closeOwn()
	guestEvents, closeGuest, _ := b.events.subscribe(guest.uid)
	defer closeGuest()
	expectStatus(t, callAPI(b, owner, "PUT", "/api/appointments/"+a.ID+"/choice", map[string]bool{"choice": true}), 200)
	select {
	case <-ownEvents:
	default:
		t.Fatal("own sessions not updated")
	}
	select {
	case <-guestEvents:
		t.Fatal("private vote timing leaked")
	default:
	}
	w := callAPI(b, guest, "GET", "/api/appointments", nil)
	if strings.Contains(w.Body.String(), owner.uid) || strings.Contains(w.Body.String(), "choices") {
		t.Fatal("private member data leaked")
	}
	current, _ := ownAppointment(b.db, a.ID, guest.uid)
	if current.MyChoice || current.IsCancelled {
		t.Fatal("guest sees another vote")
	}
	edit := map[string]any{"title": "수정", "startsAt": a.StartsAt, "destination": "홍대입구역", "version": current.Version}
	expectStatus(t, callAPI(b, guest, "PATCH", "/api/appointments/"+a.ID, edit), 403)
	expectStatus(t, callAPI(b, other, "PUT", "/api/appointments/"+a.ID+"/choice", map[string]bool{"choice": true}), 404)
	expectStatus(t, callAPI(b, owner, "PATCH", "/api/appointments/"+a.ID, edit), 200)
	expectStatus(t, callAPI(b, owner, "PATCH", "/api/appointments/"+a.ID, edit), 409)
	expectStatus(t, callAPI(b, owner, "DELETE", "/api/appointments/"+a.ID, nil), 409)
	// Simultaneous final requests and retries create one durable event per member.
	var wg sync.WaitGroup
	responses := make(chan int, 4)
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			responses <- callAPI(b, guest, "PUT", "/api/appointments/"+a.ID+"/choice", map[string]bool{"choice": true}).Code
		}()
	}
	wg.Wait()
	close(responses)
	for status := range responses {
		if status != 200 {
			t.Fatalf("concurrent status %d", status)
		}
	}
	if countRows(t, b, "notifications") != 2 {
		t.Fatal("duplicate consensus")
	}
	current, _ = ownAppointment(b.db, a.ID, owner.uid)
	if !current.IsCancelled {
		t.Fatal("owner not updated")
	}
	expectStatus(t, callAPI(b, owner, "PATCH", "/api/appointments/"+a.ID, edit), 409)
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestArrivalRoutingQuotaAndNoPersistentProviderData(t *testing.T) {
	b := testBackend(t)
	owner := newTestDevice(t, "android")
	login(t, b, owner)
	a := createTestAppointment(t, b, owner, false)
	b.cfg.MapsKey = "server-only"
	b.cfg.MapsDailyLimit = 1
	calls := 0
	b.cfg.HTTPClient = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		calls++
		body := ""
		headers := http.Header{}
		switch r.URL.Host {
		case "routes.googleapis.com":
			var input map[string]any
			if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
				t.Fatal(err)
			}
			if input["arrivalTime"] != a.StartsAt || input["travelMode"] != "TRANSIT" || input["departureTime"] != nil {
				t.Fatal("incorrect arrival request")
			}
			if input["origin"].(map[string]any)["address"] != a.Origin {
				t.Fatal("wrong personal origin")
			}
			body = `{"routes":[{"duration":"2281s","polyline":{"encodedPolyline":"provider-polyline-sentinel"}}]}`
		case "maps.googleapis.com":
			if !strings.Contains(r.URL.Query().Get("path"), "provider-polyline-sentinel") || r.URL.Query().Get("zoom") != "" {
				t.Fatal("route not fitted")
			}
			body = "fake-png"
			headers.Set("Content-Type", "image/png")
		default:
			t.Fatal("unexpected provider")
		}
		return &http.Response{StatusCode: 200, Header: headers, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}
	w := callAPI(b, owner, "GET", "/api/appointments/"+a.ID+"/route", nil)
	expectStatus(t, w, 200)
	data := decodeBody[map[string]any](t, w)
	if data["durationMinutes"] != float64(39) || data["mapBase64"] != base64.StdEncoding.EncodeToString([]byte("fake-png")) {
		t.Fatal("bad routing result")
	}
	expectStatus(t, callAPI(b, owner, "GET", "/api/appointments/"+a.ID+"/route", nil), 429)
	if calls != 2 {
		t.Fatal("quota failed")
	}
	var sql string
	if err := b.db.QueryRow(`SELECT group_concat(sql) FROM sqlite_schema`).Scan(&sql); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(sql, "polyline") || strings.Contains(sql, "duration_minutes") {
		t.Fatal("provider cache persisted")
	}
	expectStatus(t, callAPI(b, nil, "GET", "/api/appointments/"+a.ID+"/route", nil), 401)
}

func TestPushOutboxSurvivesRestartAndRetriesWithoutDuplicates(t *testing.T) {
	path := filepath.Join(t.TempDir(), "app.db")
	b, err := newBackend(path, serverConfig{PublicOrigin: testOrigin})
	if err != nil {
		t.Fatal(err)
	}
	owner := newTestDevice(t, "android")
	guest := newTestDevice(t, "android")
	login(t, b, owner)
	login(t, b, guest)
	for _, d := range []*testDevice{owner, guest} {
		expectStatus(t, callAPI(b, d, "PUT", "/api/push", map[string]any{"kind": "android", "payload": map[string]string{"token": strings.Repeat(d.uid[:1], 40)}}), 200)
	}
	a := createTestAppointment(t, b, owner, true)
	joinTest(t, b, guest, a, true)
	if countRows(t, b, "push_outbox") != 2 {
		t.Fatal("missing durable deliveries")
	}
	public := b.vapidPublic
	b.db.Close()
	b, err = newBackend(path, serverConfig{PublicOrigin: testOrigin})
	if err != nil {
		t.Fatal(err)
	}
	defer b.db.Close()
	if b.vapidPublic != public {
		t.Fatal("VAPID identity changed")
	}
	failed := 0
	err = b.deliverDue(context.Background(), func(_ context.Context, j pushJob) error { failed++; return errors.New("temporary outage") })
	if err != nil || failed != 2 {
		t.Fatalf("retry setup: %v", err)
	}
	now := time.Now().Add(20 * time.Second)
	b.now = func() time.Time { return now }
	delivered := map[string]bool{}
	send := func(_ context.Context, j pushJob) error {
		if delivered[j.Message.ID] {
			t.Fatal("duplicate delivery")
		}
		delivered[j.Message.ID] = true
		return nil
	}
	if err = b.deliverDue(context.Background(), send); err != nil {
		t.Fatal(err)
	}
	if err = b.deliverDue(context.Background(), send); err != nil {
		t.Fatal(err)
	}
	if len(delivered) != 2 {
		t.Fatal("retry did not deliver both")
	}
	expectStatus(t, callAPI(b, owner, "PUT", "/api/push", map[string]any{"kind": "web", "payload": map[string]any{"endpoint": "https://127.0.0.1/metadata"}}), 400)
}
