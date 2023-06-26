defmodule Membrane.Matroska.Plugin.Mixfile do
  use Mix.Project

  @version "0.3.0"
  @github_url "https://github.com/membraneframework/membrane_matroska_plugin"

  def project do
    [
      app: :membrane_matroska_plugin,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

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
      {:membrane_core, "~> 0.12.3"},
      {:membrane_matroska_format, "~> 0.1.0"},
      {:membrane_h264_format, "~> 0.5.0"},
      {:membrane_vp8_format, "~> 0.4.0"},
      {:membrane_vp9_format, "~> 0.4.0"},
      {:membrane_opus_format, "~> 0.3.0"},
      {:membrane_mp4_format, "~> 0.7.0"},
      {:membrane_common_c, "~> 0.15.0"},
      {:membrane_file_plugin, "~> 0.14.0", runtime: false},
      {:qex, "~> 0.5.1"},
      {:bimap, "~> 1.2"},
      # Test dependencies
      {:membrane_opus_plugin, "~> 0.17.0", only: :test, runtime: false},
      {:membrane_flv_plugin, "~> 0.7.0", only: :test},
      {:membrane_mp4_plugin, "~> 0.24.1", only: :test},
      {:membrane_ivf_plugin, "~> 0.6.0", only: :test, runtime: false},
      {:membrane_ogg_plugin,
       github: "membraneframework-labs/membrane_libogg_plugin",
       tag: "v0.3.0",
       only: :test,
       runtime: false},
      {:membrane_h264_ffmpeg_plugin, "~> 0.27.0", only: :test, runtime: false},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.17.1", only: :test, runtime: false},
      # Credo
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
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

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
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
