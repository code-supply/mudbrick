defmodule Mudbrick.MixProject do
  use Mix.Project

  @scm_url "https://github.com/code-supply/mudbrick"

  def project do
    [
      app: :mudbrick,
      deps: deps(),
      description: "PDF-2.0 generator",
      dialyzer: dialyzer(),
      elixir: "~> 1.17",
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: "0.9.1",

      # Docs
      source_url: @scm_url,
      docs: [
        main: "Mudbrick",
        extras: ["README.md"],
        assets: %{
          "examples" => "examples"
        }
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.21", only: [:dev], runtime: false},
      {:ex_image_info, "~> 0.2"},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:nimble_parsec, "~> 1.4", runtime: false},
      {:opentype, "~> 0.5"},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:nimble_parsec]
    ]
  end

  defp package do
    [
      links: %{"GitHub" => @scm_url},
      licenses: ["MIT"]
    ]
  end
end
