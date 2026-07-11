package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

func main() {
	// Inicjalizacja połączenia z bazą danych
	if err := InitDB(); err != nil {
		log.Fatalf("Błąd inicjalizacji bazy danych: %v", err)
	}
	defer DB.Close()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Routing HTTP
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "message": "sh-messenger backend is running"})
	})

	// Endpoint WebSocket
	http.HandleFunc("/ws", handleWebSocket)

	log.Printf("Serwer startuje na porcie %s...", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Błąd serwera: %v", err)
	}
}
