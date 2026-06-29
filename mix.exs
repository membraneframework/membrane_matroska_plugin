defmodule Membrane.Matroska.Plugin.Mixfile do
  use Mix.Project

  @version "0.6.3"
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
      docs: docs(),
      aliases: [docs: ["docs", &append_llms_links/1]]
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
      {:membrane_core, "~> 1.0"},
      {:membrane_matroska_format, "~> 0.1.0"},
      {:membrane_h264_format, "~> 0.6.1"},
      {:membrane_vp8_format, "~> 0.5.0"},
      {:membrane_vp9_format, "~> 0.5.0"},
      {:membrane_opus_format, "~> 0.3.0"},
      {:membrane_common_c, "~> 0.16.0"},
      {:membrane_file_plugin, "~> 0.17.0", runtime: false},
      {:qex, "~> 0.5.1"},
      {:bimap, "~> 1.2"},
      # Test dependencies
      {:membrane_opus_plugin, "~> 0.19.0", only: :test, runtime: false},
      {:membrane_flv_plugin, "~> 0.11.0", only: :test, runtime: false},
      {:membrane_ivf_plugin, "~> 0.7.0", only: :test, runtime: false},
      {:membrane_ogg_plugin,
       github: "membraneframework-labs/membrane_libogg_plugin",
       tag: "v0.4.0",
       only: :test,
       runtime: false},
      {:membrane_h264_plugin, "~> 0.9.0", only: :test, runtime: false},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.19.0", only: :test, runtime: false},
      # Credo
      {:ex_doc, ">= 0.40.0", only: :dev, runtime: false},
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
      File.mkdir_p!(Path.join([__DIR__, "priv", "plts"]))
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

  defp append_llms_links(_args) do
    output_dir = docs()[:output] || "doc"
    path = Path.join(output_dir, "llms.txt")

    if File.exists?(path) do
      existing = File.read!(path)

      footer = """


      ## See Also

      - [Membrane Framework AI Skill](https://hexdocs.pm/membrane_core/skill.md)
      - [Membrane Core](https://hexdocs.pm/membrane_core/llms.txt)
      """

      File.write!(path, String.trim_trailing(existing) <> footer)
    else
      IO.warn("#{path} not found — llms.txt was not generated, check your ex_doc configuration")
    end
  end
end
