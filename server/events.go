package main

import (
	"fmt"
	"net/http"
	"sync"
	"time"
)

type eventHub struct {
	mu      sync.Mutex
	clients map[string]map[chan struct{}]bool
}

func (h *eventHub) subscribe(uid string) (chan struct{}, func(), bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients == nil {
		h.clients = map[string]map[chan struct{}]bool{}
	}
	if h.clients[uid] == nil {
		h.clients[uid] = map[chan struct{}]bool{}
	}
	if len(h.clients[uid]) >= 4 {
		return nil, func() {}, false
	}
	channel := make(chan struct{}, 1)
	h.clients[uid][channel] = true
	return channel, func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		delete(h.clients[uid], channel)
		if len(h.clients[uid]) == 0 {
			delete(h.clients, uid)
		}
	}, true
}

func (h *eventHub) publish(uids []string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, uid := range uids {
		for channel := range h.clients[uid] {
			select {
			case channel <- struct{}{}:
			default:
			}
		}
	}
}

func (b *backend) stream(w http.ResponseWriter, r *http.Request, user identity) {
	channel, unsubscribe, ok := b.events.subscribe(user.UID)
	if !ok {
		fail(w, 429, "too_many_connections", "연결을 잠시 후 다시 시도해주세요.")
		return
	}
	defer unsubscribe()
	controller := http.NewResponseController(w)
	_ = controller.SetWriteDeadline(time.Time{})
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	fmt.Fprint(w, "event: ready\ndata: {}\n\n")
	if err := controller.Flush(); err != nil {
		return
	}
	heartbeat := time.NewTicker(20 * time.Second)
	defer heartbeat.Stop()
	expires := time.NewTimer(time.Until(time.Unix(user.Expires, 0)))
	defer expires.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-expires.C:
			return
		case <-heartbeat.C:
			fmt.Fprint(w, ": keepalive\n\n")
		case <-channel:
			fmt.Fprint(w, "event: changed\ndata: {}\n\n")
		}
		if err := controller.Flush(); err != nil {
			return
		}
	}
}
