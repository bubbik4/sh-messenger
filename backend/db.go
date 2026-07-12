package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
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
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS public_key TEXT NOT NULL DEFAULT '';`,
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
func CreateUser(username, passwordHash, publicKey string) error {
	_, err := DB.Exec(context.Background(), "INSERT INTO users (username, password_hash, public_key) VALUES ($1, $2, $3)", username, passwordHash, publicKey)
	return err
}

func GetUserByUsername(username string) (*User, error) {
	var user User
	err := DB.QueryRow(context.Background(), "SELECT id, username, password_hash, public_key FROM users WHERE username = $1", username).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.PublicKey)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func GetAllUsers() ([]User, error) {
	rows, err := DB.Query(context.Background(), "SELECT id, username, public_key FROM users")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.PublicKey); err != nil {
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
		SELECT u.username, m.encrypted_content, m.created_at 
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
		if err := rows.Scan(&msg.SenderUsername, &msg.EncryptedContent, &t); err != nil {
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
