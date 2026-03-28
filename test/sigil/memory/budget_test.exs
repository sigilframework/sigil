defmodule Sigil.Memory.BudgetTest do
  use ExUnit.Case, async: true

  alias Sigil.Memory.Budget

  describe "new/1" do
    test "creates a budget with model defaults" do
      budget = Budget.new(model: "claude-sonnet-4-20250514")
      assert budget.total > 0
      assert budget.response_buffer > 0
    end

    test "creates a budget with custom limit" do
      budget = Budget.new(model: "custom", context_window: 8_000)
      assert budget.total == 8_000
    end


  end

  describe "reserve/3" do
    test "reserves tokens for system prompt" do
      budget = Budget.new(model: "claude-sonnet-4-20250514")
      budget = Budget.reserve(budget, :system, "You are a helpful assistant.")

      assert budget.reservations[:system] > 0
    end

    test "reserves tokens for string content" do
      budget = Budget.new(model: "claude-sonnet-4-20250514")
      budget = Budget.reserve(budget, :my_slot, "Some content here")

      assert budget.reservations[:my_slot] > 0
    end
  end

  describe "available/1" do
    test "returns remaining tokens after reservations" do
      budget = Budget.new(model: "claude-sonnet-4-20250514")
      full_available = Budget.available(budget)

      budget = Budget.reserve(budget, :system, "You are a helpful assistant.")
      after_reserve = Budget.available(budget)

      assert after_reserve < full_available
      assert after_reserve > 0
    end
  end

  describe "fits?/2" do
    test "returns true when messages fit" do
      budget = Budget.new(model: "claude-sonnet-4-20250514")
      messages = [%{role: "user", content: "Hello"}]

      assert Budget.fits?(budget, messages) == true
    end

    test "returns false when messages exceed budget" do
      budget = Budget.new(model: "custom", context_window: 50, response_buffer: 10)
      # Create a message that exceeds the tiny budget
      long_message = String.duplicate("word ", 200)
      messages = [%{role: "user", content: long_message}]

      assert Budget.fits?(budget, messages) == false
    end
  end
end
