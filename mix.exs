defmodule Membrane.WebM.Plugin.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/membraneframework/membrane_webm_plugin"

  def project do
    [
      app: :membrane_webm_plugin,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "WebM Plugin for Membrane Multimedia Framework",
      package: package(),

      # docs
      name: "Membrane WebM plugin",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 0.9.0", override: true},
      {:bimap, "~> 1.2"},
      {:membrane_opus_plugin, "~> 0.8.0"},
      {:membrane_ivf_plugin,
       github: "membraneframework/membrane_ivf_plugin",
       branch: "change-caps",
       only: :test,
       runtime: false},
      {:membrane_vp8_format,
       github: "membraneframework/membrane_vp8_format", branch: "add-stream-params"},
      {:membrane_vp9_format,
       github: "membraneframework/membrane_vp9_format", branch: "add-stream-params"},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.10.0", only: :test, runtime: false},
      {:membrane_file_plugin, "~> 0.8.0", runtime: false},
      {:membrane_ogg_plugin,
       github: "membraneframework/membrane_ogg_plugin", only: :test, runtime: false},
      {:membrane_h264_ffmpeg_plugin, "~> 0.18.0"},
      {:membrane_mp4_plugin, "~> 0.13.0"},
      {:membrane_common_c, "~> 0.11.0", override: true},
      {:ex_doc, "~> 0.26", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:qex, "~> 0.5.1"}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.WebM]
    ]
  end
end
