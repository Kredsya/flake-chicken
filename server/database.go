package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

func openDatabase(path string) (*sql.DB, error) {
	if path != ":memory:" {
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			return nil, err
		}
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	_, err = db.Exec(`
		PRAGMA foreign_keys=ON;
		PRAGMA busy_timeout=5000;
		PRAGMA journal_mode=WAL;
		PRAGMA synchronous=FULL;
		PRAGMA cache_size=-2048;
		CREATE TABLE IF NOT EXISTS users (
		 uid TEXT PRIMARY KEY, salt BLOB NOT NULL, public_key BLOB NOT NULL UNIQUE,
		 platform TEXT NOT NULL CHECK(platform IN ('android','web')), created_at INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS challenges (
		 id TEXT PRIMARY KEY, uid TEXT NOT NULL, salt BLOB NOT NULL, public_key BLOB NOT NULL,
		 platform TEXT NOT NULL, payload TEXT NOT NULL, expires_at INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS sessions (
		 token_hash TEXT PRIMARY KEY, uid TEXT NOT NULL REFERENCES users(uid), expires_at INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS appointments (
		 id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, owner TEXT NOT NULL REFERENCES users(uid),
		 title TEXT NOT NULL, starts_at TEXT NOT NULL, destination TEXT NOT NULL,
		 version INTEGER NOT NULL DEFAULT 1, cancelled_at INTEGER,
		 request_id TEXT NOT NULL, request_hash TEXT NOT NULL, created_at INTEGER NOT NULL,
		 UNIQUE(owner, request_id));
		CREATE TABLE IF NOT EXISTS members (
		 appointment_id TEXT NOT NULL REFERENCES appointments(id), uid TEXT NOT NULL REFERENCES users(uid),
		 display_name TEXT NOT NULL, origin TEXT NOT NULL, choice INTEGER NOT NULL DEFAULT 0,
		 hidden INTEGER NOT NULL DEFAULT 0, joined_at INTEGER NOT NULL,
		 PRIMARY KEY(appointment_id, uid));
		CREATE INDEX IF NOT EXISTS members_user ON members(uid, hidden);
		CREATE TABLE IF NOT EXISTS notifications (
		 id TEXT PRIMARY KEY, appointment_id TEXT NOT NULL REFERENCES appointments(id),
		 uid TEXT NOT NULL REFERENCES users(uid), title TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL,
		 UNIQUE(appointment_id, uid));
		CREATE TABLE IF NOT EXISTS push_targets (
		 id TEXT PRIMARY KEY, uid TEXT NOT NULL REFERENCES users(uid), kind TEXT NOT NULL,
		 payload TEXT NOT NULL, updated_at INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1, UNIQUE(uid, kind));
		CREATE TABLE IF NOT EXISTS push_outbox (
		 notification_id TEXT NOT NULL REFERENCES notifications(id), target_id TEXT NOT NULL REFERENCES push_targets(id),
		 attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL,
		 delivered_at INTEGER, expired INTEGER NOT NULL DEFAULT 0,
		 PRIMARY KEY(notification_id, target_id));
		CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
		CREATE TABLE IF NOT EXISTS maps_usage (day TEXT NOT NULL, kind TEXT NOT NULL, count INTEGER NOT NULL,
		 PRIMARY KEY(day,kind));
	`)
	if err != nil {
		db.Close()
		return nil, err
	}
	if path != ":memory:" {
		if err = os.Chmod(path, 0600); err != nil {
			db.Close()
			return nil, err
		}
	}
	return db, nil
}

func randomHex(size int) string {
	data := make([]byte, size)
	if _, err := rand.Read(data); err != nil {
		panic(err)
	}
	return hex.EncodeToString(data)
}

func randomToken() string {
	data := make([]byte, 32)
	if _, err := rand.Read(data); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(data)
}

func randomCode() string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	data := make([]byte, 8)
	if _, err := rand.Read(data); err != nil {
		panic(err)
	}
	for i := range data {
		data[i] = alphabet[int(data[i])%len(alphabet)]
	}
	return string(data)
}

func consumeMapsQuota(db *sql.DB, kind string, limit int, now time.Time) error {
	result, err := db.Exec(`INSERT INTO maps_usage(day,kind,count) VALUES(?,?,1)
	 ON CONFLICT(day,kind) DO UPDATE SET count=count+1 WHERE count < ?`,
		now.UTC().Format("2006-01-02"), kind, limit)
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if count != 1 {
		return fmt.Errorf("maps daily limit reached")
	}
	return nil
}
