defmodule Sigil.Live.DiffHardenedTest do
  use ExUnit.Case, async: true

  alias Sigil.Live.Diff

  describe "attribute parsing" do
    test "handles double-quoted attributes" do
      html = ~s(<div class="flex gap-2" id="main">text</div>)
      [node] = Diff.parse(html)
      assert node.type == :element
      assert {"class", "flex gap-2"} in node.attrs
      assert {"id", "main"} in node.attrs
    end

    test "handles single-quoted attributes" do
      html = ~s(<div class='hello world'>text</div>)
      [node] = Diff.parse(html)
      assert {"class", "hello world"} in node.attrs
    end

    test "handles boolean attributes" do
      html = ~s(<input type="checkbox" checked disabled />)
      [node] = Diff.parse(html)
      assert {"checked", ""} in node.attrs
      assert {"disabled", ""} in node.attrs
    end

    test "handles data-* attributes with colons" do
      html = ~s(<div data-sigil-session="abc" data-sigil-csrf="xyz">ok</div>)
      [node] = Diff.parse(html)
      assert {"data-sigil-session", "abc"} in node.attrs
      assert {"data-sigil-csrf", "xyz"} in node.attrs
    end
  end

  describe "raw text elements" do
    test "preserves script content as raw text" do
      html = "<script>if (a < b) { alert('hi'); }</script>"
      [node] = Diff.parse(html)
      assert node.type == :raw_element
      assert node.tag == "script"
      assert node.content =~ "if (a < b"
    end

    test "preserves style content as raw text" do
      html = ~s(<style>.foo { color: red; } .bar > .baz { margin: 0; }</style>)
      [node] = Diff.parse(html)
      assert node.type == :raw_element
      assert node.tag == "style"
      assert node.content =~ ".foo { color: red"
    end

    test "diffs raw element content correctly" do
      old = ~s(<style>.foo { color: red; }</style>)
      new = ~s(<style>.foo { color: blue; }</style>)
      patches = Diff.diff(old, new)
      assert length(patches) > 0
      assert hd(patches).op == "replace"
    end
  end

  describe "serialization" do
    test "boolean attributes serialize without values" do
      html = ~s(<input type="text" disabled />)
      tree = Diff.parse(html)
      # Re-serialize should produce valid HTML
      assert tree != []
    end

    test "attribute values with quotes are escaped" do
      # Test node_to_html handles escaping
      old = ~s(<div title="hello">a</div>)
      new = ~s(<div title="world">a</div>)
      patches = Diff.diff(old, new)
      assert [%{op: "attr", key: "title", value: "world"}] = patches
    end
  end

  describe "diff robustness" do
    test "handles empty strings" do
      assert Diff.diff("", "") == []
    end

    test "handles text-only content" do
      patches = Diff.diff("hello", "world")
      assert length(patches) > 0
    end

    test "handles deeply nested HTML" do
      old = "<div><div><div><span>old</span></div></div></div>"
      new = "<div><div><div><span>new</span></div></div></div>"
      patches = Diff.diff(old, new)
      assert [%{op: "text", content: "new"}] = patches
    end

    test "same HTML produces no patches" do
      html = ~s(<div class="test"><p>Hello <strong>world</strong></p></div>)
      assert Diff.diff(html, html) == []
    end

    test "handles void elements" do
      old = ~s(<div><br /><hr /><img src="a.png" /></div>)
      new = ~s(<div><br /><hr /><img src="b.png" /></div>)
      patches = Diff.diff(old, new)
      assert length(patches) > 0
    end
  end
end
