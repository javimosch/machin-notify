---
name: machin-notify
description: >-
  Run, configure, and integrate machin-notify — a notification hub (daemon + CLI,
  written in machin/MFL) that fans Discord/Telegram alerts out from one
  token-authenticated endpoint. Use this skill when an app needs to send
  notifications without embedding provider secrets, when adding/rotating a
  Discord webhook or Telegram bot, when minting/revoking app tokens, or when
  deploying the hub as a service.
---

# machin-notify — notification hub

## Mental model

One daemon holds all provider secrets (Discord webhooks, Telegram bot tokens).
Apps never embed those — they hold a single **bearer token** and `POST /notify`.
Add, rotate, or re-route channels at the hub; apps don't change.

```
app / CLI ──POST /notify (Bearer <token>, {channel, message})──► daemon ──HTTPS──► Discord / Telegram
```

- **Process:** `machin-notify daemon` (binds `127.0.0.1:48090`, `machweb` + SQLite).
- **Config store:** one SQLite file (`NOTIFY_DB`, default `notify.db`) with two
  tables — `channel(name, kind, a, b)` and `token(hash, label, created)`.
- **Admin (`token`, `add`, `list`)** writes the SQLite file directly.
  **`send`** goes through the daemon over HTTP. The daemon re-opens the DB per
  request, so admin changes take effect immediately — **no daemon restart needed**.

## Build

Needs the `machin` compiler, a C compiler, and `libsqlite3` (the daemon also
links OpenSSL for outbound HTTPS — `libssl`/`libcrypto` must exist at runtime).

```bash
./build.sh            # → ./machin-notify  (encodes machweb.src + notify.src)
```

## Run + configure

```bash
machin-notify daemon                                   # start the hub
machin-notify token new "myapp"                        # prints a 48-hex token ONCE — capture it
machin-notify add discord  alerts  https://discord.com/api/webhooks/ID/TOKEN
machin-notify add telegram me      <bot-token> <chat-id>
machin-notify list
```

Tokens are stored **hashed** (`sha256`); the plaintext is shown only at creation.
Channel kinds: `discord` (a=webhook URL) and `telegram` (a=bot token, b=chat id).

## Send

```bash
# CLI (reads NOTIFY_TOKEN, sends Authorization: Bearer)
NOTIFY_TOKEN=<token> machin-notify send alerts "deploy finished"

# any app via REST — this is the integration contract:
curl -X POST http://127.0.0.1:48090/notify \
  -H "Authorization: Bearer <token>" \
  -d '{"channel":"alerts","message":"hello"}'
```

`POST /notify` → `{"ok":true,"info":"discord -> status 204"}` on success, `401`
on bad token, `502` with `info` on a provider failure. `GET /health` → `{"ok":true}`.
The token may also be sent in the JSON body (`{"token":...}`) for back-compat,
but **prefer the `Authorization: Bearer` header**.

## Integrate from another machin app

The daemon is plain HTTP on localhost, so a machin app sends with raw sockets
(`dial`/`write`/`read`), not `https_post`/`http_request` (those are TLS-only):

```machin
body := "{\"channel\":\"" + json_escape(channel) + "\",\"message\":\"" + json_escape(msg) + "\"}"
fd := dial("127.0.0.1", 48090)
write(fd, "POST /notify HTTP/1.1\r\nHost: 127.0.0.1:48090\r\nAuthorization: Bearer " + token + "\r\nContent-Type: application/json\r\nContent-Length: " + str(len(body)) + "\r\nConnection: close\r\n\r\n" + body)
read(fd)  close(fd)
```

[machin-meet](https://github.com/javimosch/machin-meet) does exactly this in its
`notify_hub` — set `MEET_NOTIFY_TOKEN` + `MEET_NOTIFY_CHANNEL` (and optionally
`MEET_NOTIFY_ADDR`) and booking alerts flow to the hub.

## Configuration (environment)

| var | default | meaning |
|-----|---------|---------|
| `NOTIFY_PORT` | `48090` | daemon listen port (binds `127.0.0.1`) |
| `NOTIFY_DB` | `notify.db` | SQLite config file (admin CLI **and** daemon must use the same path) |
| `NOTIFY_TOKEN` | — | token used by `machin-notify send` |

## Deploy as a service (systemd)

The hub is internal — no public route needed. Run it under systemd so it
restarts and survives reboot; the admin CLI must point `NOTIFY_DB` at the same
file the daemon uses.

```ini
# /etc/systemd/system/machin-notify.service
[Service]
User=appuser
Environment=NOTIFY_PORT=48090
Environment=NOTIFY_DB=/home/appuser/notify.db
ExecStart=/home/appuser/machin-notify daemon
Restart=always
[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now machin-notify
# configure with the SAME db path the service uses:
NOTIFY_DB=/home/appuser/notify.db ./machin-notify token new myapp
NOTIFY_DB=/home/appuser/notify.db ./machin-notify add discord alerts <webhook>
```

## Gotchas

- **Provider secrets stay only in `NOTIFY_DB`.** Don't commit it (it's
  gitignored) and don't echo webhook URLs into logs/commits — Discord webhook
  URLs and Telegram bot tokens *are* secrets (a leaked Discord webhook lets
  anyone post to the channel; rotate it in Discord if exposed).
- Discord success is HTTP **204** (no body); Telegram is **200**. The hub treats
  any 2xx as success.
- Run admin commands and the daemon with the **same `NOTIFY_DB`**, or the daemon
  won't see channels/tokens you added.
- The CLI `send` talks to the daemon; the admin commands don't — so the daemon
  must be running for `send`, but not for `add`/`token`.
