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

	// Middleware do obsługi CORS
	corsMiddleware := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
			w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization")

			if r.Method == "OPTIONS" {
				return
			}

			next.ServeHTTP(w, r)
		})
	}

	mux := http.NewServeMux()

	// Routing HTTP
	mux.HandleFunc("/api/register", handleRegister)
	mux.HandleFunc("/api/login", handleLogin)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "message": "sh-messenger backend is running"})
	})

	// Endpoint WebSocket
	mux.HandleFunc("/ws", handleWebSocket)

	log.Printf("Serwer startuje na porcie %s...", port)
	if err := http.ListenAndServe(":"+port, corsMiddleware(mux)); err != nil {
		log.Fatalf("Błąd serwera: %v", err)
	}
}
