# Membrane Matroska Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_matroska_plugin.svg)](https://hex.pm/packages/membrane_matroska_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_matroska_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_matroska_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_matroska_plugin)

Membrane plugin for muxing and demuxing files in the [Matroska](https://www.matroska.org/index.html) format.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

- Both muxer and demuxer support tracks encoded with VP8, VP9, H264 and Opus.
- Opus tracks with more than 2 channels are not supported.
- Demuxing of files containing [laced](https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-12.3) frames is not supported.
- Passing tag values is not supported

## Installation

The package can be installed by adding `membrane_matroska_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_matroska_plugin, "~> 0.1.0"}
  ]
end
```

## Usage

### `Membrane.Matroska.Muxer`
Matroska muxer requires a sink that can handle `Membrane.File.SeekEvent`, e.g. `Membrane.File.Sink`.
For an example of muxing streams to a regular matroska file, refer to [`examples/muxer_h264.exs`](examples/muxer_h264.exs).

To run the example, you can use the following command:
 ```bash
elixir examples/muxer_h264.exs
``` 

### `Membrane.Matroska.Demuxer`
For an example of demuxing streams, refer to [`examples/demuxer_h264.exs`](examples/demuxer_h264.exs). 

To run the example, use the following command:
```bash
elixir examples/demuxer_h264.exs
```

You can expect `demuxing_output` folder to appear and contain an audio file `2.ogg` and a video file `1.h264`.

## Copyright and License

Copyright 2022, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_matroska_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_matroska_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
