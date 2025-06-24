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
        plt_core_path: "_plts/core"
      ],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "readme",
        extras: [
          "README.md": [title: "Introduction"],
          "CHANGELOG.md": [title: "Changelog"],
          LICENSE: [title: "License"]
        ]
      ]
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
      {:evision, "~> 0.2"},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:gen_state_machine, "~> 3.0"},
      {:hnswlib, "~> 0.1"},
      {:mimic, "~> 1.12", only: :test},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:nimble_options, "~> 1.1"},
      {:nx, "~> 0.9"},
      {:qr_code, "~> 3.2"},
      {:qrex, "~> 0.1"},
      {:recode, "~> 0.6", only: :dev, runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:text_chunker, "~> 0.3"},
      {:xav, "~> 0.10"}
    ]
    |> maybe_add_exla()
    |> maybe_add_emlx()
  end

  ## Exla 0.9 is not building on MacOS, 0.10 is, but bumblebee requires 0.9
  defp maybe_add_exla(deps) do
    if System.get_env("USE_EXLA") do
      deps ++ [{:exla, ">= 0.0.0", only: [:dev, :test]}]
    else
      deps
    end
  end

  defp maybe_add_emlx(deps) do
    if System.get_env("USE_EMLX") do
      deps ++ [{:emlx, github: "elixir-nx/emlx", branch: "main", only: [:test, :dev]}]
    else
      deps
    end
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
