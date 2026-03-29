defmodule Journal.Blog do
  @moduledoc "Context for managing blog posts."

  import Ecto.Query
  alias Journal.{Repo, Post}

  def list_posts do
    from(p in Post, order_by: [desc: p.inserted_at])
    |> Repo.all()
  end

  def list_published_posts do
    from(p in Post,
      where: p.published == true,
      order_by: [desc: p.published_at]
    )
    |> Repo.all()
  end

  def get_post!(id), do: Repo.get!(Post, id)

  def create_post(attrs) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  def search_posts(query) do
    term = "%#{query}%"

    from(p in Post,
      where: p.published == true,
      where: ilike(p.title, ^term) or ilike(p.body, ^term) or ^query in p.tags,
      order_by: [desc: p.published_at],
      limit: 5
    )
    |> Repo.all()
  end

  def list_tags do
    from(p in Post,
      where: p.published == true,
      select: p.tags
    )
    |> Repo.all()
    |> List.flatten()
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_tag, count} -> -count end)
    |> Enum.map(fn {tag, _count} -> tag end)
  end

  @doc "Returns {prev_post, next_post} relative to the given post (by published_at)."
  def adjacent_posts(%Post{} = post) do
    published_at = post.published_at || post.inserted_at

    prev =
      from(p in Post,
        where: p.published == true,
        where: p.id != ^post.id,
        where: p.published_at > ^published_at,
        order_by: [asc: p.published_at],
        limit: 1
      )
      |> Repo.one()

    next =
      from(p in Post,
        where: p.published == true,
        where: p.id != ^post.id,
        where: p.published_at < ^published_at,
        order_by: [desc: p.published_at],
        limit: 1
      )
      |> Repo.one()

    {prev, next}
  end
end
