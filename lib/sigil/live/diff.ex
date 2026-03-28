defmodule Sigil.Live.Diff do
  @moduledoc """
  Server-side DOM diffing engine.

  Compares two HTML strings and produces a minimal set of patch
  operations that the client can apply to update the DOM without
  a full page reload.

  ## Patch Operations

  - `%{op: "replace", path: [...], html: "..."}` — Replace an element
  - `%{op: "text", path: [...], content: "..."}` — Update a text node
  - `%{op: "attr", path: [...], key: "...", value: "..."}` — Set attribute
  - `%{op: "remove_attr", path: [...], key: "..."}` — Remove attribute
  - `%{op: "remove", path: [...]}` — Remove an element
  - `%{op: "insert", path: [...], html: "..."}` — Insert HTML

  ## Robustness

  - Handles single and double-quoted attribute values
  - Handles boolean attributes (e.g., `disabled`, `checked`)
  - Preserves raw content in `<script>`, `<style>`, and `<textarea>` tags
  - Falls back to full replacement when subtree diff exceeds threshold
  - Properly handles HTML entities in attribute values
  """

  # Maximum number of child patches before falling back to full replace
  @max_child_patches 50

  # Tags whose content should be treated as raw text (not parsed as HTML)
  @raw_tags ~w(script style textarea)

  # Void elements (self-closing, no children)
  @void_elements ~w(area base br col embed hr img input link meta param source track wbr)

  @doc """
  Compare two HTML strings and return a list of patches.

  Returns a list of maps suitable for JSON serialization:

      [%{op: "replace", path: [0, :children, 1], html: "<p>new</p>"}]
  """
  def diff(old_html, new_html) when is_binary(old_html) and is_binary(new_html) do
    if old_html == new_html do
      []
    else
      old_tree = parse(old_html)
      new_tree = parse(new_html)
      compare_trees(old_tree, new_tree, [])
    end
  end

  # --- Parsing ---

  @doc false
  def parse(html) do
    html
    |> String.trim()
    |> tokenize([])
    |> build_tree()
  end

  # Tokenizer

  defp tokenize("", acc), do: Enum.reverse(acc)

  # HTML comments
  defp tokenize(<<"<!--", rest::binary>>, acc) do
    case String.split(rest, "-->", parts: 2) do
      [_comment, rest] -> tokenize(rest, acc)
      _ -> Enum.reverse(acc)
    end
  end

  # Closing tags
  defp tokenize(<<"</", rest::binary>>, acc) do
    case extract_tag_name(rest) do
      {tag_name, rest} ->
        rest = skip_until_gt(rest)
        tokenize(rest, [{:close, tag_name} | acc])

      nil ->
        tokenize(rest, acc)
    end
  end

  # Opening tags
  defp tokenize(<<"<", rest::binary>>, acc) do
    case parse_open_tag(rest) do
      {:ok, tag_name, attrs, self_closing, rest} ->
        if tag_name in @raw_tags and not self_closing do
          # Raw tags: extract everything until </tag>
          close_tag = "</#{tag_name}>"

          case String.split(rest, close_tag, parts: 2) do
            [raw_content, rest] ->
              token = {:raw_element, tag_name, attrs, raw_content}
              tokenize(rest, [token | acc])

            [_no_close] ->
              # No closing tag found — treat as self-closing
              token = {:raw_element, tag_name, attrs, rest}
              tokenize("", [token | acc])
          end
        else
          token =
            if self_closing do
              {:self_closing, tag_name, attrs}
            else
              {:open, tag_name, attrs}
            end

          tokenize(rest, [token | acc])
        end

      :error ->
        # Not a valid tag — treat < as text
        tokenize(rest, [{:text, "<"} | acc])
    end
  end

  # Text content
  defp tokenize(html, acc) do
    case String.split(html, "<", parts: 2) do
      [text, rest] ->
        text = String.trim(text)

        if text != "" do
          tokenize("<" <> rest, [{:text, text} | acc])
        else
          tokenize("<" <> rest, acc)
        end

      [text] ->
        text = String.trim(text)

        if text != "" do
          Enum.reverse([{:text, text} | acc])
        else
          Enum.reverse(acc)
        end
    end
  end

  defp extract_tag_name(str) do
    case Regex.run(~r/^([a-zA-Z][a-zA-Z0-9-]*)/, str) do
      [_, name] -> {String.downcase(name), String.slice(str, String.length(name)..-1//1)}
      _ -> nil
    end
  end

  defp skip_until_gt(str) do
    case String.split(str, ">", parts: 2) do
      [_, rest] -> rest
      _ -> ""
    end
  end

  # Attribute parsing — handles single/double quotes and boolean attrs

  defp parse_open_tag(str) do
    case extract_tag_name(str) do
      {tag_name, rest} ->
        {attrs, rest} = parse_attrs(String.trim(rest), [])

        {self_closing, rest} =
          cond do
            String.starts_with?(rest, "/>") -> {true, String.slice(rest, 2..-1//1)}
            String.starts_with?(rest, ">") -> {false, String.slice(rest, 1..-1//1)}
            true -> {false, rest}
          end

        # Void elements are always self-closing
        self_closing = self_closing or tag_name in @void_elements

        {:ok, tag_name, attrs, self_closing, rest}

      nil ->
        :error
    end
  end

  defp parse_attrs(">" <> _ = rest, acc), do: {Enum.reverse(acc), rest}
  defp parse_attrs("/>" <> _ = rest, acc), do: {Enum.reverse(acc), rest}
  defp parse_attrs("", acc), do: {Enum.reverse(acc), ""}

  defp parse_attrs(str, acc) do
    str = String.trim_leading(str)

    cond do
      # double-quoted: key="value"
      match = Regex.run(~r/^([a-zA-Z_:][a-zA-Z0-9_\-:.]*)="([^"]*)"/, str) ->
        [full, key, value] = match
        rest = String.slice(str, String.length(full)..-1//1)
        parse_attrs(rest, [{key, value} | acc])

      # single-quoted: key='value'
      match = Regex.run(~r/^([a-zA-Z_:][a-zA-Z0-9_\-:.]*)='([^']*)'/, str) ->
        [full, key, value] = match
        rest = String.slice(str, String.length(full)..-1//1)
        parse_attrs(rest, [{key, value} | acc])

      # boolean attribute: just the key (e.g., disabled, checked)
      match = Regex.run(~r/^([a-zA-Z_:][a-zA-Z0-9_\-:.]*)(?=[\s\/>])/, str) ->
        [full, key] = match
        rest = String.slice(str, String.length(full)..-1//1)
        parse_attrs(rest, [{key, ""} | acc])

      true ->
        {Enum.reverse(acc), str}
    end
  end

  # --- Tree building ---

  defp build_tree(tokens) do
    {nodes, _remaining} = build_nodes(tokens, nil)
    nodes
  end

  defp build_nodes([], _parent_tag), do: {[], []}

  defp build_nodes([{:close, tag} | rest], parent_tag) when tag == parent_tag do
    {[], rest}
  end

  defp build_nodes([{:close, _tag} | rest], parent_tag) do
    # Mismatched close tag — skip and continue
    build_nodes(rest, parent_tag)
  end

  defp build_nodes([{:text, text} | rest], parent_tag) do
    {siblings, remaining} = build_nodes(rest, parent_tag)
    {[%{type: :text, content: text} | siblings], remaining}
  end

  defp build_nodes([{:self_closing, tag, attrs} | rest], parent_tag) do
    node = %{type: :element, tag: tag, attrs: attrs, children: []}
    {siblings, remaining} = build_nodes(rest, parent_tag)
    {[node | siblings], remaining}
  end

  defp build_nodes([{:raw_element, tag, attrs, raw_content} | rest], parent_tag) do
    node = %{type: :raw_element, tag: tag, attrs: attrs, content: raw_content}
    {siblings, remaining} = build_nodes(rest, parent_tag)
    {[node | siblings], remaining}
  end

  defp build_nodes([{:open, tag, attrs} | rest], parent_tag) do
    {children, after_close} = build_nodes(rest, tag)
    node = %{type: :element, tag: tag, attrs: attrs, children: children}
    {siblings, remaining} = build_nodes(after_close, parent_tag)
    {[node | siblings], remaining}
  end

  # --- Comparison ---

  defp compare_trees(old_nodes, new_nodes, path) when is_list(old_nodes) and is_list(new_nodes) do
    max_len = max(length(old_nodes), length(new_nodes))

    # If one side is dramatically larger than the other, just do full replace
    if max_len > @max_child_patches do
      old_html = Enum.map_join(old_nodes, "", &node_to_html/1)
      new_html = Enum.map_join(new_nodes, "", &node_to_html/1)

      if old_html != new_html do
        # Return a single replace for the parent
        [%{op: "replace_children", path: path, html: new_html}]
      else
        []
      end
    else
      old_padded = old_nodes ++ List.duplicate(nil, max_len - length(old_nodes))
      new_padded = new_nodes ++ List.duplicate(nil, max_len - length(new_nodes))

      patches =
        old_padded
        |> Enum.zip(new_padded)
        |> Enum.with_index()
        |> Enum.flat_map(fn {{old, new}, idx} ->
          compare_node(old, new, path ++ [idx])
        end)

      # If we generate too many patches, collapse to a single replace
      if length(patches) > @max_child_patches do
        new_html = Enum.map_join(new_nodes, "", &node_to_html/1)
        [%{op: "replace_children", path: path, html: new_html}]
      else
        patches
      end
    end
  end

  defp compare_node(nil, %{} = new_node, path) do
    [%{op: "insert", path: path, html: node_to_html(new_node)}]
  end

  defp compare_node(%{} = _old_node, nil, path) do
    [%{op: "remove", path: path}]
  end

  defp compare_node(%{type: :text, content: old}, %{type: :text, content: new}, path) do
    if old == new, do: [], else: [%{op: "text", path: path, content: new}]
  end

  # Raw elements (script, style, textarea) — compare content as text
  defp compare_node(
         %{type: :raw_element, tag: tag, attrs: old_attrs, content: old_content},
         %{type: :raw_element, tag: tag, attrs: new_attrs, content: new_content},
         path
       ) do
    attr_patches = compare_attrs(old_attrs, new_attrs, path)

    content_patches =
      if old_content == new_content do
        []
      else
        [
          %{
            op: "replace",
            path: path,
            html:
              node_to_html(%{
                type: :raw_element,
                tag: tag,
                attrs: new_attrs,
                content: new_content
              })
          }
        ]
      end

    attr_patches ++ content_patches
  end

  # Same tag — deep compare
  defp compare_node(
         %{type: :element, tag: tag, attrs: old_attrs, children: old_children},
         %{type: :element, tag: tag, attrs: new_attrs, children: new_children},
         path
       ) do
    attr_patches = compare_attrs(old_attrs, new_attrs, path)
    child_patches = compare_trees(old_children, new_children, path ++ [:children])
    attr_patches ++ child_patches
  end

  # Different types or tags — full replacement
  defp compare_node(_old, %{} = new_node, path) do
    [%{op: "replace", path: path, html: node_to_html(new_node)}]
  end

  defp compare_attrs(old_attrs, new_attrs, path) do
    old_map = Map.new(old_attrs)
    new_map = Map.new(new_attrs)

    if old_map == new_map do
      []
    else
      # Changed/added attrs
      changed =
        Enum.flat_map(new_map, fn {key, value} ->
          if Map.get(old_map, key) != value do
            [%{op: "attr", path: path, key: key, value: value}]
          else
            []
          end
        end)

      # Removed attrs
      removed =
        Enum.flat_map(old_map, fn {key, _value} ->
          if not Map.has_key?(new_map, key) do
            [%{op: "remove_attr", path: path, key: key}]
          else
            []
          end
        end)

      changed ++ removed
    end
  end

  # --- Serialization ---

  defp node_to_html(%{type: :text, content: text}), do: text

  defp node_to_html(%{type: :raw_element, tag: tag, attrs: attrs, content: content}) do
    attr_str = attrs_to_string(attrs)
    "<#{tag}#{attr_str}>#{content}</#{tag}>"
  end

  defp node_to_html(%{type: :element, tag: tag, attrs: attrs, children: children}) do
    attr_str = attrs_to_string(attrs)

    if children == [] and tag in @void_elements do
      "<#{tag}#{attr_str} />"
    else
      inner = Enum.map_join(children, "", &node_to_html/1)
      "<#{tag}#{attr_str}>#{inner}</#{tag}>"
    end
  end

  defp attrs_to_string([]), do: ""

  defp attrs_to_string(attrs) do
    " " <>
      Enum.map_join(attrs, " ", fn
        # Boolean attribute
        {k, ""} ->
          k

        {k, v} ->
          # Use double quotes, escape any double quotes in the value
          escaped = String.replace(v, "\"", "&quot;")
          ~s(#{k}="#{escaped}")
      end)
  end
end
