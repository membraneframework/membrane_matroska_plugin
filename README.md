# Membrane WebM Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_webm_plugin.svg)](https://hex.pm/packages/membrane_webm_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_webm_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_webm_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_webm_plugin)

Membrane plugin for muxing and demuxing files in the [WebM](https://www.webmproject.org/) format

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

- WebM files can contain tracks encoded with VP8, VP9 and Opus.
- Opus tracks with more than 2 channels are not supported.
- Demuxing of files containing [laced](https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-12.3) frames is not supported.

## Installation

The package can be installed by adding `membrane_webm_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_webm_plugin, "~> 0.1.0"}
  ]
end
```

## Usage

For usage examples please refer to our tests.

## Copyright and License

Copyright 2022, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webm_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webm_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
