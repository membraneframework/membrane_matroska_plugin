import Config

config :membrane_matroska_plugin,
  version: Membrane.Matroska.Plugin.Mixfile.project()[:version]

import_config "#{Mix.env()}.exs"
