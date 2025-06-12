defmodule ExMemvid.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_memvid,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:bumblebee, "~> 0.6"},
      {:briefly, "~> 0.5", only: :test},
      {:evision, "~> 0.2"},
      {:emlx, github: "elixir-nx/emlx", branch: "main", only: [:test, :dev]},
      {:hnswlib, "~> 0.1"},
      {:mimic, "~> 1.12", only: :test},
      {:nimble_options, "~> 1.1"},
      {:nx, "~> 0.9"},
      {:qr_code, "~> 3.2"},
      {:qrex, "~> 0.1"},
      {:text_chunker, "~> 0.3"},
      {:xav, "~> 0.10"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
