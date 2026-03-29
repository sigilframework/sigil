# Sigil

**Ship AI products, not agent scripts.** One framework — agents, memory, real-time UI, and admin — in 3,000 lines of Elixir.

[Docs](https://sigil.dev/docs) · [Discord](https://discord.com/channels/1487814726950981674/1487814838066483221) · [GitHub](https://github.com/sigilframework/sigil)

---

## One command to a running AI product

```
mix sigil.new my_app && cd my_app && mix setup && mix sigil.server
```

That's it. Open `localhost:4000`. You have:

- ✅ A personal blog with rich text editor
- ✅ AI chat assistant with streaming responses over WebSocket
- ✅ Multi-agent routing — add agents from the admin, not code
- ✅ Calendar tools — your agents book meetings, check availability
- ✅ Full admin dashboard — manage agents, tools, posts, conversations
- ✅ Auth, sessions, protected routes
- ✅ Dockerfile + Render config — deploy in 5 minutes

**Zero agent code.** Agents are configured in the database. Change a system prompt, swap a model, assign tools — all from the admin UI. No restart required.

---

## Why Sigil exists

Most AI frameworks give you an LLM wrapper and wish you luck. You still need to build auth, admin, UI, memory, deployment — five libraries stitched together with duct tape.

Sigil gives you the full stack:

| Layer | What it does |
|-------|-------------|
| **Sigil.LLM** | Unified interface to Claude, GPT — swap models without changing code |
| **Sigil.Tool** | Define actions agents can take (book meetings, query DBs, call APIs) |
| **Sigil.Memory** | Progressive context compression — 80% fewer tokens on long conversations |
| **Sigil.Agent** | Long-running agents with event sourcing, checkpointing, crash recovery |
| **Sigil.Live** | Real-time UI over WebSocket — server-rendered, ~2KB client, no React |
| **Sigil.Auth** | Users, login, sessions, protected routes — built in |

Use any layer independently, or all of them together.

---

## Define an agent in 10 lines

```elixir
defmodule MyApp.GenericAgent do
  use Sigil.Agent

  def init_agent(opts) do
    %{
      llm: {Sigil.LLM.Anthropic, model: opts[:model] || "claude-sonnet-4-20250514"},
      tools: MyApp.ToolRegistry.resolve(opts[:tools] || []),
      system: opts[:system_prompt] || "You are a helpful assistant.",
      memory: :progressive,
      max_turns: 15
    }
  end
end
```

That's a **generic agent** — one module that powers every agent in your app. The system prompt, model, and tools come from the database. Add a new agent? Add a row. No code.

## Define a tool

```elixir
defmodule MyApp.Tools.BookMeeting do
  use Sigil.Tool

  def name, do: "book_meeting"
  def description, do: "Book a meeting on the calendar"

  def params do
    %{
      "type" => "object",
      "properties" => %{
        "title" => %{"type" => "string"},
        "time" => %{"type" => "string", "description" => "ISO 8601 datetime"},
        "email" => %{"type" => "string"}
      },
      "required" => ["title", "time", "email"]
    }
  end

  def call(%{"title" => title, "time" => time, "email" => email}, _ctx) do
    {:ok, "Booked: #{title} at #{time} with #{email}"}
  end
end
```

## Real-time UI (no React, no build step)

Sigil.Live renders HTML on the server and patches the DOM over WebSocket:

```elixir
defmodule MyApp.ChatLive do
  use Sigil.Live

  def mount(_params, socket) do
    {:ok, Sigil.Live.assign(socket, messages: [], loading: false)}
  end

  def render(assigns) do
    """
    <div id="chat">
      #{render_messages(assigns.messages)}
      <form sigil-event="send">
        <input type="text" name="message" placeholder="Ask anything..." />
      </form>
    </div>
    """
  end
end
```

---

## Built on the BEAM

Sigil runs on Elixir and the Erlang VM — the same runtime that powers WhatsApp (2B users) and Discord.

| Problem | Python/TS | Sigil |
|---------|-----------|-------|
| Agent running for hours | Redis queues, Celery, workers | It's a process. It just runs. |
| 10,000 concurrent users | Kubernetes, message brokers | BEAM handles millions of lightweight processes |
| Agent crashes mid-conversation | Data lost, manual restart | Supervisor restarts from last checkpoint |
| Real-time streaming | SSE hacks, polling | Native WebSocket, built in |
| Long conversations | Manual token counting | Progressive memory compression, automatic |
| Hosting cost | $50-200/mo across services | $0-7/mo (one server) |

**New to Elixir?** That's fine. The [Getting Started guide](https://elixir-lang.org/getting-started/introduction.html) takes an afternoon.

---

## Installation

### Full app (recommended)

```bash
mix sigil.new my_app    # prompts for your Anthropic API key
cd my_app
mix setup               # install deps, create DB, seed
mix sigil.server        # running at localhost:4000
```

The generator will ask for your [Anthropic API key](https://console.anthropic.com/) and save it to `.env`. If you skip it, add it later:

```bash
# .env (auto-loaded by mix sigil.server)
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### Add to an existing Elixir project

```elixir
# mix.exs
def deps do
  [
    {:sigil, "~> 0.1.0"},

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
- ⚪ Plugin ecosystem on Hex
- ⚪ OpenAI provider
- ⚪ Agent templates (support bot, content writer, scheduler)
- ⚪ Sigil Cloud (hosted deployment)

---

## Community

- [Discord](https://discord.com/channels/1487814726950981674/1487814838066483221) — get help, share what you're building
- [GitHub Discussions](https://github.com/sigilframework/sigil/discussions) — ideas, RFCs, questions
- [Contributing](CONTRIBUTING.md) — we welcome PRs

## License

MIT — see [LICENSE](LICENSE) for details.
