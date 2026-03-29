defmodule MyApp.Tools.BookMeeting do
  @moduledoc """
  Sigil.Tool that creates a Google Calendar event and sends an invite.

  ## Configuration

  Same as `CheckCalendar` — uses the Google Calendar API credentials
  from config. In demo mode, simulates a successful booking.
  """
  use Sigil.Tool

  @impl true
  def name, do: "book_meeting"

  @impl true
  def description do
    "Book a 30-minute meeting on the calendar. Creates the event and sends a calendar invite to the guest."
  end

  @impl true
  def params do
    %{
      "type" => "object",
      "properties" => %{
        "datetime" => %{
          "type" => "string",
          "description" => "The date and time for the meeting (e.g., '2026-03-30 14:00 ET' or 'Wednesday at 10:00am')"
        },
        "guest_name" => %{
          "type" => "string",
          "description" => "Full name of the guest"
        },
        "guest_email" => %{
          "type" => "string",
          "description" => "Email address to send the calendar invite to"
        },
        "topic" => %{
          "type" => "string",
          "description" => "Brief description of what the meeting is about"
        }
      },
      "required" => ["datetime", "guest_name", "guest_email", "topic"]
    }
  end

  @impl true
  def call(params, _context) do
    config = Application.get_env(:my_app, :google_calendar)

    if config && config[:credentials] do
      create_live_event(params, config)
    else
      demo_booking(params)
    end
  end

  # Live Google Calendar API integration
  defp create_live_event(params, config) do
    calendar_id = config[:calendar_id] || "primary"

    # Parse the datetime
    {start_dt, end_dt} = parse_meeting_time(params["datetime"])

    event = %{
      "summary" => "Meeting with #{params["guest_name"]}: #{params["topic"]}",
      "description" => "Topic: #{params["topic"]}\nBooked via My App",
      "start" => %{"dateTime" => DateTime.to_iso8601(start_dt), "timeZone" => "America/New_York"},
      "end" => %{"dateTime" => DateTime.to_iso8601(end_dt), "timeZone" => "America/New_York"},
      "attendees" => [
        %{"email" => params["guest_email"], "displayName" => params["guest_name"]}
      ],
      "reminders" => %{
        "useDefault" => false,
        "overrides" => [
          %{"method" => "email", "minutes" => 60},
          %{"method" => "popup", "minutes" => 15}
        ]
      }
    }

    url = "https://www.googleapis.com/calendar/v3/calendars/#{URI.encode(calendar_id)}/events?sendUpdates=all"

    case get_access_token(config) do
      {:ok, token} ->
        headers = [
          {"authorization", "Bearer #{token}"},
          {"content-type", "application/json"}
        ]

        case Req.post(url, body: Jason.encode!(event), headers: headers) do
          {:ok, %{status: status, body: body}} when status in [200, 201] ->
            event_link = body["htmlLink"] || ""

            {:ok,
             "Meeting booked successfully!\n" <>
               "- Guest: #{params["guest_name"]} (#{params["guest_email"]})\n" <>
               "- Time: #{params["datetime"]} (30 minutes)\n" <>
               "- Topic: #{params["topic"]}\n" <>
               "- Calendar invite sent to #{params["guest_email"]}\n" <>
               if(event_link != "", do: "- Event link: #{event_link}", else: "")}

          {:ok, %{status: status, body: body}} ->
            {:error, "Calendar API returned #{status}: #{inspect(body)}"}

          {:error, reason} ->
            {:error, "Failed to create event: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to get access token: #{inspect(reason)}"}
    end
  end

  defp get_access_token(config) do
    creds_path = config[:credentials]

    if creds_path && File.exists?(creds_path) do
      creds = creds_path |> File.read!() |> Jason.decode!()
      {:ok, creds["access_token"] || "needs-oauth-setup"}
    else
      {:error, :no_credentials}
    end
  end

  defp parse_meeting_time(datetime_str) do
    # Try ISO format first, then fallback
    case DateTime.from_iso8601(datetime_str) do
      {:ok, dt, _offset} ->
        {dt, DateTime.add(dt, 30 * 60, :second)}

      _ ->
        # Fallback: interpret as "today + time"
        now = DateTime.utc_now()
        end_time = DateTime.add(now, 30 * 60, :second)
        {now, end_time}
    end
  end

  # Demo mode: simulates a successful booking
  defp demo_booking(params) do
    {:ok,
     "Meeting booked successfully!\n" <>
       "- Guest: #{params["guest_name"]} (#{params["guest_email"]})\n" <>
       "- Time: #{params["datetime"]} (30 minutes)\n" <>
       "- Topic: #{params["topic"]}\n" <>
       "- Calendar invite sent to #{params["guest_email"]}\n\n" <>
       "(Demo mode — configure Google Calendar credentials for live booking)"}
  end
end
