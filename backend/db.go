package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var DB *pgxpool.Pool

func InitDB() error {
	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbUser := os.Getenv("DB_USER")
	dbPass := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")

	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", dbUser, dbPass, dbHost, dbPort, dbName)

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return fmt.Errorf("unable to connect to database: %v", err)
	}

	DB = pool

	if err := createTables(); err != nil {
		return fmt.Errorf("failed to create tables: %v", err)
	}

	log.Println("Połączono z bazą PostgreSQL")
	return nil
}

func createTables() error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			username VARCHAR(50) UNIQUE NOT NULL,
			password_hash TEXT NOT NULL,
			public_key TEXT NOT NULL DEFAULT '',
			is_admin BOOLEAN DEFAULT FALSE,
			is_visible BOOLEAN DEFAULT TRUE,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS messages (
			id SERIAL PRIMARY KEY,
			sender_id INT REFERENCES users(id),
			receiver_id INT REFERENCES users(id),
			encrypted_content TEXT NOT NULL,
			encrypted_aes_key TEXT NOT NULL DEFAULT '',
			is_delivered BOOLEAN DEFAULT FALSE,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);`,
		// Migracje: dodawanie kolumn jeśli tabela już istniała bez nich
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT NOT NULL DEFAULT '';`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS public_key TEXT NOT NULL DEFAULT '';`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE;`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS is_visible BOOLEAN DEFAULT TRUE;`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS encrypted_aes_key TEXT NOT NULL DEFAULT '';`,
	}

	for _, query := range queries {
		_, err := DB.Exec(context.Background(), query)
		if err != nil {
			return err
		}
	}
	return nil
}

// Funkcje pomocnicze bazy danych
func CreateUser(username, passwordHash, publicKey string, isVisible bool) error {
	_, err := DB.Exec(context.Background(), "INSERT INTO users (username, password_hash, public_key, is_visible) VALUES ($1, $2, $3, $4)", username, passwordHash, publicKey, isVisible)
	return err
}

func GetUserByUsername(username string) (*User, error) {
	var user User
	err := DB.QueryRow(context.Background(), "SELECT id, username, password_hash, public_key, is_admin, is_visible FROM users WHERE username = $1", username).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.PublicKey, &user.IsAdmin, &user.IsVisible)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func GetAllUsers() ([]User, error) {
	rows, err := DB.Query(context.Background(), "SELECT id, username, public_key, is_admin, is_visible FROM users")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.PublicKey, &u.IsAdmin, &u.IsVisible); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func GetVisibleUsers() ([]User, error) {
	rows, err := DB.Query(context.Background(), "SELECT id, username, public_key, is_admin, is_visible FROM users WHERE is_visible = true")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.PublicKey, &u.IsAdmin, &u.IsVisible); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func GetUsersByUsernames(usernames []string) ([]User, error) {
	if len(usernames) == 0 {
		return []User{}, nil
	}
	rows, err := DB.Query(context.Background(), "SELECT id, username, public_key, is_admin, is_visible FROM users WHERE username = ANY($1)", usernames)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.PublicKey, &u.IsAdmin, &u.IsVisible); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func SearchUser(username string) ([]User, error) {
	// Exact match as requested
	rows, err := DB.Query(context.Background(), "SELECT id, username, public_key, is_admin, is_visible FROM users WHERE username = $1", username)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.PublicKey, &u.IsAdmin, &u.IsVisible); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func SaveMessage(senderID, receiverID int, content string) error {
	_, err := DB.Exec(context.Background(), "INSERT INTO messages (sender_id, receiver_id, encrypted_content, encrypted_aes_key) VALUES ($1, $2, $3, '')", senderID, receiverID, content)
	return err
}

func GetUndeliveredMessages(receiverID int) ([]WsMessage, error) {
	rows, err := DB.Query(context.Background(), `
		SELECT u.username, u.public_key, m.encrypted_content, m.created_at 
		FROM messages m 
		JOIN users u ON m.sender_id = u.id 
		WHERE m.receiver_id = $1 AND m.is_delivered = false
		ORDER BY m.created_at ASC`, receiverID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var msgs []WsMessage
	for rows.Next() {
		var msg WsMessage
		var t time.Time
		if err := rows.Scan(&msg.SenderUsername, &msg.SenderPublicKey, &msg.EncryptedContent, &t); err != nil {
			return nil, err
		}
		msg.Timestamp = t.Format(time.RFC3339)
		msgs = append(msgs, msg)
	}
	return msgs, nil
}

func MarkMessagesAsDelivered(receiverID int) error {
	_, err := DB.Exec(context.Background(), "UPDATE messages SET is_delivered = true WHERE receiver_id = $1 AND is_delivered = false", receiverID)
	return err
}

func DeleteUser(username string) error {
	user, err := GetUserByUsername(username)
	if err != nil {
		return err
	}
	
	// Usuń najpierw wiadomości powiązane z użytkownikiem (jako nadawca lub odbiorca)
	_, err = DB.Exec(context.Background(), "DELETE FROM messages WHERE sender_id = $1 OR receiver_id = $1", user.ID)
	if err != nil {
		return err
	}
	
	// Następnie usuń samo konto użytkownika
	_, err = DB.Exec(context.Background(), "DELETE FROM users WHERE id = $1", user.ID)
	return err
}

func UpdateUserPassword(username, passwordHash string) error {
	_, err := DB.Exec(context.Background(), "UPDATE users SET password_hash = $1 WHERE username = $2", passwordHash, username)
	return err
}

func SeedAdmin() {
	user, err := GetUserByUsername("admin")
	if err != nil || user == nil {
		// Admin nie istnieje, tworzymy
		hash, _ := bcrypt.GenerateFromPassword([]byte("152247"), bcrypt.DefaultCost)
		_, err := DB.Exec(context.Background(), "INSERT INTO users (username, password_hash, public_key, is_admin, is_visible) VALUES ($1, $2, $3, $4, $5)", "admin", string(hash), "", true, false)
		if err != nil {
			log.Printf("Błąd podczas tworzenia konta admina: %v", err)
		} else {
			log.Println("Pomyślnie utworzono domyślne konto administratora.")
		}
	} else if !user.IsAdmin {
		// Użytkownik istnieje, ale nie jest adminem - nadajemy uprawnienia
		_, _ = DB.Exec(context.Background(), "UPDATE users SET is_admin = true WHERE username = 'admin'")
	}
}
