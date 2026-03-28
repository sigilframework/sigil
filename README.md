# Sigil

**AI agent framework for Elixir** — long-running, fault-tolerant agents on the BEAM.

## Why Sigil?

Most AI agent frameworks are built on Python or TypeScript. They all hit the same wall: long-running agents are fundamentally at odds with request-response runtimes. Sigil is built on the BEAM — the runtime designed for systems that never stop.

| Problem | Python/TS Frameworks | Sigil on BEAM |
|---|---|---|
| Agent running for hours | Redis queues, Celery, external orchestration | GenServer just runs. It's a process. |
| 10,000 concurrent agents | Kubernetes pod scaling, message brokers | BEAM handles millions of lightweight processes |
| Agent crashes mid-run | Data lost, manual restart logic | Supervisor restarts it. OTP was built for this. |
| Real-time streaming to UI | SSE hacks, polling | WebSocket — native to Elixir |

## Five Layers

```
┌─────┐ ┌──────┐ ┌──────┐ ┌─────┐ ┌────┐
│ LLM │ │ Tool │ │Memory│ │Agent│ │Live│
└─────┘ └──────┘ └──────┘ └─────┘ └────┘
```

1. **`Sigil.LLM`** — Unified interface to AI models (Anthropic, OpenAI)
2. **`Sigil.Tool`** — Actions agents can take, with permissions and timeouts
3. **`Sigil.Memory`** — Context window management, token budgeting, progressive summarization
4. **`Sigil.Agent`** — GenServer orchestrator with event sourcing, checkpointing, and resume
5. **`Sigil.Live`** — Real-time web views over WebSocket with server-side DOM diffing

## Quick Start

```elixir
# Define an agent
defmodule MyAgent do
  use Sigil.Agent

  def init_agent(_opts) do
    %{
      llm: {Sigil.LLM.Anthropic, model: "claude-sonnet-4-20250514"},
      tools: [MyApp.Tools.Search],
      system: "You are a helpful assistant.",
      memory: :progressive,
      max_turns: 10
    }
  end
end

# Start and chat
{:ok, pid} = Sigil.Agent.start(MyAgent, api_key: System.get_env("ANTHROPIC_API_KEY"))
{:ok, response} = Sigil.Agent.chat(pid, "What's on Hacker News today?")
IO.puts(response.content)
```

## Define a Tool

```elixir
defmodule MyApp.Tools.SendEmail do
  use Sigil.Tool

  def name, do: "send_email"
  def description, do: "Send an email to a recipient"

  def params do
    %{
      "type" => "object",
      "properties" => %{
        "to" => %{"type" => "string", "description" => "Recipient email"},
        "subject" => %{"type" => "string"},
        "body" => %{"type" => "string"}
      },
      "required" => ["to", "subject", "body"]
    }
  end

  # Require human approval before sending
  def permission, do: :human_approval

  def call(%{"to" => to, "subject" => _subject, "body" => _body}, _context) do
    # Your email sending logic here
    {:ok, "Email sent to #{to}"}
  end
end
```

## Long-Running Agents

Sigil's context window management keeps agents coherent over long conversations:

```elixir
def init_agent(_opts) do
  %{
    llm: {Sigil.LLM.Anthropic, model: "claude-sonnet-4-20250514"},
    system: "You are a research assistant.",
    memory: :progressive,  # Tiered compression: recent=verbatim, old=summarized
    max_turns: 50
  }
end
```

**Progressive compression** divides conversation history into zones:
- **Zone 1** (most recent): Full messages, no compression
- **Zone 2** (medium age): LLM-summarized
- **Zone 3** (oldest): Key facts only

Token budgets are managed automatically — the framework guarantees messages fit within the model's context window.

## Durable Agents (requires Postgres)

Agents can survive restarts via event sourcing and checkpointing:

```elixir
# Agent automatically checkpoints every 5 turns and after tool calls
{:ok, pid} = Sigil.Agent.start(MyAgent, api_key: System.get_env("ANTHROPIC_API_KEY"))
run_id = Sigil.Agent.run_id(pid)

# ... later, after a restart ...
{:ok, pid} = Sigil.Agent.resume(run_id, agent_module: MyAgent)

# Inspect what happened
{:ok, timeline} = Sigil.Agent.Observer.timeline(run_id)
{:ok, context} = Sigil.Agent.Observer.context_at(run_id, sequence: 15)
```

## Multi-Agent Teams

```elixir
{:ok, team} = Sigil.Agent.Team.start(%{
  name: :research_team,
  agents: [
    {:researcher, ResearchAgent, [topic: "market analysis"]},
    {:analyst, AnalysisAgent, []},
    {:writer, ReportAgent, []}
  ],
  shared_memory: true
})

Sigil.Agent.Team.send_message(team, :researcher, "Find Q4 revenue data")
```

## Installation

```elixir
# mix.exs
def deps do
  [{:sigil, "~> 0.1.0"}]
end
```

Only the core agent framework is required. Web layer and database are optional:

```elixir
# Add these only if you need them:
{:sigil, "~> 0.1.0"},
{:bandit, "~> 1.6"},           # Web server (for Sigil.Live)
{:plug, "~> 1.16"},            # Routing
{:websock_adapter, "~> 0.5"},  # WebSocket
{:ecto_sql, "~> 3.12"},       # Database (for event sourcing)
{:postgrex, "~> 0.19"},       # PostgreSQL driver
{:bcrypt_elixir, "~> 3.0"},   # Auth (for Sigil.Auth)
```

## Configuration

```elixir
# config/config.exs
config :sigil,
  secret_key_base: "generate-a-64-byte-secret-here"

# config/runtime.exs — set API keys from environment
config :sigil,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY")

# Optional: PostgreSQL for event sourcing
config :sigil, Sigil.Repo,
  database: "my_app_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
```

## License

MIT — see [LICENSE](LICENSE) for details.
