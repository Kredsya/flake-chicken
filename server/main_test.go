package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWebAndHealth(t *testing.T) {
	dir := t.TempDir()
	for name, content := range map[string]string{
		"index.html":    "<title>Flake Chicken</title>",
		"manifest.json": `{"display":"standalone"}`,
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	handler := newHandler(dir)
	for _, tc := range []struct {
		path   string
		status int
		body   string
	}{
		{"/", http.StatusOK, "Flake Chicken"},
		{"/manifest.json", http.StatusOK, `"standalone"`},
		{"/healthz", http.StatusOK, `"status":"ok"`},
		{"/missing.js", http.StatusNotFound, "404"},
	} {
		t.Run(tc.path, func(t *testing.T) {
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, tc.path, nil))
			if response.Code != tc.status || !strings.Contains(response.Body.String(), tc.body) {
				t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
			}
		})
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodHead, "/", nil))
	if response.Code != http.StatusOK || response.Body.Len() != 0 || response.Header().Get("Cache-Control") != "no-cache" {
		t.Fatalf("HEAD /: status=%d headers=%v body=%s", response.Code, response.Header(), response.Body.String())
	}
}

func TestAPIWithoutWebDirectory(t *testing.T) {
	response := httptest.NewRecorder()
	newHandler("").ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/", nil))
	if response.Code != http.StatusNotFound {
		t.Fatalf("API-only root status=%d", response.Code)
	}
}
