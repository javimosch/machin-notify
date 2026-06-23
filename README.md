# machin-notify

A **notification hub** — daemon + CLI — written in **[machin](https://github.com/javimosch/machin)** (MFL). Configure your **Discord** webhooks and **Telegram** bots once in the daemon; every app then sends notifications through a single token-auth'd endpoint and never embeds a provider secret.

Part of [**awesome-machin**](https://github.com/javimosch/awesome-machin) — the machin ecosystem.

## Why

Instead of wiring Discord/Telegram into every app (and copying webhook URLs and bot tokens around), apps hold **one daemon token** and POST to `/notify`. Add, rotate, or re-route channels at the hub — zero app changes. Secrets live in one place.

```
  app / CLI ──POST /notify (Bearer token, {channel, message})──►  machin-notify daemon ──HTTPS──►  Discord / Telegram
```

## Build & run

Needs the [machin](https://github.com/javimosch/machin) compiler, a C compiler, and `libsqlite3`. (Links OpenSSL for the outbound HTTPS, SQLite for config.)

```bash
./build.sh                                   # → ./machin-notify
./machin-notify daemon                       # start the hub (127.0.0.1:48090)
```

Configure channels and tokens (the CLI writes the same SQLite file the daemon reads):

```bash
machin-notify token new "machin-meet"        # mint an app token — printed once
machin-notify add discord  ops  https://discord.com/api/webhooks/ID/TOKEN
machin-notify add telegram me   123456:ABC-bot-token  987654321   # bot-token + chat-id
machin-notify list
```

Send (CLI, or any app via REST):

```bash
NOTIFY_TOKEN=<token> machin-notify send ops "deploy finished ✅"

curl -X POST localhost:48090/notify \
  -H "Authorization: Bearer <token>" \
  -d '{"channel":"ops","message":"hello"}'
```

## REST API

| | |
|---|---|
| `POST /notify` | `Authorization: Bearer <token>` + `{channel, message}` → sends; `{"ok":true}` or an error. (Token may also be in the body for back-compat.) |
| `GET /health` | `{"ok":true}` |

## Providers

Both are a single HTTPS POST with the secret in the URL — no auth header:

- **Discord** — `add discord <name> <webhook-url>`; sends `{"content": message}`.
- **Telegram** — `add telegram <name> <bot-token> <chat-id>`; sends `{"chat_id", "text"}` to `api.telegram.org/bot…/sendMessage`.

## Configuration (environment)

| var | default | meaning |
|-----|---------|---------|
| `NOTIFY_PORT` | `48090` | daemon listen port (binds `127.0.0.1`) |
| `NOTIFY_DB` | `notify.db` | SQLite config file |
| `NOTIFY_TOKEN` | — | the app token used by `machin-notify send` |

## Security

- Apps hold a **daemon token only**, never the provider secrets. Tokens are stored **hashed** (`sha256`); rotate/revoke at the hub.
- Daemon binds localhost. Provider secrets sit in one SQLite file — keep its perms tight (encrypting them with `aes_gcm` is a natural next step).

## Built on machin

`machweb` (HTTP daemon), SQLite (bound params), `http_request` (authenticated/typed HTTPS), `json_get`, `sha256`/`rand_bytes` (tokens), and raw sockets for the localhost app→daemon hop. The daemon→provider sends report real HTTP status, so failures surface.

> Used by [machin-meet](https://github.com/javimosch/machin-meet): point it at the hub (`MEET_NOTIFY_*`) and booking alerts go to Discord/Telegram with no provider code in the app.

## Layout

```
machin-notify/
├── notify.src    # daemon + CLI (MFL)
├── machweb.src   # vendored web framework
├── build.sh
└── README.md
```
