package main

import (
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Tymczasowo pozwalamy na wszystko
	},
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Błąd połączenia websocket: %v", err)
		return
	}
	defer ws.Close()

	var client *Client
	isAuthenticated := false

	log.Println("Nowy klient połączony przez WebSocket. Oczekiwanie na autoryzację...")

	for {
		var event WsEvent
		err := ws.ReadJSON(&event)
		if err != nil {
			log.Printf("Klient rozłączony: %v", err)
			break
		}

		if !isAuthenticated {
			if event.Type == "auth" && event.Token != "" {
				username, err := verifyJWT(event.Token)
				if err != nil {
					log.Printf("Błędny token JWT: %v", err)
					ws.WriteJSON(WsEvent{Type: "error", EncryptedContent: "Invalid token"})
					break // Rozłączamy intruza
				}

				// Uwierzytelniono pomyślnie
				isAuthenticated = true
				client = &Client{Conn: ws, Username: username}
				globalHub.Register(client)
				client.WriteJSON(WsEvent{Type: "auth_success"})
			} else {
				log.Println("Oczekiwano eventu auth. Rozłączanie.")
				break
			}
			continue
		}

		// Obsługa zdarzeń PO autoryzacji
		switch event.Type {
		case "get_users":
			users, err := GetAllUsers()
			if err != nil {
				log.Printf("Błąd pobierania użytkowników: %v", err)
				continue
			}
			client.WriteJSON(WsEvent{Type: "user_list", Users: users})

		case "sync_messages":
			user, _ := GetUserByUsername(client.Username)
			msgs, err := GetUndeliveredMessages(user.ID)
			if err == nil && len(msgs) > 0 {
				client.WriteJSON(WsEvent{Type: "sync_messages", Messages: msgs})
				MarkMessagesAsDelivered(user.ID)
			}

		case "send_message":
			receiver, err := GetUserByUsername(event.ReceiverUsername)
			if err != nil {
				log.Printf("Odbiorca nie istnieje: %v", err)
				continue
			}
			sender, _ := GetUserByUsername(client.Username)

			// Zapis do bazy
			err = SaveMessage(sender.ID, receiver.ID, event.EncryptedContent)
			if err != nil {
				log.Printf("Błąd zapisu wiadomości: %v", err)
				continue
			}

			// Próba wysłania na żywo
			delivered := globalHub.SendToUser(receiver.Username, WsEvent{
				Type:             "new_message",
				ReceiverUsername: sender.Username, // Kto wysłał (aby odbiorca wiedział)
				EncryptedContent: event.EncryptedContent,
				Messages: []WsMessage{
					{
						SenderUsername:   sender.Username,
						EncryptedContent: event.EncryptedContent,
						Timestamp:        time.Now().Format(time.RFC3339),
					},
				},
			})

			if delivered {
				MarkMessagesAsDelivered(receiver.ID)
			}
		}
	}

	if client != nil {
		globalHub.Unregister(client)
	}
}
