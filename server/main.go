package main

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func newHandler(webDir string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		if err := json.NewEncoder(w).Encode(map[string]string{
			"status": "ok", "service": "flake-chicken",
		}); err != nil {
			log.Printf("health response: %v", err)
		}
	})
	if webDir != "" {
		files := http.FileServer(http.Dir(webDir))
		mux.Handle("GET /", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-cache")
			files.ServeHTTP(w, r)
		}))
	}
	return mux
}

func main() {
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	origin := strings.TrimRight(os.Getenv("PUBLIC_ORIGIN"), "/")
	development := os.Getenv("DEVELOPMENT") == "1"
	if !strings.HasPrefix(origin, "https://") && !development {
		log.Fatal("PUBLIC_ORIGIN must be an HTTPS origin")
	}
	path := os.Getenv("DATABASE_PATH")
	if path == "" {
		path = "/var/lib/flake-chicken/app.db"
	}
	limit, _ := strconv.Atoi(os.Getenv("MAPS_DAILY_LIMIT"))
	api, err := newBackend(path, serverConfig{PublicOrigin: origin, Development: development,
		MapsKey: os.Getenv("GOOGLE_MAPS_API_KEY"), MapsDailyLimit: limit, ProjectID: os.Getenv("GOOGLE_CLOUD_PROJECT")})
	if err != nil {
		log.Fatal(err)
	}
	defer api.db.Close()
	server := &http.Server{
		Addr:              addr,
		Handler:           api.handler(os.Getenv("WEB_DIR")),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      40 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    16 * 1024,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	server.BaseContext = func(net.Listener) context.Context { return ctx }
	workerDone := make(chan struct{})
	go func() { defer close(workerDone); api.runPushWorker(ctx) }()
	shutdownDone := make(chan struct{})
	go func() {
		defer close(shutdownDone)
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("shutdown: %v", err)
		}
	}()
	log.Printf("listening on %s", addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
	stop()
	<-shutdownDone
	<-workerDone
}
