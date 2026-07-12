package main

import (
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		return origin == "https://chat.bubikit.pl"
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

	const pongWait = 60 * time.Second
	ws.SetReadDeadline(time.Now().Add(pongWait))
	ws.SetPongHandler(func(string) error { ws.SetReadDeadline(time.Now().Add(pongWait)); return nil })

	for {
		var event WsEvent
		err := ws.ReadJSON(&event)
		if err != nil {
			log.Printf("Klient rozłączony: %v", err)
			break
		}
		
		// Reset read deadline on any JSON message as well
		ws.SetReadDeadline(time.Now().Add(pongWait))

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
		case "ping":
			// Zwracamy pong, żeby serwery proxy (np. Nginx) wiedziały, że backend żyje
			client.WriteJSON(WsEvent{Type: "pong"})
			continue

		case "get_users":
			users, err := GetVisibleUsers()
			if err != nil {
				log.Printf("Błąd pobierania użytkowników: %v", err)
				continue
			}
			for i := range users {
				users[i].IsOnline = globalHub.IsUserOnline(users[i].Username)
			}
			client.WriteJSON(WsEvent{Type: "user_list", Users: users})

		case "search_users":
			if event.SearchQuery != "" {
				users, err := SearchUser(event.SearchQuery)
				if err == nil {
					for i := range users {
						users[i].IsOnline = globalHub.IsUserOnline(users[i].Username)
					}
					client.WriteJSON(WsEvent{Type: "search_results", Users: users})
				}
			}

		case "get_specific_users":
			if len(event.Usernames) > 0 {
				users, err := GetUsersByUsernames(event.Usernames)
				if err == nil {
					for i := range users {
						users[i].IsOnline = globalHub.IsUserOnline(users[i].Username)
					}
					client.WriteJSON(WsEvent{Type: "specific_users_list", Users: users})
				}
			}

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
						SenderPublicKey:  sender.PublicKey,
						EncryptedContent: event.EncryptedContent,
						Timestamp:        time.Now().Format(time.RFC3339),
					},
				},
			})

			if delivered {
				MarkMessagesAsDelivered(receiver.ID)
			} else {
				// Użytkownik jest offline, wyślij powiadomienie Push
				sendPushNotification(receiver.Username, sender.Username)
			}
		}
	}

	if client != nil {
		globalHub.Unregister(client)
	}
}
