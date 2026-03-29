defmodule MyApp.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "posts" do
    field :title, :string
    field :body, :string, default: ""
    field :tags, {:array, :string}, default: []
    field :published, :boolean, default: false
    field :published_at, :utc_datetime

    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :body, :tags, :published, :published_at])
    |> validate_required([:title])
    |> maybe_set_published_at()
  end

  defp maybe_set_published_at(changeset) do
    if get_change(changeset, :published) == true && is_nil(get_field(changeset, :published_at)) do
      put_change(changeset, :published_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      changeset
    end
  end
end
