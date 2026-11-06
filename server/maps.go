package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

func (b *backend) route(w http.ResponseWriter, r *http.Request, user identity) {
	if !b.limit(w, r, "maps", 20) {
		return
	}
	a, err := ownAppointment(b.db, r.PathValue("id"), user.UID)
	if err != nil {
		fail(w, 404, "not_found", "약속을 찾을 수 없어요.")
		return
	}
	if b.cfg.MapsKey == "" {
		fail(w, 503, "maps_unavailable", "경로 조회가 준비되지 않았어요.")
		return
	}
	arrival, err := time.Parse(time.RFC3339Nano, a.StartsAt)
	if err != nil {
		b.internal(w, err)
		return
	}
	if arrival.Before(b.now().Add(-7*24*time.Hour)) || arrival.After(b.now().Add(100*24*time.Hour)) {
		fail(w, 422, "schedule_unavailable", "이 날짜의 대중교통 시간표는 아직 조회할 수 없어요.")
		return
	}
	if err = consumeMapsQuota(b.db, "routes", b.cfg.MapsDailyLimit, b.now()); err != nil {
		fail(w, 429, "maps_daily_limit", "오늘 경로 조회 한도에 도달했어요.")
		return
	}
	requestBody, _ := json.Marshal(map[string]any{
		"origin":      map[string]string{"address": a.Origin},
		"destination": map[string]string{"address": a.Destination},
		"travelMode":  "TRANSIT", "arrivalTime": arrival.UTC().Format(time.RFC3339),
		"languageCode": "ko-KR", "regionCode": "KR", "polylineQuality": "OVERVIEW",
	})
	request, err := http.NewRequestWithContext(r.Context(), http.MethodPost, "https://routes.googleapis.com/directions/v2:computeRoutes", bytes.NewReader(requestBody))
	if err != nil {
		b.internal(w, err)
		return
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Goog-Api-Key", b.cfg.MapsKey)
	request.Header.Set("X-Goog-FieldMask", "routes.duration,routes.polyline.encodedPolyline")
	response, err := b.cfg.HTTPClient.Do(request)
	if err != nil {
		fail(w, 502, "maps_failed", "경로를 불러오지 못했어요.")
		return
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		log.Printf("Routes API status=%d", response.StatusCode)
		fail(w, 502, "maps_failed", "대중교통 경로를 불러오지 못했어요.")
		return
	}
	var result struct {
		Routes []struct {
			Duration string `json:"duration"`
			Polyline struct {
				Encoded string `json:"encodedPolyline"`
			} `json:"polyline"`
		} `json:"routes"`
	}
	if err = json.NewDecoder(io.LimitReader(response.Body, 2*1024*1024)).Decode(&result); err != nil {
		fail(w, 502, "maps_failed", "경로 응답을 확인할 수 없어요.")
		return
	}
	if len(result.Routes) == 0 {
		fail(w, 422, "no_route", "조건에 맞는 대중교통 경로가 없어요.")
		return
	}
	journey := result.Routes[0]
	duration, err := time.ParseDuration(journey.Duration)
	if err != nil || duration < 0 || journey.Polyline.Encoded == "" || len(journey.Polyline.Encoded) > 10000 {
		fail(w, 502, "maps_failed", "경로 응답을 확인할 수 없어요.")
		return
	}
	if err = consumeMapsQuota(b.db, "static", b.cfg.MapsDailyLimit, b.now()); err != nil {
		fail(w, 429, "maps_daily_limit", "오늘 지도 조회 한도에 도달했어요.")
		return
	}
	values := url.Values{
		"size": {"128x142"}, "scale": {"2"}, "format": {"png"}, "maptype": {"roadmap"}, "language": {"ko"}, "region": {"KR"},
		"path":    {"weight:4|color:0x2487E8ff|enc:" + journey.Polyline.Encoded},
		"markers": {"size:small|color:green|" + a.Origin, "size:small|color:red|" + a.Destination},
		"key":     {b.cfg.MapsKey},
	}
	mapURL := "https://maps.googleapis.com/maps/api/staticmap?" + values.Encode()
	if len(mapURL) > 16000 {
		fail(w, 422, "route_too_large", "이 경로는 지도에 표시하기 너무 길어요.")
		return
	}
	request, err = http.NewRequestWithContext(r.Context(), http.MethodGet, mapURL, nil)
	if err != nil {
		b.internal(w, err)
		return
	}
	imageResponse, err := b.cfg.HTTPClient.Do(request)
	if err != nil {
		fail(w, 502, "map_failed", "지도를 불러오지 못했어요.")
		return
	}
	defer imageResponse.Body.Close()
	if imageResponse.StatusCode != 200 || !strings.HasPrefix(imageResponse.Header.Get("Content-Type"), "image/") {
		log.Printf("Static Maps API status=%d", imageResponse.StatusCode)
		fail(w, 502, "map_failed", "지도를 불러오지 못했어요.")
		return
	}
	image, err := io.ReadAll(io.LimitReader(imageResponse.Body, 2*1024*1024+1))
	if err != nil || len(image) > 2*1024*1024 {
		fail(w, 502, "map_failed", "지도 응답을 확인할 수 없어요.")
		return
	}
	// Google content is returned for immediate display, never written to SQLite
	// or a disk cache. The complete image, including attribution, is preserved.
	respond(w, 200, map[string]any{
		"durationSeconds": int(duration.Seconds()), "durationMinutes": int(math.Ceil(duration.Minutes())),
		"requestedArrivalTime": arrival.UTC().Format(time.RFC3339),
		"mapBase64":            base64.StdEncoding.EncodeToString(image), "imageWidth": 128, "imageHeight": 142,
		"version": a.Version, "source": "google_maps", "requestTime": strconv.FormatInt(b.now().Unix(), 10),
	})
}
