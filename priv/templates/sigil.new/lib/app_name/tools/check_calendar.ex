defmodule MyApp.Tools.CheckCalendar do
  @moduledoc """
  Sigil.Tool that checks Google Calendar for available meeting slots.

  Returns available 30-minute slots over the next 5 business days.

  ## Configuration

  Set the Google Calendar OAuth credentials in config:

      config :my_app, :google_calendar,
        calendar_id: "admin@example.com",
        credentials: "/path/to/service-account.json"

  When no credentials are configured, returns realistic demo availability
  so the agent flow can be tested end-to-end.
  """
  use Sigil.Tool

  @impl true
  def name, do: "check_calendar"

  @impl true
  def description do
    "Check the calendar for available 30-minute meeting slots over the next 5 business days."
  end

  @impl true
  def params do
    %{
      "type" => "object",
      "properties" => %{
        "reason" => %{
          "type" => "string",
          "description" => "Brief description of the meeting topic (for context)"
        }
      },
      "required" => ["reason"]
    }
  end

  @impl true
  def call(%{"reason" => _reason}, _context) do
    config = Application.get_env(:my_app, :google_calendar)

    if config && config[:credentials] do
      check_live_calendar(config)
    else
      demo_availability()
    end
  end

  # Live Google Calendar API integration
  defp check_live_calendar(config) do
    calendar_id = config[:calendar_id] || "primary"

    # Calculate time range: next 5 business days
    now = DateTime.utc_now()
    five_days = DateTime.add(now, 5 * 24 * 60 * 60, :second)

    # Google Calendar FreeBusy API
    url = "https://www.googleapis.com/calendar/v3/freeBusy"

    body =
      Jason.encode!(%{
        "timeMin" => DateTime.to_iso8601(now),
        "timeMax" => DateTime.to_iso8601(five_days),
        "items" => [%{"id" => calendar_id}]
      })

    case get_access_token(config) do
      {:ok, token} ->
        headers = [
          {"authorization", "Bearer #{token}"},
          {"content-type", "application/json"}
        ]

        case Req.post(url, body: body, headers: headers) do
          {:ok, %{status: 200, body: resp}} ->
            busy_periods = get_in(resp, ["calendars", calendar_id, "busy"]) || []
            slots = find_available_slots(now, five_days, busy_periods)
            format_slots(slots)

          {:ok, %{status: status, body: body}} ->
            {:error, "Calendar API returned #{status}: #{inspect(body)}"}

          {:error, reason} ->
            {:error, "Calendar API request failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to get access token: #{inspect(reason)}"}
    end
  end

  defp get_access_token(config) do
    creds_path = config[:credentials]

    if creds_path && File.exists?(creds_path) do
      # Service account JWT flow
      creds = creds_path |> File.read!() |> Jason.decode!()
      # Simplified — in production, use Goth or similar library
      {:ok, creds["access_token"] || "needs-oauth-setup"}
    else
      {:error, :no_credentials}
    end
  end

  defp find_available_slots(from, to, busy_periods) do
    # Generate 30-minute slots during business hours (9am-5pm ET)
    from
    |> generate_business_slots(to)
    |> Enum.reject(fn slot ->
      Enum.any?(busy_periods, fn busy ->
        {:ok, busy_start, _} = DateTime.from_iso8601(busy["start"])
        {:ok, busy_end, _} = DateTime.from_iso8601(busy["end"])
        DateTime.compare(slot, busy_start) != :lt and
          DateTime.compare(slot, busy_end) == :lt
      end)
    end)
    |> Enum.take(6)
  end

  defp generate_business_slots(from, to) do
    from
    |> Stream.iterate(&DateTime.add(&1, 30 * 60, :second))
    |> Stream.take_while(&(DateTime.compare(&1, to) == :lt))
    |> Stream.filter(fn dt ->
      # Business hours: 9am-5pm (assuming UTC-4 for ET)
      hour = dt.hour - 4
      day = Date.day_of_week(DateTime.to_date(dt))
      hour >= 9 and hour < 17 and day in 1..5
    end)
    |> Enum.to_list()
  end

  # Demo mode: returns realistic-looking availability
  defp demo_availability do
    today = Date.utc_today()

    slots =
      1..7
      |> Enum.map(&Date.add(today, &1))
      |> Enum.filter(&(Date.day_of_week(&1) in 1..5))
      |> Enum.take(3)
      |> Enum.flat_map(fn date ->
        # 2 slots per day at varied times
        times = Enum.take_random(["10:00", "11:00", "13:00", "14:00", "15:00", "16:00"], 2)
        Enum.map(times, fn time -> "#{date} #{time} ET" end)
      end)
      |> Enum.take(5)

    formatted =
      slots
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {slot, i} ->
        "#{i}. #{format_friendly_date(slot)}"
      end)

    {:ok, "Available 30-minute slots:\n\n#{formatted}\n\n(Times shown in Eastern Time)"}
  end

  defp format_slots(slots) do
    if slots == [] do
      {:ok, "No available slots found in the next 5 business days. the calendar is fully booked — please try again next week."}
    else
      formatted =
        slots
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {dt, i} ->
          "#{i}. #{Calendar.strftime(dt, "%A, %B %d at %I:%M %p")} ET"
        end)

      {:ok, "Available 30-minute slots:\n\n#{formatted}\n\n(Times shown in Eastern Time)"}
    end
  end

  defp format_friendly_date(slot_string) do
    # Parse "2026-03-30 14:00 ET" into friendly format
    case String.split(slot_string, " ") do
      [date_str, time_str | _] ->
        case Date.from_iso8601(date_str) do
          {:ok, date} ->
            day_name = Calendar.strftime(date, "%A")
            month_day = Calendar.strftime(date, "%B %d")
            "#{day_name}, #{month_day} at #{time_str} ET"

          _ ->
            slot_string
        end

      _ ->
        slot_string
    end
  end
end
