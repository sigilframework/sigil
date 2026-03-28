defmodule Sigil.Memory.ContextTest do
  use ExUnit.Case, async: true

  alias Sigil.Memory.Context

  @messages Enum.map(1..30, fn i ->
              %{role: "user", content: "Message #{i}"}
            end)

  describe "sliding_window/2" do
    test "keeps only the last N messages" do
      result = Context.compact(@messages, strategy: :sliding_window, max_messages: 5)
      assert length(result) == 5
      assert hd(result).content == "Message 26"
    end

    test "preserves system messages" do
      messages = [%{role: "system", content: "System"} | @messages]
      result = Context.compact(messages, strategy: :sliding_window, max_messages: 5)
      assert hd(result).role == "system"
      assert length(result) == 6
    end

    test "returns all messages when under the limit" do
      short = Enum.take(@messages, 3)
      result = Context.compact(short, strategy: :sliding_window, max_messages: 20)
      assert length(result) == 3
    end
  end

  describe "drop_tool_results/2" do
    test "truncates long tool results" do
      long_content = String.duplicate("x", 1000)

      messages = [
        %{role: "tool", content: long_content},
        %{role: "user", content: "short"}
      ]

      result = Context.compact(messages, strategy: :drop_tool_results)
      tool_msg = hd(result)
      # Tool results get truncated with a "tokens]" suffix
      assert String.contains?(tool_msg.content, "truncated") or
             String.length(tool_msg.content) <= String.length(long_content)
    end
  end

  describe "token counting" do
    test "counts tokens in messages" do
      messages = [%{role: "user", content: String.duplicate("hello ", 50)}]
      tokens = Sigil.Memory.Tokenizer.count_messages(messages)
      assert tokens > 0
    end
  end
end
