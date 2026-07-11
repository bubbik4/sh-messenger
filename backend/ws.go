package main

import (
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Tymczasowo pozwalamy na wszystko (do celów dev)
	},
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Błąd połączenia websocket: %v", err)
		return
	}
	defer ws.Close()

	log.Println("Nowy klient połączony przez WebSocket")

	for {
		var msg map[string]interface{}
		err := ws.ReadJSON(&msg)
		if err != nil {
			log.Printf("Klient rozłączony: %v", err)
			break
		}
		log.Printf("Otrzymano wiadomość: %v", msg)

		err = ws.WriteJSON(msg)
		if err != nil {
			log.Printf("Błąd wysyłania: %v", err)
			break
		}
	}
}
