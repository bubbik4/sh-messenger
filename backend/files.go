package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func generateFileID() string {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		log.Fatal(err)
	}
	return hex.EncodeToString(bytes)
}

func handleFileUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Wymagana autoryzacja (JWT)
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

	_, err := verifyJWT(tokenParts[1])
	if err != nil {
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}

	// Maksymalny rozmiar: 50MB (będzie to zaszyfrowany bełkot)
	r.ParseMultipartForm(50 << 20)

	file, _, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "Błąd pobierania pliku", http.StatusBadRequest)
		return
	}
	defer file.Close()

	fileID := generateFileID()
	uploadDir := "./downloads"

	// Upewnij się, że katalog istnieje
	if err := os.MkdirAll(uploadDir, os.ModePerm); err != nil {
		http.Error(w, "Błąd serwera przy zapisie", http.StatusInternalServerError)
		return
	}

	filePath := filepath.Join(uploadDir, fileID)
	dest, err := os.Create(filePath)
	if err != nil {
		http.Error(w, "Błąd zapisu pliku", http.StatusInternalServerError)
		return
	}
	defer dest.Close()

	if _, err := io.Copy(dest, file); err != nil {
		http.Error(w, "Błąd zapisywania danych pliku", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"file_id": fileID,
	})
}

func handleFileDownload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Wymagana autoryzacja - pliki to tajemnica, pomimo że są zaszyfrowane
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

	_, err := verifyJWT(tokenParts[1])
	if err != nil {
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}

	// Ścieżka to /api/download/{fileID}
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 4 {
		http.Error(w, "Brak identyfikatora pliku", http.StatusBadRequest)
		return
	}
	fileID := pathParts[3]

	if fileID == "" || strings.Contains(fileID, "..") || strings.Contains(fileID, "/") {
		http.Error(w, "Nieprawidłowy plik", http.StatusBadRequest)
		return
	}

	filePath := filepath.Join("./downloads", fileID)
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		http.Error(w, "Plik nie istnieje", http.StatusNotFound)
		return
	}

	// Szyfrowany bełkot - typ application/octet-stream
	w.Header().Set("Content-Type", "application/octet-stream")
	http.ServeFile(w, r, filePath)
}
