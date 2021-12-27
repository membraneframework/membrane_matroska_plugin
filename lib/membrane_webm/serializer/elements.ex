defmodule Membrane.WebM.Serializer.Elements do
  @moduledoc """
  Module for constructing the top-level elements constituting a WebM file
  """
  alias Membrane.WebM.Parser.Codecs

  alias Membrane.WebM.Serializer
  alias Membrane.{Opus, VP8, VP9}

  @timestamp_scale Membrane.Time.millisecond()
  @version Membrane.WebM.Plugin.Mixfile.project()[:version]
  @seekhead_bytes 160

  def construct_ebml_header() do
    {
      :EBML,
      [
        DocTypeReadVersion: 2,
        DocTypeVersion: 4,
        DocType: "webm",
        EBMLMaxSizeLength: 8,
        EBMLMaxIDLength: 4,
        EBMLReadVersion: 1,
        EBMLVersion: 1
      ]
    }
  end

  def construct_tracks(pads, tracks) do
    {:Tracks, Enum.map(Enum.zip(pads, tracks), &construct_track_entry/1)}
  end

  defp construct_track_entry({{id, %Opus{channels: channels}}, {_id, track_number}}) do
    {:TrackEntry,
     [
       # CodecPrivate is identical to the ogg ID header specified here:
       # https://datatracker.ietf.org/doc/html/rfc7845#section-5.1
       # it can be ignored for opus streams with 1 or 2 channels but must be used to correctly play higher-channel-count streams
       CodecPrivate: Codecs.construct_opus_id_header(channels),
       Audio: [
         # I guess this is hardcoded. Hard to tell from RFC
         BitDepth: 32,
         # Possible frequencies: 8, 12, 16, 24, 48 kHz
         # https://datatracker.ietf.org/doc/html/rfc6716#section-2
         SamplingFrequency: 2.4e4,
         Channels: channels
       ],
       # Tracktype: 2 for `audio`
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-tracktype-values
       TrackType: 2,
       # FIXME: I don't understand SeekPreRoll: copying over from ffmpeg webm for now
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-seekpreroll-element
       # https://opus-codec.org/docs/opusfile_api-0.5/group__stream__seeking.html
       SeekPreRoll: 80_000_000,
       # FIXME: How do I determine CodecDelay? copying over from ffmpeg webm for now
       # https://github.com/GStreamer/gstreamer/blob/5e3bf0fff7205390de56747f950f726b456fc65d/subprojects/gst-plugins-good/gst/matroska/matroska-mux.c#L1898
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-8.1.4.1.28-1.14
       # https://datatracker.ietf.org/doc/html/rfc6716#section-2
       # The LP layer is based on the SILK codec [SILK].  It supports NB, MB,
       # or WB audio and frame sizes from 10 ms to 60 ms, and requires an
       # additional 5 ms look-ahead for noise shaping estimation.  A small
       # additional delay (up to 1.5 ms) may be required for sampling rate
       # conversion.
       # gstreamer has codecdelay set to 0
       CodecDelay: 3_250_000,
       CodecID: "A_OPUS",
       CodecName: "Opus Audio Codec",
       # I didn't find information about lacing in the Opus RFC so I assume it's always unlaced
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-8.1.4.1.12
       FlagLacing: 0,
       #  TrackUID is an 8 byte number that MUST NOT be 0
       #  FIXME: :rand.uniform((1 <<< 56) - 2) works for now but :rand.uniform((1 <<< 64) - 2) should be used instead
       # Probably a problem with Membrane.WebM.EBML encoding of 8-byte numbers
       TrackUID: id,
       # The track number as used in the Block Header (using more than 127 tracks is not encouraged, though the design allows an unlimited number).
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry({{id, %VP8{width: width, height: height}}, {_id, track_number}}) do
    {:TrackEntry,
     [
       Video: [
         Colour: [
           # :half,
           ChromaSitingVert: 2,
           # :left_coallocated
           ChromaSitingHorz: 1
         ],
         # :progressive, - no interlacing
         FlagInterlaced: 2,
         PixelHeight: width,
         PixelWidth: height
       ],
       DefaultDuration: 16_666_666,
       # :video,
       TrackType: 1,
       # :vp8,
       CodecID: "V_VP8",
       Language: "und",
       FlagLacing: 0,
       TrackUID: id,
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry({{id, %VP9{width: width, height: height}}, {_id, track_number}}) do
    {:TrackEntry,
     [
       Video: [
         Colour: [
           # TODO:
           # VP9 provides the option for the 2 chroma planes (called U and V) to be subsampled in either the horizontal or
           # vertical direction (or both, or neither).
           # In profiles 0 and 2, only 4:2:0 format is allowed, which means that chroma is subsampled
           # page 22 https://storage.googleapis.com/downloads.webmproject.org/docs/vp9/vp9-bitstream-specification-v0.6-20160331-draft.pdf
           # :half, - 2
           ChromaSitingVert: 0,
           # :left_coallocated - 1
           ChromaSitingHorz: 0
         ],
         # :progressive, - no interlacing
         FlagInterlaced: 2,
         PixelHeight: width,
         PixelWidth: height
       ],
       # TODO: where did this come from?
       DefaultDuration: 16_666_666,
       # :video,
       TrackType: 1,
       # :vp8,
       CodecID: "V_VP9",
       Language: "und",
       FlagLacing: 0,
       TrackUID: id,
       TrackNumber: track_number
     ]}
  end

  @doc """
  segment position:
  https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-segment-position
  """
  def construct_seek_head(elements) do
    seeks =
      elements
      |> Enum.reduce({[], @seekhead_bytes + 1}, fn element, acc ->
        {name, data} = element
        {results, offset} = acc
        new_acc = [{name, offset} | results]
        new_offset = offset + byte_size(Serializer.serialize({name, data}))
        {new_acc, new_offset}
      end)
      |> elem(0)
      |> Enum.map(fn {name, offset} ->
        {:Seek,
         [
           {:SeekPosition, offset},
           {:SeekID, Base.decode16!(Membrane.WebM.Schema.name_to_element_id(name))}
         ]}
      end)

    {:SeekHead, seeks}
  end

  def construct_void(seek_head) do
    void_width = @seekhead_bytes - byte_size(Serializer.serialize(seek_head))
    {:Void, void_width}
  end

  # this element MUST exist - because of TimestampScale
  def construct_info() do
    {
      :Info,
      [
        # TODO: calculate Duration dynamically
        Duration: 27201.0,
        WritingApp: "membrane_webm_plugin-#{@version}",
        MuxingApp: "membrane_webm_plugin-#{@version}",
        # FIXME: how should the title field be populated?
        Title: "Membrane WebM file",
        # hardcoded per RFC
        # note that this requires all incoming buffer `pts` timestamp to be expressed in Membrane.Time (i.e. in nanoseconds)
        # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-timestampscale-element
        # FIXME: FIXME: FIXME:
        # Matroska's `TimecodeScale` changed it's name to `TimestampScale`
        # See https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-13
        # Yet the WebM documentation appears to still be using `TimecodeScale`
        # See https://www.webmproject.org/docs/container/#TimecodeScale
        TimestampScale: @timestamp_scale
      ]
    }
  end

  # TODO: There's no way of extracting this metadata from raw streams so a callback or option should be implemented to supply these values
  # Though they do not appear essential for achieving playable files (possible exception: VLC)
  def construct_tags() do
    {:Tags,
     [
       Tag: [
         SimpleTag: [TagString: "00:00:27.201000000", TagName: "DURATION"],
         SimpleTag: [TagString: "Lavc58.134.100 libopus", TagName: "ENCODER"],
         Targets: [TagTrackUID: 6_979_663_406_594_824_908]
       ],
       Tag: [
         SimpleTag: [TagString: "Lavf58.76.100", TagName: "ENCODER"],
         SimpleTag: [TagString: "Kevin MacLeod", TagName: "ARTIST"],
         SimpleTag: [TagString: "YouTube Audio Library", TagName: "ALBUM"],
         SimpleTag: [TagString: "Cinematic", TagName: "GENRE"],
         Targets: []
       ]
     ]}
  end

  # https://www.matroska.org/technical/cues.html
  def construct_cues() do
    nil
  end
end
