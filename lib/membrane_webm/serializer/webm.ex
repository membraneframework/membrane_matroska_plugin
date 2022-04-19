defmodule Membrane.WebM.Serializer.WebM do
  @moduledoc false

  # Module for constructing the top-level elements constituting a WebM file Segment
  # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-7

  alias Membrane.Buffer
  alias Membrane.WebM.Parser.Codecs
  alias Membrane.WebM.Serializer.Helper
  alias Membrane.WebM.Serializer.EBML
  alias Membrane.{Opus, VP8, VP9, MP4}

  @timestamp_scale Membrane.Time.millisecond()
  @version Membrane.WebM.Plugin.Mixfile.project()[:version]
  @seekhead_bytes 160

  @spec serialize_empty_segment() :: binary
  defp serialize_empty_segment() do
    element_id = EBML.encode_element_id(:Segment)
    element_data_size = <<0b11111111>>
    element_id <> element_data_size
  end

  @spec serialize_void(non_neg_integer, atom, function) :: binary
  def serialize_void(length, _element_name, schema) do
    # it's impossible to create void elements with size 2^(7*n) +- 1 because element_width is a vint which takes up n bytes
    # solution: create two void elements, each holding half the bytes (but not exactly half or you have the same problem)
    n = trunc(:math.log2(length - 1) / 7) + 1
    length = (length - n - 1) * 8
    element_data = <<0::size(length)>>

    EBML.serialize_element(element_data, :Void, schema)
  end

  @spec serialize_simple_block(tuple, atom, function) :: binary
  def serialize_simple_block(
        {timecode, %Buffer{payload: data}, track_number, _type} = block,
        _element_name,
        schema
      ) do
    # Opus flags
    #         value :: number_of_bits
    # keyframe:    1::0     # always 1    - no mention of keyframes in Opus RFC
    # reserved:    0::3     # always 000  - per Matroska RFC
    # invisible:   0::1     # always 0    - assumed
    # lacing:      0::2     # always 00   - no mention in Opus RFC
    # discardable: 0::1     # always 0    - assumed
    # Not sure about VP8/VP9
    timecode = <<timecode::integer-signed-big-size(16)>>
    keyframe = Codecs.keyframe_bit(block)
    header_flags = <<keyframe::1, 0::7>>

    element_data = EBML.encode_vint(track_number) <> timecode <> header_flags <> data

    EBML.serialize_element(element_data, :SimpleBlock, schema)
  end

  @spec serialize_cluster(binary, any, function) :: binary
  def serialize_cluster(content_bytes, _element_name, schema) do
    EBML.serialize_element(content_bytes, :Cluster, schema)
  end

  @spec serialize_webm_header(list, map) :: {non_neg_integer, binary}
  def serialize_webm_header(tracks, options) do
    ebml_header = Helper.serialize(construct_ebml_header())

    segment_header = serialize_empty_segment()

    info = construct_info(options)
    tracks = construct_tracks(tracks)
    # tags = construct_tags()
    seek_head = construct_seek_head([info, tracks])
    void = construct_void(seek_head)

    webm_header_elements = Helper.serialize([seek_head, void, info, tracks])

    segment_size = byte_size(webm_header_elements)

    {segment_size, ebml_header <> segment_header <> webm_header_elements}
  end

  @spec construct_ebml_header() :: {atom, list}
  defp construct_ebml_header() do
    {
      :EBML,
      [
        DocTypeReadVersion: 2,
        DocTypeVersion: 4,
        # DocType: "webm",
        DocType: "matroska",
        EBMLMaxSizeLength: 8,
        EBMLMaxIDLength: 4,
        EBMLReadVersion: 1,
        EBMLVersion: 1
      ]
    }
  end

  @spec construct_tracks(list({non_neg_integer, map})) :: {atom, list}
  defp construct_tracks(tracks) do
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
       FlagLacing: 0,
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
       FlagLacing: 0,
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
       FlagLacing: 0,
       TrackUID: id,
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry(
         {id,
          %{
            caps: %MP4.Payload{
              content: %Membrane.MP4.Payload.AVC1{
                avcc: codec_private
              },
              width: width,
              height: height
            },
            track_number: track_number
          }}
       ) do
    {:TrackEntry,
     [
       CodecPrivate: codec_private,
       Video: [
         PixelHeight: width,
         PixelWidth: height
       ],
       # 1 for video
       TrackType: 1,
       CodecID: "V_MPEG4/ISO/AVC",
       FlagLacing: 0,
       TrackUID: id,
       TrackNumber: track_number
     ]}
  end

  # explanation of segment position:
  # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-segment-position
  @spec construct_seek_head(list({atom, list})) :: {atom, list}
  defp construct_seek_head(elements) do
    seeks =
      elements
      |> Enum.reduce({[], @seekhead_bytes + 1}, fn element, acc ->
        {name, data} = element
        {results, offset} = acc
        new_acc = [{name, offset} | results]
        new_offset = offset + byte_size(Helper.serialize({name, data}))
        {new_acc, new_offset}
      end)
      |> elem(0)
      |> Enum.map(fn {name, offset} ->
        {:Seek,
         [
           {:SeekPosition, offset},
           {:SeekID, EBML.encode_element_id(name)}
         ]}
      end)

    {:SeekHead, seeks}
  end

  @spec construct_void({atom, list}) :: {atom, non_neg_integer}
  defp construct_void(seek_head) do
    void_width = @seekhead_bytes - byte_size(Helper.serialize(seek_head))
    {:Void, void_width}
  end

  # this element MUST exist - because of TimestampScale
  @spec construct_info(map) :: {atom, list}
  defp construct_info(options) do
    info = [
      # FIXME: off by last frame duration
      Duration: options.duration * @timestamp_scale,
      WritingApp: "membrane_webm_plugin-#{@version}",
      MuxingApp: "membrane_webm_plugin-#{@version}",
      Title: options.title,
      DateUTC:
        :calendar.datetime_to_gregorian_seconds(:calendar.now_to_datetime(:erlang.timestamp())),
      TimestampScale: @timestamp_scale
    ]

    if options.add_date? do
      {:Info, info}
    else
      {:Info, Keyword.drop(info, [:DateUTC])}
    end
  end

  # TODO: add callback or option to supply tag values
  # https://matroska.org/technical/tagging.html
end
