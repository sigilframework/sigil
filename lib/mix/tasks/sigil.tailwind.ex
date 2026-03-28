defmodule Mix.Tasks.Sigil.Tailwind do
  @moduledoc """
  Manages Tailwind CSS for Sigil applications.

  ## Setup

      mix sigil.tailwind install

  This downloads the Tailwind standalone CLI and creates a default
  `tailwind.config.js` and input CSS file.

  ## Watch mode (for development)

      mix sigil.tailwind watch

  ## Build (for production)

      mix sigil.tailwind build
  """
  use Mix.Task

  @tailwind_version "3.4.17"
  @bin_path "_build/tailwind"

  @impl true
  def run(["install" | _]) do
    install()
  end

  def run(["watch" | _]) do
    ensure_installed()
    Mix.shell().info("Watching for CSS changes...")

    System.cmd(
      bin_path(),
      [
        "--input",
        "assets/app.css",
        "--output",
        "priv/static/app.css",
        "--watch"
      ],
      into: IO.stream(:stdio, :line)
    )
  end

  def run(["build" | _]) do
    ensure_installed()
    Mix.shell().info("Building CSS for production...")

    System.cmd(
      bin_path(),
      [
        "--input",
        "assets/app.css",
        "--output",
        "priv/static/app.css",
        "--minify"
      ],
      into: IO.stream(:stdio, :line)
    )
  end

  def run(_) do
    Mix.shell().info("""
    Usage:
      mix sigil.tailwind install   # Download Tailwind CLI and create config
      mix sigil.tailwind watch     # Watch for changes (dev)
      mix sigil.tailwind build     # Build for production
    """)
  end

  defp install do
    Mix.shell().info("Installing Tailwind CSS v#{@tailwind_version}...")

    # Determine platform
    {os, arch} = platform()
    filename = "tailwindcss-#{os}-#{arch}"

    url =
      "https://github.com/tailwindlabs/tailwindcss/releases/download/v#{@tailwind_version}/#{filename}"

    # Download
    File.mkdir_p!(Path.dirname(bin_path()))
    Mix.shell().info("Downloading from #{url}...")

    case System.cmd("curl", ["-sL", "-o", bin_path(), url]) do
      {_, 0} ->
        File.chmod!(bin_path(), 0o755)
        Mix.shell().info("✓ Tailwind CLI installed at #{bin_path()}")

      {err, _} ->
        Mix.raise("Failed to download Tailwind: #{err}")
    end

    # Create default config if not present
    unless File.exists?("tailwind.config.js") do
      File.write!("tailwind.config.js", """
      /** @type {import('tailwindcss').Config} */
      module.exports = {
        content: [
          "./lib/**/*.ex",
          "./lib/**/*.html",
        ],
        theme: {
          extend: {},
        },
        plugins: [],
      }
      """)

      Mix.shell().info("✓ Created tailwind.config.js")
    end

    # Create default input CSS
    File.mkdir_p!("assets")

    unless File.exists?("assets/app.css") do
      File.write!("assets/app.css", """
      @tailwind base;
      @tailwind components;
      @tailwind utilities;

      /* Your custom styles below */
      """)

      Mix.shell().info("✓ Created assets/app.css")
    end

    Mix.shell().info("\nTailwind CSS is ready! Run `mix sigil.tailwind watch` for development.")
  end

  defp ensure_installed do
    unless File.exists?(bin_path()) do
      Mix.shell().info("Tailwind not found, installing...")
      install()
    end
  end

  defp bin_path, do: @bin_path

  defp platform do
    os =
      case :os.type() do
        {:unix, :darwin} -> "macos"
        {:unix, _} -> "linux"
        {:win32, _} -> "windows"
      end

    arch =
      case List.to_string(:erlang.system_info(:system_architecture)) do
        "aarch64" <> _ -> "arm64"
        "arm" <> _ -> "arm64"
        "x86_64" <> _ -> "x64"
        _ -> "x64"
      end

    {os, arch}
  end
end
