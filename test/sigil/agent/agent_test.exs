defmodule Sigil.Agent.AgentTest do
  use ExUnit.Case, async: true

  alias Sigil.LLM.Mock

  defmodule SimpleTestAgent do
    use Sigil.Agent

    def init_agent(opts) do
      %{
        llm: {Sigil.LLM.Mock, responses: Keyword.get(opts, :responses, ["Hello from mock!"])},
        system: "You are a test agent.",
        max_turns: 5
      }
    end
  end

  defmodule ToolTestAgent do
    use Sigil.Agent

    def init_agent(opts) do
      %{
        llm: {Sigil.LLM.Mock, responses: Keyword.get(opts, :responses, ["Done."])},
        tools: [Sigil.Tools.HTTPRequest],
        system: "You are a test agent with tools.",
        max_turns: 5
      }
    end
  end

  setup do
    Mock.reset()
    :ok
  end

  describe "start/2" do
    test "starts an agent process" do
      {:ok, pid} = Sigil.Agent.start(SimpleTestAgent)
      assert Process.alive?(pid)
      Sigil.Agent.stop(pid)
    end

    test "validates config at init" do
      defmodule BadAgent do
        use Sigil.Agent
        def init_agent(_opts), do: %{no_llm: true}
      end

      Process.flag(:trap_exit, true)
      assert {:error, _} = Sigil.Agent.start_link({BadAgent, []})
    end

    test "validates LLM adapter module exists" do
      defmodule BadAdapterAgent do
        use Sigil.Agent
        def init_agent(_opts), do: %{llm: {NonExistent.Module, []}}
      end

      Process.flag(:trap_exit, true)
      assert {:error, _} = Sigil.Agent.start_link({BadAdapterAgent, []})
    end
  end

  describe "chat/2" do
    test "returns a response from the mock LLM" do
      {:ok, pid} = Sigil.Agent.start(SimpleTestAgent, responses: ["Test response!"])
      {:ok, response} = Sigil.Agent.chat(pid, "Hello")

      assert response.content == "Test response!"
      assert response.role == "assistant"

      Sigil.Agent.stop(pid)
    end

    test "preserves conversation history" do
      {:ok, pid} = Sigil.Agent.start(SimpleTestAgent, responses: ["First", "Second"])

      {:ok, _} = Sigil.Agent.chat(pid, "Message 1")
      {:ok, _} = Sigil.Agent.chat(pid, "Message 2")

      state = Sigil.Agent.get_state(pid)
      # Should have system + user + assistant + user + assistant
      assert length(state.messages) >= 4

      Sigil.Agent.stop(pid)
    end

    test "tracks run_id" do
      {:ok, pid} = Sigil.Agent.start(SimpleTestAgent)

      run_id = Sigil.Agent.run_id(pid)
      assert is_binary(run_id)
      # UUID
      assert String.length(run_id) == 36

      Sigil.Agent.stop(pid)
    end
  end

  describe "get_state/1" do
    test "returns the agent state struct" do
      {:ok, pid} = Sigil.Agent.start(SimpleTestAgent)

      state = Sigil.Agent.get_state(pid)
      assert state.module == SimpleTestAgent
      assert state.status == :ready
      assert state.turn_count == 0
      assert state.messages == []

      Sigil.Agent.stop(pid)
    end
  end

  describe "mock LLM adapter" do
    test "cycles through responses" do
      {:ok, pid} =
        Sigil.Agent.start(SimpleTestAgent,
          responses: ["Response 1", "Response 2", "Response 3"]
        )

      {:ok, r1} = Sigil.Agent.chat(pid, "First")
      {:ok, r2} = Sigil.Agent.chat(pid, "Second")
      {:ok, r3} = Sigil.Agent.chat(pid, "Third")

      assert r1.content == "Response 1"
      assert r2.content == "Response 2"
      assert r3.content == "Response 3"

      Sigil.Agent.stop(pid)
    end
  end
end
