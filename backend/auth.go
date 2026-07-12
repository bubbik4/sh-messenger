package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

var jwtKey = []byte(getEnvOrDefault("JWT_SECRET", "supersecretkey"))

func getEnvOrDefault(key, defaultVal string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultVal
}

type Claims struct {
	Username string `json:"username"`
	jwt.RegisteredClaims
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var req AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	if req.Username == "" || req.Password == "" || req.PublicKey == "" {
		http.Error(w, "Missing fields", http.StatusBadRequest)
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, "Błąd serwera", http.StatusInternalServerError)
		return
	}

	err = CreateUser(req.Username, string(hashedPassword), req.PublicKey, req.IsVisible)
	if err != nil {
		log.Printf("Błąd DB przy CreateUser: %v", err)
		http.Error(w, fmt.Sprintf("Błąd przy tworzeniu użytkownika: %v", err), http.StatusConflict)
		return
	}

	// Od razu logujemy użytkownika po rejestracji
	token, err := generateJWT(req.Username)
	if err != nil {
		http.Error(w, "Błąd generowania tokenu", http.StatusInternalServerError)
		return
	}

	// Broadcast the updated visible user list to connected clients
	if users, err := GetVisibleUsers(); err == nil {
		globalHub.Broadcast(WsEvent{Type: "user_list", Users: users})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(AuthResponse{
		Token:   token,
		IsAdmin: false,
	})
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	var req AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	user, err := GetUserByUsername(req.Username)
	if err != nil {
		http.Error(w, "User not found", http.StatusUnauthorized)
		return
	}

	err = bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password))
	if err != nil {
		http.Error(w, "Invalid password", http.StatusUnauthorized)
		return
	}

	// Aktualizacja klucza publicznego, jeśli urządzenie wygenerowało nowy (np. logowanie na nowej przeglądarce)
	if req.PublicKey != "" && req.PublicKey != user.PublicKey {
		_, err = DB.Exec(r.Context(), "UPDATE users SET public_key = $1 WHERE id = $2", req.PublicKey, user.ID)
		if err == nil {
			// Broadcast updated user list to all connected clients
			if users, err := GetVisibleUsers(); err == nil {
				globalHub.Broadcast(WsEvent{Type: "user_list", Users: users})
			}
		}
	}

	tokenString, err := generateJWT(req.Username)
	if err != nil {
		http.Error(w, "Error generating token", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(AuthResponse{
		Token:   tokenString,
		IsAdmin: user.IsAdmin,
	})
}

func generateJWT(username string) (string, error) {
	expirationTime := time.Now().Add(24 * 7 * time.Hour)
	claims := &Claims{
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtKey)
}

func verifyJWT(tokenString string) (string, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		return jwtKey, nil
	})

	if err != nil || !token.Valid {
		return "", err
	}

	return claims.Username, nil
}

func handleUpdateVisibility(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	authHeader := r.Header.Get("Authorization")
	if authHeader == "" || len(authHeader) < 8 {
		http.Error(w, "Missing token", http.StatusUnauthorized)
		return
	}
	tokenString := authHeader[7:]

	username, err := verifyJWT(tokenString)
	if err != nil {
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}

	var req SettingsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	err = UpdateUserVisibility(username, req.IsVisible)
	if err != nil {
		log.Printf("Błąd DB przy UpdateUserVisibility: %v", err)
		http.Error(w, "Error updating visibility", http.StatusInternalServerError)
		return
	}

	// Od razu rozgłaszamy zaktualizowaną listę użytkowników widocznych do wszystkich
	if users, err := GetVisibleUsers(); err == nil {
		globalHub.Broadcast(WsEvent{Type: "user_list", Users: users})
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"success"}`))
}

type UserChangePasswordRequest struct {
	OldPassword string `json:"old_password"`
	NewPassword string `json:"new_password"`
}

func handleChangePassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	authHeader := r.Header.Get("Authorization")
	if authHeader == "" || len(authHeader) < 8 {
		http.Error(w, "Missing token", http.StatusUnauthorized)
		return
	}
	tokenString := authHeader[7:]

	username, err := verifyJWT(tokenString)
	if err != nil {
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}

	var req UserChangePasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.OldPassword == "" || req.NewPassword == "" {
		http.Error(w, "Missing fields", http.StatusBadRequest)
		return
	}

	// Pobranie starego hasha
	var currentHash string
	err = DB.QueryRow(r.Context(), "SELECT password_hash FROM users WHERE username = $1", username).Scan(&currentHash)
	if err != nil {
		log.Printf("Błąd DB przy pobieraniu hasha dla zmiany hasła: %v", err)
		http.Error(w, "Internal error", http.StatusInternalServerError)
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(currentHash), []byte(req.OldPassword)); err != nil {
		http.Error(w, "Invalid old password", http.StatusUnauthorized)
		return
	}

	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, "Error hashing password", http.StatusInternalServerError)
		return
	}

	_, err = DB.Exec(r.Context(), "UPDATE users SET password_hash = $1 WHERE username = $2", string(newHash), username)
	if err != nil {
		log.Printf("Błąd DB przy zapisywaniu nowego hasła: %v", err)
		http.Error(w, "Error updating password", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"success"}`))
}
