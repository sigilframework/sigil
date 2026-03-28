# Try it:
#   cd relay
#   ANTHROPIC_API_KEY=sk-ant-... iex -S mix
#
# Then paste:
#   {:ok, pid} = Relay.Agent.start(Relay.Examples.Assistant)
#   {:ok, resp} = Relay.Agent.chat(pid, "What's 2+2?")
#   IO.puts(resp.content)

alias Relay.Agent
alias Relay.Examples.Assistant

IO.puts("""
\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Relay v#{Relay.version()} — Interactive Console
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Quick start:
    {:ok, pid} = Agent.start(Assistant)
    {:ok, resp} = Agent.chat(pid, "Hello!")
    IO.puts(resp.content)

  Multi-turn:
    {:ok, resp} = Agent.chat(pid, "What can you do?")
    {:ok, resp} = Agent.chat(pid, "Fetch https://news.ycombinator.com")

  Stop:
    Agent.stop(pid)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
