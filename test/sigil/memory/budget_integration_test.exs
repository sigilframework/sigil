defmodule Sigil.Memory.BudgetIntegrationTest do
  use ExUnit.Case, async: true

  alias Sigil.Memory.{Budget, Context}

  describe "budget-aware sliding window" do
    test "drops oldest messages when exceeding budget" do
      budget =
        Budget.new(model: "custom", context_window: 100, response_buffer: 20)

      # Create enough messages to exceed the small budget
      messages =
        Enum.map(1..20, fn i ->
          %{role: "user", content: "This is message number #{i} with some content"}
        end)

      result = Context.compact(messages, strategy: :sliding_window, budget: budget)

      # Should have fewer messages than original
      assert length(result) < length(messages)
      assert length(result) > 0

      # Should keep the most recent messages
      last_original = List.last(messages)
      last_compacted = List.last(result)
      assert last_compacted.content == last_original.content
    end

    test "preserves system messages when compacting" do
      budget =
        Budget.new(model: "custom", context_window: 100, response_buffer: 20)

      system = %{role: "system", content: "You are a helper"}

      messages =
        [system | Enum.map(1..20, fn i ->
          %{role: "user", content: "This is message number #{i} with some wordy content here"}
        end)]

      result = Context.compact(messages, strategy: :sliding_window, budget: budget)

      # System message must survive compaction
      assert hd(result).role == "system"
      assert hd(result).content == "You are a helper"
    end

    test "does not compact when messages fit" do
      budget = Budget.new(model: "claude-sonnet-4-20250514")

      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      result = Context.compact(messages, strategy: :sliding_window, budget: budget)
      assert length(result) == 2
    end
  end

  describe "budget summary" do
    test "returns utilization metrics" do
      budget =
        Budget.new(model: "claude-sonnet-4-20250514")
        |> Budget.reserve(:system, "You are a helpful assistant")
        |> Budget.reserve(:tools, "Some tool definitions here")

      summary = Budget.summary(budget)

      assert summary.model == "claude-sonnet-4-20250514"
      assert summary.total == 200_000
      assert summary.total_reserved > 0
      assert summary.available_for_history > 0
      assert summary.utilization_pct > 0
      assert is_float(summary.utilization_pct)
    end
  end

  describe "budget reserve_tokens/3" do
    test "reserves exact token count without tokenization" do
      budget =
        Budget.new(model: "custom", context_window: 10_000)
        |> Budget.reserve_tokens(:fixed_cost, 5_000)

      assert budget.reservations[:fixed_cost] == 5_000
      # Half the budget is now reserved (5000 fixed + 4096 response)
      assert Budget.available(budget) < 1_000
    end
  end
end
