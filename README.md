# Sigil

[![Hex.pm](https://img.shields.io/hexpm/v/sigil.svg)](https://hex.pm/packages/sigil)
[![Downloads](https://img.shields.io/hexpm/dt/sigil.svg)](https://hex.pm/packages/sigil)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/sigil)
[![CI](https://github.com/sigilframework/sigil/actions/workflows/ci.yml/badge.svg)](https://github.com/sigilframework/sigil/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen.svg)](LICENSE)

**Ship AI products, not agent scripts.** A framework for building AI-powered web apps in Elixir.

*Sigil gives you the foundation — agents, memory, tools, auth, real-time UI — so you can build your product on top. You own every line of code.*

[Docs](https://hexdocs.pm/sigil) · [GitHub](https://github.com/sigilframework/sigil)

<p>
  <img src="docs/screenshots/blog.png" width="32%" alt="Blog with AI chat" />
  <img src="docs/screenshots/chat.png" width="32%" alt="AI chat assistant" />
  <img src="docs/screenshots/admin.png" width="32%" alt="Admin dashboard" />
</p>

<sub>Blog with integrated AI chat · Streaming chat assistant · Admin dashboard — all from <code>mix sigil.new</code></sub>

---

## Sigil is two things

### 1. A framework — the building blocks

Add `{:sigil, "~> 0.1.4"}` to any Elixir project. You get six composable layers:

| Layer | What it does |
|-------|-------------|
| **Sigil.LLM** | Unified interface to Claude, GPT — swap models without changing code |
| **Sigil.Tool** | Define actions agents can take (API calls, database writes, anything) |
| **Sigil.Memory** | Context windows, token budgeting, progressive summarization — never overflow |
| **Sigil.Agent** | Long-running OTP agents with checkpointing, crash recovery, and tool dispatch |
| **Sigil.Live** | Real-time server-rendered UI over WebSocket — no React, no build step, ~2KB client |
| **Sigil.Auth** | Users, login, sessions, protected routes — out of the box |

Use any layer independently, or all of them together. [Full API docs →](https://hexdocs.pm/sigil)

### 2. A starter app — a working product in one command

`mix sigil.new` generates a real, deployable app — not a blank project. It's a starting point you customize or rebuild entirely.

```bash
mix sigil.new my_app
```

```bash
cd my_app && mix setup && mix sigil.server
```

Open `localhost:4000`. You have:

- ✅ A personal blog with rich text editor
- ✅ AI chat assistant with streaming responses over WebSocket
- ✅ Multi-agent routing — add agents from the admin, not code
- ✅ Calendar tools — your agents book meetings, check availability
- ✅ Full admin dashboard — manage agents, tools, posts, conversations
- ✅ Auth, sessions, protected routes
- ✅ Dockerfile + Render config — deploy in 5 minutes

**The example app is a blog. Yours can be anything.** A coaching app, a customer support bot, a SaaS dashboard — the framework supports whatever you need.

> **New to Elixir?** See the [full setup walkthrough](#getting-started) below — it covers installing Elixir, PostgreSQL, and everything you need.

---

## What `mix sigil.new` generates

```
my_app/
├── lib/my_app/
│   ├── live/                  # Chat, blog, admin views
│   │   ├── chat_live.ex       # Streaming AI chat
│   │   ├── home_live.ex       # Blog homepage
│   │   └── admin/             # Dashboard, agents, posts, settings
│   ├── schemas/               # Ecto schemas (posts, conversations, etc.)
│   ├── tools/                 # Agent tools (calendar, booking)
│   ├── generic_agent.ex       # One module powers all agents
│   ├── router.ex              # Routes with auth guards
│   └── layout.ex              # Full HTML layout with dark mode
├── priv/
│   ├── repo/migrations/       # DB schema (one migration)
│   ├── repo/seeds.exs         # Sample data + agent configs
│   └── static/css/            # Design system
├── config/                    # Dev, test, prod, runtime
├── Dockerfile                 # Production-ready container
└── render.yaml                # One-click deploy to Render
```

**Zero agent code.** Agents are configured in the database. Change a system prompt, swap a model, assign tools — all from the admin UI. No restart required.

---


## How Sigil compares

| | LangChain / CrewAI | Phoenix + custom | **Sigil** |
|-|-------------------|-----------------|-----------|
| **Language** | Python / TS | Elixir | Elixir |
| **Agent runtime** | Short-lived scripts | Build your own | Long-lived GenServer with crash recovery |
| **UI** | Bring your own (React, etc.) | LiveView (separate dep) | Built-in Sigil.Live (~2KB client) |
| **Admin** | None | Build your own | Included — agents, tools, posts, conversations |
| **Memory** | Manual / vector DB | Build your own | Progressive compression + token budgets |
| **Auth** | None | Separate library | Built in |
| **Generator** | None | `mix phx.new` (no AI) | `mix sigil.new` — full AI app in 60 seconds |

---

## Built on the BEAM

Sigil runs on Elixir and the Erlang VM — the same runtime that powers WhatsApp (2B users) and Discord.

Each agent, each chat, each user gets its own lightweight process (~2KB). One server can run millions. If something crashes, the system restarts it in milliseconds from the last checkpoint. No lost conversations.

| Problem | Python/TS | Sigil |
|---------|-----------|-------|
| Agent running for hours | Redis queues, Celery, workers | It's a process. It just runs. |
| 10,000 concurrent users | Kubernetes, message brokers | BEAM handles millions of lightweight processes |
| Agent crashes mid-conversation | Data lost, manual restart | Supervisor restarts from last checkpoint |
| Real-time streaming | SSE hacks, polling | Native WebSocket, built in |
| Long conversations | Manual token counting | Progressive memory compression, automatic |
| Hosting cost | $50-200/mo across services | $0-50/mo (one server + one database) |

---

## Getting Started

### 1. Install prerequisites

You need three things installed before using Sigil:

- **Elixir 1.18+** (includes `mix`, the build tool used in all commands below)
- **Erlang/OTP 27+** (installed automatically with most Elixir installers)
- **PostgreSQL 14+** (the database — must be running locally)

The fastest way to install Elixir and Erlang:

```bash
# macOS with Homebrew
brew install elixir
```

```bash
# Or with mise (recommended for version management)
mise install elixir@1.18 erlang@27
```

For other platforms, see the [Elixir install guide](https://elixir-lang.org/install.html). For PostgreSQL, see the [PostgreSQL downloads](https://www.postgresql.org/download/).

You'll also need an [Anthropic API key](https://console.anthropic.com/) for AI chat.

### 2. Install the Sigil generator

```bash
mix archive.install hex sigil
```

This installs the `mix sigil.new` command globally. You only need to do this once.

### 3. Create your app

```bash
mix sigil.new my_app
```

The generator will ask for your Anthropic API key and save it to `.env`.

### 4. Set up and run

```bash
cd my_app
```

```bash
mix setup
```

This installs dependencies, creates the PostgreSQL database, runs migrations, and seeds sample data. **PostgreSQL must be running** for this step.

```bash
mix sigil.server
```

Open [localhost:4000](http://localhost:4000). You're running.

**Admin login:** `admin@example.com` / `admin123`

### Add to an existing Elixir project

```elixir
# mix.exs
def deps do
  [
    {:sigil, "~> 0.1.4"},

    # Optional — add only what you need:
    {:bandit, "~> 1.6"},           # Web server (for Sigil.Live)
    {:ecto_sql, "~> 3.12"},       # Database (for persistence)
    {:postgrex, "~> 0.19"},       # PostgreSQL
  ]
end
```

```elixir
# config/runtime.exs
config :sigil,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
```

---

## Roadmap

- ✅ Multi-agent teams with shared memory
- ✅ Progressive context compression
- ✅ Event sourcing and checkpointing
- ✅ Real-time UI (Sigil.Live)
- ✅ DB-driven agent configuration
- ✅ Admin dashboard (agents, tools, conversations)
- ✅ `mix sigil.new` app generator
- ✅ Token usage tracking and telemetry
- ✅ Plugin ecosystem on Hex
- ⚪ Build out more robust demo
- ⚪ Agent templates (support bot, content writer)
- ⚪ OpenAI provider
- ⚪ Hosted deployments

---

## Community

- [GitHub Discussions](https://github.com/sigilframework/sigil/discussions) — ideas, RFCs, questions

## License

MIT — see [LICENSE](LICENSE) for details.
