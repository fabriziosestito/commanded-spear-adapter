defmodule Commanded.EventStore.Adapters.Spear.Mixfile do
  use Mix.Project

  @version "0.2.1"

  def project do
    [
      app: :commanded_spear_adapter,
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
      {:commanded, "~> 1.4"},
      {:spear, "~> 1.0"},
      # Test & build tooling
      {:ex_doc, "~> 0.21", only: :dev},
      {:mox, "~> 1.0", only: :test},
      {:httpoison, "~> 2.0", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:excontainers, "~> 0.3.1", only: :test}
    ]
  end

  defp description do
    """
    EventStoreDB adapter for Commanded, based on Spear
    """
  end

  defp docs do
    [
      main: "Commanded.EventStore.Adapters.Spear",
      canonical: "http://hexdocs.pm/commanded_spear_adapter",
      source_ref: "v#{@version}",
      extras: [
        "CHANGELOG.md",
        "README.md": [filename: "readme", title: "README"]
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
      maintainers: ["Fabrizio Sestito"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/fabriziosestito/commanded-spear-adapter"
      }
    ]
  end
end
