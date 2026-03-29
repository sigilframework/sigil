# Sigil Demo (Docker)

Try a full AI-powered app in 30 seconds. No Elixir required.

## Quick Start

```bash
docker compose up
```

Open [localhost:4000](http://localhost:4000).

**Admin login:** `admin@example.com` / `admin123`

## Enable AI Chat

AI chat requires an [Anthropic API key](https://console.anthropic.com/):

```bash
ANTHROPIC_API_KEY=sk-ant-your-key docker compose up
```

Without the key, the blog and admin dashboard work fine — only the AI chat is disabled.

## What's running

- **App** — A Sigil demo app (blog, AI chat, admin dashboard)
- **PostgreSQL** — Database on port 5432 (internal only)
- **Port 4000** — The web app

## Stop it

```bash
docker compose down
```

To also remove the database volume:

```bash
docker compose down -v
```

## Ready to build your own?

The Docker demo is read-only. To create a customizable app, install Elixir and run:

```bash
mix archive.install hex sigil
mix sigil.new my_app
cd my_app && mix setup && mix sigil.server
```

See the [full getting started guide](https://sigilframework.github.io/sigil/#start).
