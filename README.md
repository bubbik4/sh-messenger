# Twill Chat

![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-red.svg)
![Frontend: Flutter](https://img.shields.io/badge/Frontend-Flutter-02569B?logo=flutter)
![Backend: Go](https://img.shields.io/badge/Backend-Go-00ADD8?logo=go)

**Twill Chat** to bezpieczny komunikator oparty na architekturze klient-serwer z wykorzystaniem szyfrowania End-to-End (E2EE). 

Projekt opiera się na modelu scentralizowanym. Kod udostępniamy jako Open Source pod licencją GNU AGPLv3 w celu zachowania transparentności - każdy może zweryfikować implementację kryptografii i upewnić się o braku tylnych furtek. Sama aplikacja docelowo łączy się z oficjalną infrastrukturą.

---

## Odpowiedź na Chat Control

Komunikator został zaprojektowany jako bezpośrednia odpowiedź na kontrowersyjne regulacje prawne, w tym dyrektywę Unii Europejskiej potocznie zwaną **Chat Control**. 

Celem projektu jest ochrona prywatności korespondencji użytkowników przed zautomatyzowanym, masowym monitorowaniem wiadomości (ang. mass surveillance) oraz mechanizmami Client-Side Scanning (CSS). Architektura aplikacji gwarantuje, że komunikacja jest weryfikowana i szyfrowana wyłącznie po stronie użytkownika, uniemożliwiając wgląd w jej treść osobom trzecim.

---

## Pobieranie aplikacji

Oficjalne wydania aplikacji znajdują się na naszej stronie domowej:

**[bubikit.pl](https://bubikit.pl)**

Strona zawiera:
- Dostęp do wersji webowej
- Pliki instalacyjne na platformę Android (APK)

---

## Architektura i Bezpieczeństwo

Komunikator wykorzystuje zasadę Zero-Knowledge dla danych tekstowych, a serwer zajmuje się wyłącznie przekazywaniem zaszyfrowanych pakietów.

1. **Wymiana Kluczy (ECDH - X25519):** Przy pierwszym logowaniu urządzenie klienta generuje parę kluczy. Klucz prywatny jest generowany i przechowywany wyłącznie lokalnie.
2. **Szyfrowanie (AES-GCM 256-bit):** Wszystkie wiadomości tekstowe są szyfrowane symetrycznie przed wysłaniem. Serwer nie posiada mechanizmów ani danych do ich rozszyfrowania.
3. **Zabezpieczenie przed MitM:** Aplikacja automatycznie weryfikuje publiczne klucze rozmówców w celu zapobiegania atakom typu man-in-the-middle.
4. **CORS & Origin Control:** Backend weryfikuje źródło zapytań (Origin HTTP oraz WebSocket) odrzucając komunikację z nieautoryzowanych domen.

---

## Stack Technologiczny

* **Backend (`/backend`)** - napisany w języku Go, wspierany bazą PostgreSQL. Wykorzystuje JWT do uwierzytelniania oraz pakiet `gorilla/websocket` do asynchronicznej obsługi klientów.
* **Frontend (`/frontend`)** - stworzony we Flutterze. Umożliwia kompilację pod aplikację webową oraz system Android w oparciu o wspólną bazę kodu, z wykorzystaniem pakietu `cryptography`.

---


