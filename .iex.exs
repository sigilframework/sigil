# Try it:
#   cd sigil
#   ANTHROPIC_API_KEY=sk-ant-... iex -S mix
#
# Then in your app that uses Sigil:
#   {:ok, pid} = Sigil.Agent.start(MyApp.MyAgent)
#   {:ok, resp} = Sigil.Agent.chat(pid, "What's 2+2?")
#   IO.puts(resp.content)

alias Sigil.Agent
alias Sigil.LLM
alias Sigil.Tool
alias Sigil.Memory

IO.puts("""
\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Sigil v#{Sigil.version()} — Interactive Console
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Quick start (in your app):
    {:ok, pid} = Agent.start(MyApp.MyAgent)
    {:ok, resp} = Agent.chat(pid, "Hello!")
    IO.puts(resp.content)

  Multi-turn:
    {:ok, resp} = Agent.chat(pid, "What can you do?")

  Stop:
    Agent.stop(pid)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
