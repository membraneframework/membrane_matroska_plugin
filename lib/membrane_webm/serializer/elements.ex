defmodule Membrane.WebM.Serializer.Elements do
  @moduledoc false

  # Module for constructing the top-level elements constituting a WebM file Segment
  # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-7

  alias Membrane.WebM.Parser.Codecs
  alias Membrane.WebM.Serializer
  alias Membrane.{Opus, VP8, VP9}

  @timestamp_scale Membrane.Time.millisecond()
  @version Membrane.WebM.Plugin.Mixfile.project()[:version]
  @seekhead_bytes 160

  @spec construct_ebml_header() :: {atom, list}
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

  @spec construct_tracks(list({non_neg_integer, map})) :: {atom, list}
  def construct_tracks(tracks) do
    {:Tracks, Enum.map(tracks, &construct_track_entry/1)}
  end

  defp construct_track_entry({id, %{caps: %Opus{channels: channels}, track_number: track_number}}) do
    {:TrackEntry,
     [
       # this field will become important if membrane expands support for opus to more than 2 channels
       CodecPrivate: Codecs.construct_opus_id_header(channels),
       Audio: [
         Channels: channels
       ],
       # 2 for audio
       TrackType: 2,
       CodecID: "A_OPUS",
       TrackUID: id,
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry(
         {id, %{caps: %VP8{width: width, height: height}, track_number: track_number}}
       ) do
    {:TrackEntry,
     [
       Video: [
         PixelHeight: width,
         PixelWidth: height
       ],
       # 1 for video
       TrackType: 1,
       CodecID: "V_VP8",
       TrackUID: id,
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry(
         {id, %{caps: %VP9{width: width, height: height}, track_number: track_number}}
       ) do
    {:TrackEntry,
     [
       Video: [
         PixelHeight: width,
         PixelWidth: height
       ],
      # 1 for video
      TrackType: 1,
      CodecID: "V_VP9",
      TrackUID: id,
      TrackNumber: track_number
     ]}
  end

  # explanation of segment position:
  # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-segment-position
  # FIXME: clean up after fixing serializer
  @spec construct_seek_head(list({atom, list})) :: {atom, list}
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
           {:SeekID, Membrane.WebM.Serializer.EBML.encode_element_id(name)}
         ]}
      end)

    {:SeekHead, seeks}
  end

  @spec construct_void({atom, list}) :: {atom, non_neg_integer}
  def construct_void(seek_head) do
    void_width = @seekhead_bytes - byte_size(Serializer.serialize(seek_head))
    {:Void, void_width}
  end

  # this element MUST exist - because of TimestampScale
  @spec construct_info() :: {atom, list}
  def construct_info() do
    {
      :Info,
      [
        # TODO: calculate Duration dynamically
        Duration: 0,
        WritingApp: "membrane_webm_plugin-#{@version}",
        MuxingApp: "membrane_webm_plugin-#{@version}",
        # TODO: add options to populate title fields
        Title: "Membrane WebM file",
        # TODO: add current date: breaks testing reproducibility:
        # DateUTC:
        #   :calendar.datetime_to_gregorian_seconds(:calendar.now_to_datetime(:erlang.timestamp())),
        # hardcoded per RFC
        # note that this requires all incoming buffer `dts` timestamps to be expressed in Membrane.Time (i.e. in nanoseconds)
        # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-timestampscale-element
        TimestampScale: @timestamp_scale
      ]
    }
  end

  # TODO: add callback or option to supply tag values
  # https://matroska.org/technical/tagging.html
end
