package main

import (
	"time"
)

type User struct {
	ID           int       `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"` // Nie wysyłamy hasła w JSON
	PublicKey    string    `json:"public_key"`
	IsAdmin      bool      `json:"is_admin"`
	IsVisible    bool      `json:"is_visible"`
	IsOnline     bool      `json:"is_online"`
	CreatedAt    time.Time `json:"created_at"`
}

type Message struct {
	ID               int       `json:"id"`
	SenderID         int       `json:"sender_id"`
	ReceiverID       int       `json:"receiver_id"`
	EncryptedContent string    `json:"encrypted_content"`
	EncryptedAesKey  string    `json:"encrypted_aes_key"`
	IsDelivered      bool      `json:"is_delivered"`
	CreatedAt        time.Time `json:"created_at"`
}

// Struktury dla REST API
type AuthRequest struct {
	Username  string `json:"username"`
	Password  string `json:"password"`
	PublicKey string `json:"public_key,omitempty"` // Tylko przy rejestracji
	IsVisible bool   `json:"is_visible"`           // Tylko przy rejestracji
}

type SettingsRequest struct {
	IsVisible bool `json:"is_visible"`
}

type AuthResponse struct {
	Token   string `json:"token"`
	IsAdmin bool   `json:"is_admin"`
}

// Struktury dla protokołu WebSocket
type WsEvent struct {
	Type             string      `json:"type"`
	Token            string      `json:"token,omitempty"`
	ReceiverUsername string      `json:"receiver_username,omitempty"`
	EncryptedContent string      `json:"encrypted_content,omitempty"`
	SearchQuery      string      `json:"search_query,omitempty"`
	Usernames        []string    `json:"usernames,omitempty"`
	LastMessageID    int         `json:"last_message_id,omitempty"`
	MessageID        int         `json:"message_id,omitempty"`
	Users            []User      `json:"users,omitempty"`
	Messages         []WsMessage `json:"messages,omitempty"`
}

type WsMessage struct {
	MessageID        int    `json:"message_id"`
	SenderUsername   string `json:"sender_username"`
	SenderPublicKey  string `json:"sender_public_key,omitempty"`
	EncryptedContent string `json:"encrypted_content"`
	Timestamp        string `json:"timestamp"`
}
