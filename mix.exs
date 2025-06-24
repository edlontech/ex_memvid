defmodule ExMemvid.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_memvid,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:emlx, github: "elixir-nx/emlx", branch: "main", only: [:test, :dev]},
      {:evision, "~> 0.2"},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:exla, "~> 0.10", only: [:dev, :test]},
      {:gen_state_machine, "~> 3.0"},
      {:hnswlib, "~> 0.1"},
      {:mimic, "~> 1.12", only: :test},
      {:nimble_options, "~> 1.1"},
      {:nx, "~> 0.9"},
      {:qr_code, "~> 3.2"},
      {:qrex, "~> 0.1"},
      {:recode, "~> 0.6", only: :dev, runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:text_chunker, "~> 0.3"},
      {:xav, "~> 0.10"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "A Elixir library for encoding and decoding text data into video frames using QR codes, with efficient retrieval capabilities."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/edlontech/ex_memvid"},
      sponsor: "ycastor.eth"
    ]
  end
end
