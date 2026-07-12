package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
)

var fcmClient *messaging.Client

// userTokens przechowuje tokeny FCM przypisane do danego użytkownika
// W prostej wersji przechowujemy w pamięci, podobnie jak użytkowników.
var userTokens = make(map[string]string)

func initFirebase() {
	app, err := firebase.NewApp(context.Background(), nil)
	if err != nil {
		log.Printf("Błąd inicjalizacji Firebase Admin SDK: %v\n", err)
		return
	}

	client, err := app.Messaging(context.Background())
	if err != nil {
		log.Printf("Błąd pobierania klienta Messaging: %v\n", err)
		return
	}

	fcmClient = client
	log.Println("Firebase Admin SDK zainicjalizowane poprawnie")
}

func handleFCMToken(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	tokenString := r.Header.Get("Authorization")
	if tokenString == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	tokenParts := strings.Split(tokenString, " ")
	if len(tokenParts) != 2 || tokenParts[0] != "Bearer" {
		http.Error(w, "Invalid token format", http.StatusUnauthorized)
		return
	}

	claims, err := verifyJWT(tokenParts[1])
	if err != nil {
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}
	username := claims.Username

	var req struct {
		Token string `json:"token"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	if req.Token != "" {
		mutex.Lock()
		userTokens[username] = req.Token
		mutex.Unlock()
		log.Printf("Zapisano token FCM dla użytkownika: %s", username)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func sendPushNotification(toUsername, senderUsername string) {
	if fcmClient == nil {
		return
	}

	mutex.RLock()
	token, ok := userTokens[toUsername]
	mutex.RUnlock()

	if !ok || token == "" {
		return
	}

	message := &messaging.Message{
		Notification: &messaging.Notification{
			Title: "Nowa bezpieczna wiadomość",
			Body:  "Masz nową wiadomość od " + senderUsername,
		},
		Token: token,
	}

	_, err := fcmClient.Send(context.Background(), message)
	if err != nil {
		log.Printf("Błąd wysyłania powiadomienia Push do %s: %v", toUsername, err)
	}
}
