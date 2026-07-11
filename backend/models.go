package main

import (
	"time"
)

type User struct {
	ID        int       `json:"id"`
	Username  string    `json:"username"`
	PublicKey string    `json:"public_key"`
	CreatedAt time.Time `json:"created_at"`
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
