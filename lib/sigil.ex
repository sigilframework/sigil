defmodule Sigil do
  @moduledoc """
  Sigil — AI Agent Framework for Elixir.

  Build long-running, fault-tolerant AI agents on the BEAM.
  Sigil provides five composable layers:

  1. `Sigil.LLM` — Unified interface to AI models (Anthropic, OpenAI)
  2. `Sigil.Tool` — Actions agents can take, with permissions and timeouts
  3. `Sigil.Memory` — Context window management, token budgeting, summarization
  4. `Sigil.Agent` — GenServer orchestrator with event sourcing and checkpointing
  5. `Sigil.Live` — Real-time web over WebSocket (planned)

  ## Quick Start

      defmodule MyAgent do
        use Sigil.Agent

        def init_agent(_opts) do
          %{
            llm: {Sigil.LLM.Anthropic, model: "claude-sonnet-4-20250514"},
            tools: [Sigil.Tools.HTTPRequest],
            system: "You are a helpful assistant.",
            memory: :progressive,
            max_turns: 10
          }
        end
      end

      {:ok, pid} = Sigil.Agent.start(MyAgent, api_key: "sk-...")
      {:ok, response} = Sigil.Agent.chat(pid, "Hello!")
  """

  @doc "Returns the current Sigil version."
  def version, do: "0.1.0"
end
