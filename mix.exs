defmodule Commanded.EventStore.Adapters.Extreme.Mixfile do
  use Mix.Project

  @version "1.1.0"

  def project do
    [
      app: :commanded_extreme_adapter,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      description: description(),
      docs: docs(),
      package: package(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test),
    do: [
      "deps/commanded/test/event_store",
      "deps/commanded/test/support",
      "lib",
      "test/support"
    ]

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:commanded, "~> 1.3"},
      {:extreme, "~> 0.13"},
      {:spear, "~> 1.0"},
      # Optional dependencies
      {:jason, "~> 1.2", optional: true},

      # Test & build tooling
      {:ex_doc, "~> 0.21", only: :dev},
      {:mox, "~> 1.0", only: :test},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    Extreme event store adapter for Commanded
    """
  end

  defp docs do
    [
      main: "Commanded.EventStore.Adapters.Extreme",
      canonical: "http://hexdocs.pm/commanded_extreme_adapter",
      source_ref: "v#{@version}",
      extra_section: "GUIDES",
      extras: [
        "CHANGELOG.md",
        "guides/Getting Started.md": [filename: "getting-started", title: "Extreme adapter"],
        "guides/Testing.md": [title: "Testing"]
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      maintainers: ["Ben Smith"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/commanded/commanded-extreme-adapter"
      }
    ]
  end
end
