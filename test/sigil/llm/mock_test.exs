defmodule Sigil.LLM.MockTest do
  use ExUnit.Case, async: true

  alias Sigil.LLM.Mock

  setup do
    Mock.reset()
    :ok
  end

  describe "chat/2" do
    test "returns configured response" do
      {:ok, response} = Mock.chat([], responses: ["Hello!"])
      assert response.content == "Hello!"
      assert response.role == "assistant"
      assert response.tool_calls == []
    end

    test "cycles through multiple responses" do
      opts = [responses: ["First", "Second", "Third"]]

      {:ok, r1} = Mock.chat([], opts)
      {:ok, r2} = Mock.chat([], opts)
      {:ok, r3} = Mock.chat([], opts)

      assert r1.content == "First"
      assert r2.content == "Second"
      assert r3.content == "Third"
    end

    test "wraps around when responses are exhausted" do
      opts = [responses: ["A", "B"]]

      {:ok, _} = Mock.chat([], opts)
      {:ok, _} = Mock.chat([], opts)
      {:ok, r3} = Mock.chat([], opts)

      assert r3.content == "A"
    end

    test "simulates latency" do
      start = System.monotonic_time(:millisecond)
      {:ok, _} = Mock.chat([], responses: ["Hi"], delay_ms: 100)
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 90
    end

    test "fails on specified call number" do
      opts = [responses: ["OK"], fail_on: 2]

      {:ok, _} = Mock.chat([], opts)
      {:error, _} = Mock.chat([], opts)
      {:ok, _} = Mock.chat([], opts)
    end

    test "handles tool call responses" do
      tool_response = %{
        content: "I'll search for that.",
        tool_calls: [%{id: "call_1", name: "search", input: %{"q" => "test"}}]
      }

      {:ok, response} = Mock.chat([], responses: [tool_response])
      assert response.content == "I'll search for that."
      assert length(response.tool_calls) == 1
      assert hd(response.tool_calls).name == "search"
    end

    test "tracks call count" do
      assert Mock.call_count() == 0

      Mock.chat([], responses: ["Hi"])
      assert Mock.call_count() == 1

      Mock.chat([], responses: ["Hi"])
      assert Mock.call_count() == 2
    end

    test "includes usage data" do
      {:ok, response} = Mock.chat([], responses: ["Hello"])
      assert response.usage.input_tokens > 0
      assert response.usage.output_tokens > 0
      assert response.token_count > 0
    end
  end

  describe "embed/2" do
    test "returns deterministic embedding" do
      {:ok, embedding} = Mock.embed("test input", [])
      assert is_list(embedding)
      assert length(embedding) == 1536

      # Same input should give same embedding
      {:ok, embedding2} = Mock.embed("test input", [])
      assert embedding == embedding2
    end

    test "different inputs give different embeddings" do
      {:ok, e1} = Mock.embed("hello", [])
      {:ok, e2} = Mock.embed("goodbye", [])
      assert e1 != e2
    end
  end

  describe "reset/0" do
    test "resets the call counter" do
      Mock.chat([], responses: ["Hi"])
      Mock.chat([], responses: ["Hi"])
      assert Mock.call_count() == 2

      Mock.reset()
      assert Mock.call_count() == 0
    end
  end
end
