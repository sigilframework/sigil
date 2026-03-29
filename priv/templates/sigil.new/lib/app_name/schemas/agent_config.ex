defmodule Journal.AgentConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "agent_configs" do
    field :name, :string
    field :slug, :string
    field :system_prompt, :string
    field :model, :string, default: "claude-sonnet-4-20250514"
    field :active, :boolean, default: true
    field :tools, {:array, :string}, default: []

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:name, :slug, :system_prompt, :model, :active, :tools])
    |> validate_required([:name, :system_prompt])
    |> maybe_generate_slug()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""

        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end
