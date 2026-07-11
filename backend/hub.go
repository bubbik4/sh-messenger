package main

import (
	"log"
	"sync"

	"github.com/gorilla/websocket"
)

type Client struct {
	Conn     *websocket.Conn
	Username string
}

type Hub struct {
	clients map[string]*Client // mapowanie username -> Client
	mu      sync.RWMutex
}

var globalHub = &Hub{
	clients: make(map[string]*Client),
}

func (h *Hub) Register(client *Client) {
	h.mu.Lock()
	h.clients[client.Username] = client
	h.mu.Unlock()
	log.Printf("Klient zarejestrowany w Hubie: %s", client.Username)
}

func (h *Hub) Unregister(client *Client) {
	h.mu.Lock()
	if c, ok := h.clients[client.Username]; ok && c == client {
		delete(h.clients, client.Username)
		log.Printf("Klient wyrejestrowany z Huba: %s", client.Username)
	}
	h.mu.Unlock()
}

func (h *Hub) SendToUser(username string, message WsEvent) bool {
	h.mu.RLock()
	client, ok := h.clients[username]
	h.mu.RUnlock()

	if !ok {
		return false // Klient nie jest połączony
	}

	err := client.Conn.WriteJSON(message)
	if err != nil {
		log.Printf("Błąd wysyłania do %s: %v", username, err)
		client.Conn.Close()
		h.Unregister(client)
		return false
	}
	return true
}
