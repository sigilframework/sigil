defmodule Sigil.Examples.Assistant do
  @moduledoc """
  A simple conversational assistant agent.

  This is the "hello world" of Sigil agents — it demonstrates
  the full think → act → observe loop with Claude.

  ## Usage

      # Set your API key
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-...")

      # Start the agent
      {:ok, pid} = Sigil.Agent.start(Sigil.Examples.Assistant)

      # Chat with it
      {:ok, resp} = Sigil.Agent.chat(pid, "What can you do?")
      IO.puts(resp.content)

      # It can use tools too
      {:ok, resp} = Sigil.Agent.chat(pid, "Fetch the Hacker News homepage")
      IO.puts(resp.content)

      # Multi-turn conversation (memory is kept)
      {:ok, resp} = Sigil.Agent.chat(pid, "Summarize what you just found")
      IO.puts(resp.content)

      # Stop when done
      Sigil.Agent.stop(pid)
  """
  use Sigil.Agent

  @impl true
  def init_agent(_opts) do
    %{
      llm: {Sigil.LLM.Anthropic, model: "claude-sonnet-4-20250514"},
      tools: [Sigil.Tools.HTTPRequest],
      system: """
      You are a helpful AI assistant powered by Sigil.
      You can browse the web using the http_request tool.
      Be concise but thorough. When using tools, explain what you're doing.
      """,
      memory: :sliding_window,
      max_turns: 5
    }
  end

  @impl true
  def before_call(messages, state) do
    # Log the turn count for debugging
    if state.turn_count > 0 do
      IO.puts("[Sigil] Tool loop iteration #{state.turn_count}")
    end

    {messages, state}
  end

  @impl true
  def on_tool_result(tool_name, result, state) do
    IO.puts("[Sigil] Tool '#{tool_name}' completed")
    {result, state}
  end

  @impl true
  def on_complete(response, state) do
    IO.puts("[Sigil] Response received (#{response.usage.input_tokens}+#{response.usage.output_tokens} tokens)")
    {:ok, response, state}
  end
end
