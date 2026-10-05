# 🪷 lotus

Ein schöner Startbildschirm fürs macOS-Terminal: Logo, Systeminfos in Boxen,
eine Begrüssung in 15 Sprachen – und der Song, der gerade läuft, **live**.

```
                       .                     Bonjour, Gabriel
                      .#.
                     .###.                   ┌──────────────── Hardware ────────────────┐
                    .#####.                  ├─ CPU       Apple M5 (10C / 10T) @ 4.46 GHz
           .        +#####+        .         ├─ RAM       15.26 GiB / 24.00 GiB [■■■■■■····] 63%
           #=.      *#####*      .=#         └──────────────────────────────────────────┘
          …                                   …
                                             ♫ Habiba — Boef
                                               [■■■■■■■■··] 02:48 / 03:35  ▶ läuft
```

## Installieren

**Ein Befehl:**

```bash
curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | zsh
```

**Oder mit Homebrew:**

```bash
brew install Fanxy13/lotus/lotus && lotus setup
```

Danach ein neues Terminal-Fenster öffnen.

## Befehle

| Befehl | Was es macht |
|---|---|
| `lotus` | Startbildschirm wieder anzeigen (z. B. nach `clear`) |
| `/settings` | Einstellungen öffnen (gleich wie `lotus settings`) |
| `lotus doctor` | Installation prüfen |
| `lotus update` | Auf die neueste Version aktualisieren |
| `lotus uninstall` | lotus wieder entfernen |

## Einstellungen

Mit `/settings` öffnet sich ein Menü (↑↓ auswählen, ←→ oder ⏎ ändern, `v` Vorschau, `q` fertig):

- Name, Logo (Lotus, Herz, keins), Farbschema (Matcha, Sakura, Ozean, Sunset, Mono)
- Begrüssung oben: 15 Sprachen der Reihe nach oder zufällig
- Gruss unten je nach Tageszeit: Französisch, Deutsch oder Englisch
- Bereiche ein/aus: Hardware, Session, Uptime & Datum, Läuft gerade
- Live-Update und Intervall, farbiger Prompt, „Last login“-Zeile ausblenden

Gespeichert wird in `~/.config/lotus/settings.zsh`.

## Läuft gerade

Zeigt alles, was macOS unter „Läuft gerade“ kennt – Spotify, Apple Music,
YouTube im Browser usw. Die Anzeige aktualisiert sich live, solange der
Startbildschirm sichtbar ist. Sobald das Terminal scrollt oder gelöscht wird,
bleibt sie stehen – `lotus` holt sie zurück.

## Ressourcen

- Start: ca. 30–40 ms (ein fastfetch-Lauf, Song-Abfrage parallel)
- Live-Update: eine kurze Abfrage alle 2 s (≈ 20 ms CPU), bei Pause alle 5 s.
  Mehrere Terminal-Fenster teilen sich das Ergebnis.
- Nur so lange aktiv, wie der Startbildschirm sichtbar ist.

## Voraussetzungen

macOS mit zsh (Standard seit macOS 10.15). [fastfetch](https://github.com/fastfetch-cli/fastfetch)
wird automatisch installiert. Terminal.app zeigt ab macOS 26 alle Farben, auf
älteren Versionen nutzt lotus automatisch 256 Farben.
