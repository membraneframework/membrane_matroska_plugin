defmodule Membrane.Matroska.Plugin.Mixfile do
  use Mix.Project

  @version "0.1.2"
  @github_url "https://github.com/membraneframework/membrane_matroska_plugin"

  def project do
    [
      app: :membrane_matroska_plugin,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "Matroska Plugin for Membrane Multimedia Framework",
      package: package(),

      # docs
      name: "Membrane Matroska plugin",
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
      {:membrane_core, "~> 0.10.0"},
      {:membrane_matroska_format, "~> 0.1"},
      {:membrane_h264_format, "~> 0.3"},
      {:membrane_vp8_format, "~> 0.4.0"},
      {:membrane_vp9_format, "~> 0.4.0"},
      {:membrane_opus_format, "~> 0.3.0"},
      {:membrane_mp4_format, "~> 0.7.0"},
      {:membrane_common_c, "~> 0.13.0"},
      {:membrane_file_plugin, "~> 0.12.0", runtime: false},
      {:qex, "~> 0.5.1"},
      {:bimap, "~> 1.2"},
      # Test dependencies
      {:membrane_opus_plugin, "~> 0.15.0", only: :test, runtime: false},
      {:membrane_flv_plugin, "~> 0.2.0", only: :test, runtime: false},
      {:membrane_mp4_plugin, "~> 0.15.0", only: :test, runtime: false},
      {:membrane_ivf_plugin, "~> 0.4.1", only: :test, runtime: false},
      {:membrane_ogg_plugin,
       github: "membraneframework/membrane_ogg_plugin", only: :test, runtime: false},
      {:membrane_h264_ffmpeg_plugin, "~> 0.21.5", only: :test, runtime: false},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.15.0", only: :test, runtime: false},
      # Credo
      {:ex_doc, "~> 0.26", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
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
      nest_modules_by_prefix: [Membrane.Matroska]
    ]
  end
end
