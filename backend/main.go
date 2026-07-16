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

	// Inicjalizacja kluczy bezpieczeństwa
	InitAuth()

	// Inicjalizacja konta administratora
	SeedAdmin()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Middleware do obsługi CORS - model scentralizowany
	corsMiddleware := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "https://chat.bubikit.pl" {
				http.Error(w, "Zabroniony Origin", http.StatusForbidden)
				return
			}

			w.Header().Set("Access-Control-Allow-Origin", "https://chat.bubikit.pl")
			w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
			w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, Origin")

			if r.Method == "OPTIONS" {
				return
			}

			next.ServeHTTP(w, r)
		})
	}

	mux := http.NewServeMux()

	initFirebase()

	// Routing HTTP dla Niezalogowanych
	mux.HandleFunc("/api/register", handleRegister)
	mux.HandleFunc("/api/login", handleLogin)
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "message": "sh-messenger backend is running"})
	})

	// Routing HTTP dla Zalogowanych
	mux.HandleFunc("/api/ws-ticket", handleWsTicket)
	mux.HandleFunc("/api/change_password", handleChangePassword)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "message": "sh-messenger backend is running"})
	})
	mux.HandleFunc("/api/settings/visibility", handleUpdateVisibility)
	mux.HandleFunc("/api/upload", handleFileUpload)
	mux.HandleFunc("/api/download/", handleFileDownload)
	mux.HandleFunc("/api/fcm/token", handleFCMToken)

	// Routing HTTP dla Admina
	mux.HandleFunc("/api/admin/users", adminMiddleware(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			handleAdminGetUsers(w, r)
		} else if r.Method == http.MethodDelete {
			handleAdminDeleteUser(w, r)
		} else {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	}))
	mux.HandleFunc("/api/admin/change-password", adminMiddleware(handleAdminChangePassword))

	// Endpoint WebSocket
	mux.HandleFunc("/ws", handleWebSocket)

	log.Printf("Serwer startuje na porcie %s...", port)
	if err := http.ListenAndServe(":"+port, corsMiddleware(mux)); err != nil {
		log.Fatalf("Błąd serwera: %v", err)
	}
}
