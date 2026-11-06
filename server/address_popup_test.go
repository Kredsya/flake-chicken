package main

import (
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func launchPopup(t *testing.T, b *backend, d *testDevice) map[string]any {
	t.Helper()
	w := callAPI(b, d, "POST", "/api/address-popup", map[string]any{})
	expectStatus(t, w, 200)
	return decodeBody[map[string]any](t, w)
}
func popupCallback(b *backend, path string, values url.Values, origin string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("POST", path, strings.NewReader(values.Encode()))
	r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	r.Header.Set("Origin", origin)
	w := httptest.NewRecorder()
	b.handler("").ServeHTTP(w, r)
	return w
}
func TestAddressPopupIsBoundToUserAndExpiringSecret(t *testing.T) {
	b := testBackend(t)
	b.cfg.JusoKey = "test-popup-key"
	owner, other := newTestDevice(t, "android"), newTestDevice(t, "web")
	login(t, b, owner)
	login(t, b, other)
	expectStatus(t, callAPI(b, nil, "POST", "/api/address-popup", map[string]any{}), 401)
	launch := launchPopup(t, b, owner)
	path := launch["url"].(string)
	id := launch["id"].(string)
	r := httptest.NewRequest("GET", path, nil)
	w := httptest.NewRecorder()
	b.handler("").ServeHTTP(w, r)
	expectStatus(t, w, 200)
	body := w.Body.String()
	if !strings.Contains(body, jusoPopupURL) || !strings.Contains(body, `name="confmKey" value="test-popup-key"`) || !strings.Contains(body, path) {
		t.Fatal("wrong official popup form")
	}
	if w.Header().Get("Cache-Control") != "no-store" || !strings.Contains(w.Header().Get("Content-Security-Policy"), "form-action https://business.juso.go.kr") {
		t.Fatal("unsafe popup document")
	}
	expectStatus(t, callAPI(b, other, "GET", "/api/address-popup/"+id, nil), 410)
	status := decodeBody[map[string]any](t, callAPI(b, owner, "GET", "/api/address-popup/"+id, nil))
	if status["ready"] != false || status["address"] != nil {
		t.Fatal("result leaked before selection")
	}
	wrong := path[:len(path)-1] + "!"
	w = httptest.NewRecorder()
	b.handler("").ServeHTTP(w, httptest.NewRequest("GET", wrong, nil))
	expectStatus(t, w, 410)
	b.now = func() time.Time { return time.Now().Add(11 * time.Minute) }
	w = httptest.NewRecorder()
	b.handler("").ServeHTTP(w, httptest.NewRequest("GET", path, nil))
	expectStatus(t, w, 410)
	expectStatus(t, callAPI(b, owner, "GET", "/api/address-popup/"+id, nil), 410)
}
func TestAddressPopupCallbackKeepsFirstSelectionAndNeverExecutesAddressText(t *testing.T) {
	b := testBackend(t)
	b.cfg.JusoKey = "test-popup-key"
	owner := newTestDevice(t, "android")
	login(t, b, owner)
	launch := launchPopup(t, b, owner)
	path := launch["url"].(string)
	id := launch["id"].(string)
	form := url.Values{"inputYn": {"Y"}, "roadAddrPart1": {"서울특별시 종로구 세종대로 209"}, "addrDetail": {"3층"}, "zipNo": {"03171"}}
	expectStatus(t, popupCallback(b, path, form, "https://attacker.example"), 403)
	w := popupCallback(b, path, form, "https://business.juso.go.kr")
	expectStatus(t, w, 200)
	if strings.Contains(w.Body.String(), "세종대로") || strings.Contains(w.Body.String(), "test-popup-key") {
		t.Fatal("sensitive values embedded in callback HTML")
	}
	result := decodeBody[struct {
		Ready   bool            `json:"ready"`
		Address selectedAddress `json:"address"`
	}](t, callAPI(b, owner, "GET", "/api/address-popup/"+id, nil))
	if !result.Ready || result.Address.RoadAddress != "서울특별시 종로구 세종대로 209 3층" || result.Address.ZipCode != "03171" {
		t.Fatal("selection not delivered")
	}
	form.Set("roadAddrPart1", "다른 주소")
	expectStatus(t, popupCallback(b, path, form, "https://business.juso.go.kr"), 200)
	next := decodeBody[struct {
		Address selectedAddress `json:"address"`
	}](t, callAPI(b, owner, "GET", "/api/address-popup/"+id, nil))
	if next.Address != result.Address {
		t.Fatal("completed selection overwritten")
	}
	expectStatus(t, callAPI(b, owner, "DELETE", "/api/address-popup/"+id, nil), 204)
	if countRows(t, b, "address_popups") != 0 {
		t.Fatal("temporary address retained")
	}
	expectStatus(t, callAPI(b, owner, "GET", "/api/address-popup/"+id, nil), 410)
	// Invalid, duplicate and oversized provider data must not create a result.
	launch = launchPopup(t, b, owner)
	path = launch["url"].(string)
	form.Set("zipNo", "bad")
	expectStatus(t, popupCallback(b, path, form, "https://business.juso.go.kr"), 400)
	form.Set("zipNo", "03171")
	form["roadAddrPart1"] = []string{"하나", "둘"}
	expectStatus(t, popupCallback(b, path, form, "https://business.juso.go.kr"), 400)
	form.Set("roadAddrPart1", strings.Repeat("가", 121))
	expectStatus(t, popupCallback(b, path, form, "https://business.juso.go.kr"), 400)
}
func TestAddressPopupMissingKeyAndConcurrencyLimit(t *testing.T) {
	b := testBackend(t)
	owner := newTestDevice(t, "android")
	login(t, b, owner)
	expectStatus(t, callAPI(b, owner, "POST", "/api/address-popup", map[string]any{}), 503)
	b.cfg.JusoKey = "test-popup-key"
	for range 4 {
		launchPopup(t, b, owner)
	}
	expectStatus(t, callAPI(b, owner, "POST", "/api/address-popup", map[string]any{}), 429)
}
