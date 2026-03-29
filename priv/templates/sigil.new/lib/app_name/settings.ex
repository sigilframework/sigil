defmodule MyApp.Settings do
  @moduledoc """
  Context for managing site settings and user account updates.
  """

  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Schemas.SiteSetting

  @defaults %{
    "site_name" => "My App",
    "site_tagline" => "Notes on strategy, systems, work, and life"
  }

  @doc "Get a setting value by key, falling back to defaults."
  def get(key) when is_binary(key) do
    case Repo.one(from s in SiteSetting, where: s.key == ^key) do
      nil -> Map.get(@defaults, key, "")
      setting -> setting.value || Map.get(@defaults, key, "")
    end
  rescue
    _ -> Map.get(@defaults, key, "")
  end

  @doc "Get all settings as a map."
  def all do
    stored =
      Repo.all(SiteSetting)
      |> Enum.into(%{}, fn s -> {s.key, s.value} end)

    Map.merge(@defaults, stored)
  rescue
    _ -> @defaults
  end

  @doc "Upsert a setting."
  def put(key, value) when is_binary(key) do
    %SiteSetting{key: key}
    |> SiteSetting.changeset(%{key: key, value: value})
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )
  end

  # --- User Account ---

  @doc "Update email for a user."
  def update_email(user, new_email) do
    user
    |> Ecto.Changeset.change(%{email: new_email})
    |> Ecto.Changeset.validate_format(:email, ~r/@/, message: "must be a valid email")
    |> Ecto.Changeset.unique_constraint(:email)
    |> Repo.update()
  end

  @doc "Update password for a user. Returns {:ok, user} or {:error, reason}."
  def update_password(user, new_password) do
    if String.length(new_password) < 8 do
      {:error, "Password must be at least 8 characters"}
    else
      user
      |> Ecto.Changeset.change(%{password_hash: Sigil.Auth.Password.hash(new_password)})
      |> Repo.update()
      |> case do
        {:ok, user} -> {:ok, user}
        {:error, _changeset} -> {:error, "Failed to update password"}
      end
    end
  end
end
