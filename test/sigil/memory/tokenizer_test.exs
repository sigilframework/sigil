defmodule Sigil.Memory.TokenizerTest do
  use ExUnit.Case, async: true

  alias Sigil.Memory.Tokenizer

  describe "count/2" do
    test "returns positive token count for non-empty text" do
      count = Tokenizer.count("Hello, world!")
      assert count > 0
      assert is_integer(count)
    end

    test "returns 0 for empty string" do
      assert Tokenizer.count("") == 0
    end

    test "handles nil gracefully" do
      assert Tokenizer.count(nil) == 0
    end

    test "counts words and special tokens" do
      # ~1 token per word is a rough baseline
      text = "The quick brown fox jumps over the lazy dog"
      count = Tokenizer.count(text)
      # Should be roughly 9-12 tokens for 9 words
      assert count >= 5
      assert count <= 20
    end

    test "handles code content" do
      code = """
      defmodule Foo do
        def bar(x), do: x + 1
      end
      """

      count = Tokenizer.count(code)
      assert count > 5
    end

    test "handles JSON content" do
      json = ~s({"name": "John", "age": 30, "items": [1, 2, 3]})
      count = Tokenizer.count(json)
      assert count > 5
    end
  end

  describe "count_messages/2" do
    test "counts tokens across multiple messages" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there! How can I help?"}
      ]

      count = Tokenizer.count_messages(messages)
      assert count > 0
      # Should include overhead per message
      assert count > Tokenizer.count("Hello") + Tokenizer.count("Hi there! How can I help?")
    end

    test "handles empty message list" do
      assert Tokenizer.count_messages([]) == 0
    end

    test "handles messages with list content" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Hello"},
            %{type: "tool_result", tool_use_id: "1", content: "result data"}
          ]
        }
      ]

      count = Tokenizer.count_messages(messages)
      assert count > 0
    end
  end
end
