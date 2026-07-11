# Krok 1: Budowanie aplikacji
FROM golang:1.21-alpine AS builder

# Ustawiamy katalog roboczy
WORKDIR /app

# Kopiujemy wszystkie pliki do kontenera
COPY . .

# Dodajemy git, który jest potrzebny do pobierania modułów Go z GitHuba
RUN apk add --no-cache git

# Pobieramy zaleznosci (go mod tidy wygeneruje go.sum i pobierze co trzeba)
RUN go mod tidy

# Kompilujemy aplikację
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# Krok 2: Tworzenie lekkiego obrazu końcowego
FROM alpine:latest  

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Kopiujemy skompilowaną binarkę z pierwszego etapu
COPY --from=builder /app/main .

# Otwieramy port
EXPOSE 8080

# Uruchamiamy serwer
CMD ["./main"]
