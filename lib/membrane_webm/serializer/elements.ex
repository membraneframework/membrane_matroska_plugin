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

  def construct_tracks(tracks) do
    {:Tracks, Enum.map(tracks, &construct_track_entry/1)}
  end

  defp construct_track_entry({id, %{caps: %Opus{channels: channels}, track_number: track_number}}) do
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
       #  FIXME: The value of this Element SHOULD be kept the same when making a direct stream copy to another file.
       TrackUID: id,
       # The track number as used in the Block Header (using more than 127 tracks is not encouraged, though the design allows an unlimited number).
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry(
         {id, %{caps: %VP8{width: width, height: height}, track_number: track_number}}
       ) do
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

  # TODO: check out if relevant source of values: https://www.webmproject.org/docs/container/#TagBinary
  defp construct_track_entry(
         {id, %{caps: %VP9{width: width, height: height}, track_number: track_number}}
       ) do
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
           {:SeekID, Membrane.WebM.Parser.EBML.encode_element_id(name)}
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
        # TODO: add date when creating
        # DateUTC: :calendar.,
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
  # https://matroska.org/technical/tagging.html
  def construct_tags() do
    {:Tags,
     [
       Tag: [
         SimpleTag: [TagString: "00:00:27.201000000", TagName: "DURATION"],
         SimpleTag: [TagString: "Lavc58.134.100 libopus", TagName: "ENCODER"],
         Targets: []
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

  # Unless Matroska is used as a live stream, it SHOULD contain a Cues Element.
  # For each video track, each keyframe SHOULD be referenced by a CuePoint Element.
  # It is RECOMMENDED to not reference non-keyframes of video tracks in Cues unless it references a Cluster Element which contains a CodecState Element but no keyframes.
  # For each subtitle track present, each subtitle frame SHOULD be referenced by a CuePoint Element with a CueDuration Element.
  # References to audio tracks MAY be skipped in CuePoint Elements if a video track is present. When included the CuePoint Elements SHOULD reference audio keyframes at most once every 500 milliseconds.
  # If the referenced frame is not stored within the first SimpleBlock, or first BlockGroup within its Cluster Element, then the CueRelativePosition Element SHOULD be written to reference where in the Cluster the reference frame is stored.
  # If a CuePoint Element references Cluster Element that includes a CodecState Element, then that CuePoint Element MUST use a CueCodecState Element.
  # CuePoint Elements SHOULD be numerically sorted in storage order by the value of the CueTime Element.
  # https://www.matroska.org/technical/cues.html
  def construct_cues() do
    {:Cues,
     [
       CuePoint: [
         CueTrackPositions: [
           CueRelativePosition: 4,
           CueClusterPosition: 1_841_571,
           CueTrack: 1
         ],
         CueTime: 8540
       ],
       CuePoint: [
         CueTrackPositions: [
           CueRelativePosition: 656,
           CueClusterPosition: 818_091,
           CueTrack: 1
         ],
         CueTime: 6407
       ],
       CuePoint: [
         CueTrackPositions: [
           CueRelativePosition: 544,
           CueClusterPosition: 397_871,
           CueTrack: 1
         ],
         CueTime: 4274
       ],
       CuePoint: [
         CueTrackPositions: [
           CueRelativePosition: 4,
           CueClusterPosition: 186_395,
           CueTrack: 1
         ],
         CueTime: 2140
       ],
       CuePoint: [
         CueTrackPositions: [
           CueRelativePosition: 1402,
           CueClusterPosition: 1234,
           CueTrack: 1
         ],
         CueTime: 7
       ]
     ]}
  end
end