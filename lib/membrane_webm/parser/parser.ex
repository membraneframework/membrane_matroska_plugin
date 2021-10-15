defmodule Membrane.WebM.Parser do
end

# nice bitmap library: https://gitlab.com/Project-FiFo/DalmatinerDB/bitmap https://github.com/gausby/bit_field_set

defmodule Membrane.WebM.Parser.Vint do
  @moduledoc """
  VINT - variable length integer

  Numbers are encoded as VINTs in EBML.
  A VINT consists of three parts:
  - VINT_WIDTH - the number N of leading `0` bits in the first byte of the VINT signifies how many bytes the VINT takes up in total: N+1; having no leading `0` bits is also allowed in which case the VINT takes 1 byte
  - VINT_MARKER - the `1` bit immediately following the VINT_WIDTH `0` bits
  - VINT_DATA - the 7*N bits following the VINT_MARKER
  """

  use Bitwise

  alias Membrane.WebM.Schema.Structs.Vint

  # not sure if thte first `8` shouldn't be -inf or something. are all 0's legal?
  @vint_width [
    8,8,7,7,6,6,6,6,5,5,5,5,5,5,5,5,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
    3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]

  # bitwise AND of VINT with data_mask[VINT_WIDTH] yealds VINT_DATA
  @data_mask %{
    1 => 18446744073709551743,
    2 => 18446744073709567999,
    3 => 18446744073711648767,
    4 => 18446744073977987071,
    5 => 18446744108069289983,
    6 => 18446748471756062719,
    7 => 18447307023662972927,
    8 => 18518801667747479551
  }

  # the length of a VINT is 1-8 bytes
  def parse(<<bytes::binary-size(8), _::binary>> = all_bytes) do
    first_byte =
      binary_part(bytes, 0, 1)
      |> :binary.decode_unsigned
    # the first byte suffices to determine the vint length
    vint_width = Enum.at(@vint_width, first_byte)
    <<bytes::binary-size(vint_width), rest_bytes::binary>> = all_bytes

    # TODO validation: VINT_DATA must not be set to all 0
    # TODO validation: the values:
    #   1 1111111
    #   0 1 11111111111111
    # are reserver to mean `unknown`

    <<vint::integer-size(vint_width)-unit(8)>> = bytes
    vint_data = vint &&& @data_mask[vint_width]
    # the hex representation of the whole VINT including WIDTH, MARKER and DATA:
    element_id = Integer.to_string(vint, 16)

    %{vint: %Vint{
        vint: vint,
        vint_width: vint_width,
        vint_data: vint_data,
        element_id: element_id},
      rest: rest_bytes
    }
  end

  # in case of binary `bytes` is shorter than 8 octets
  def parse(bytes) do
  first_byte =
      binary_part(bytes, 0, 1)
      |> :binary.decode_unsigned
    # the first byte suffices to determine the vint length
    vint_width = Enum.at(@vint_width, first_byte)
    <<bytes::binary-size(vint_width), rest_bytes::binary>> = bytes

    # TODO validation: VINT_DATA must not be set to all 0
    # TODO validation: the values:
    #   1 1111111
    #   0 1 11111111111111
    # are reserver to mean `unknown`

    <<vint::integer-size(vint_width)-unit(8)>> = bytes
    vint_data = vint &&& @data_mask[vint_width]
    # the hex representation of the whole VINT including WIDTH, MARKER and DATA:
    element_id = Integer.to_string(vint, 16)

    %{vint: %Vint{
        vint: vint,
        vint_width: vint_width,
        vint_data: vint_data,
        element_id: element_id},
      rest: rest_bytes
    }
  end
end

defmodule Membrane.WebM.Parser.Element do
  @moduledoc """
  An EBML element consists of
  - element_id - a VINT
  - element_data_size - a VINT
  - element_data - which is another element
    - signed integer element
    - unsigned integer element
    - float element
    - string element
    - UTF-8 element
    - date element
    - binary element
      contents should not be interpreted by parser
    - master element
      A Master Element declare a length in octets from zero to VINTMAX or be of unknown
      length. See Section 6 for rules that apply to elements of unknown length.
      The Master Element contains zero or more other elements. EBML Elements contained within a
      Master Element have the EBMLParentPath of their Element Path equal to the
      EBMLFullPath of the Master Element Element Path (see Section 11.1.6.2). Element Data stored
      within Master Elements only consist of EBML Elements and contain any
      data that is not part of an EBML Element. The EBML Schema identifies what Element IDs are
      valid within the Master Elements for that version of the EBML Document Type. Any data
      contained within a Master Element that is not part of a Child Element be ignored.

  TODO element_id is the only type of VINT for which it is illegal to take up more space than is necessary i.e.
    1 0000001 is legal
    0 1 00000000000001 is illegal because a shorter encoding of VINT_DATA is available
    (it fits in 1 byte but 2 are used)

  element_data_size can be unknown!
    https://www.rfc-editor.org/rfc/rfc8794.pdf section 6.2
    craaayyyzy


  """

  alias Membrane.WebM.Parser.Vint

  def parse_chunk(bytes, acc) do
    %{element: element, rest: bytes} = parse_element(bytes)
    acc = [element | acc]
    if bytes == "" do
      acc
    else
      parse_chunk(bytes, acc)
    end
  end

  def parse(bytes, :master, _name) do
    if byte_size(bytes) == 0 do
      []
    else
      parse_chunk(bytes, [])
    end
  end

  def parse(bytes, :uint, _name) do
    :binary.decode_unsigned(bytes)
  end

  def parse(bytes, :float, _name) do
    bytes
  end

  def parse(bytes, :binary, :SimpleBlock) do
    # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4

    # track_number is a vint with size 1 or 2 bytes
    %{vint: track_number_vint, rest: bytes} = Vint.parse(bytes)
    << timecode::integer-signed-size(16), flags::bitstring-size(8), data::binary>> = bytes
    <<keyframe::1, reserved::3, invisible::1, lacing::2, discardable::1>> = flags

    if reserved != 0 do
      IO.puts "SimpleBlock reserved bits in header flag should all be 0 but they are #{reserved}"
    end

    lacing = case lacing do
      0b00 -> :no_lacing
      0b01 -> :Xiph_lacing
      0b11 -> :EBML_lacing
      0b10 -> :fixed_size_lacing
    end

    # TODO deal with lacing != 00 https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#laced-data-1

    %{
      track_number: track_number_vint.vint_data,
      timecode: timecode,
      header_flags: %{
          keyframe: keyframe==1,
          reserved: reserved,
          invisible: invisible==1,
          lacing: lacing,
          discardable: discardable==1
      },
      data: data
    }
  end

  def parse(bytes, :binary, _name) do
    bytes
    # Base.encode16(bytes)
  end

  def parse(bytes, :string, _name) do
    Enum.join(for <<c::utf8 <- bytes>>, do: <<c::utf8>>)
  end

  def parse(bytes, :utf_8, _name) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn(codepoint, result) ->
                     << parsed :: 8>> = codepoint
                     if parsed == 0, do: result, else: result <> <<parsed>>
                   end)
  end

  def parse(_bytes, :void, _name) do
    nil # Base.encode16(bytes)
  end

  def parse(bytes, :unknown, _name) do
    Base.encode16(bytes)
  end

  def parse(bytes, :ignore, _name) do
    Base.encode16(bytes)
  end

  def parse_element(bytes) do
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    id = vint.element_id
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    data_size = vint.vint_data
    # TODO: deal with unknown data size
    {name, type} = classify_element(id)

    if type == :unknown do
      IO.puts "unknown element ID: #{id}"
    end

    with %{bytes: data, rest: bytes} <- trim_bytes(bytes, data_size) do
      element = %{
        id: id,
        data_size: data_size,
        name: name,
        data: parse(data, type, name),
        type: type
      }

      %{element: element, rest: bytes}
    end
  end

  def trim_bytes(bytes, how_many) do
    <<bytes::binary-size(how_many), rest::binary>> = bytes
    %{bytes: bytes, rest: rest}
  end

  def classify_element(element_id) do
    case element_id do

      ### EBML elements:

      "1A45DFA3" -> {:EBML, :master}
      "4286" -> {:EBMLVersion, :uint}
      "42F7" -> {:EBMLReadVersion, :uint}
      "42F2" -> {:EBMLMaxIDLength, :uint}
      "42F3" -> {:EBMLMaxSizeLength, :uint}
      "4282" -> {:DocType, :string}
      "4287" -> {:DocTypeVersion, :uint}
      "4285" -> {:DocTypeReadVersion, :uint}
      "4281" -> {:DocTypeExtension, :master}
      "4283" -> {:DocTypeExtensionName, :string}
      "4284" -> {:DocTypeExtensionVersion, :uint}
      "BF" -> {:CRC_32, :crc_32} # shouldn't occur in a mkv or webm file
      "EC" -> {:Void, :void}

      ### Matroska elements:

      "18538067" -> {:Segment, :master}
        # \Segment

        "1C53BB6B" -> {:Cues, :master}
          # \Segment\Cues
          "BB" -> {:CuePoint, :master}
            # \Segment\Cues\CuePoint
            "B3" -> {:CueTime, :uint}
            "B7" -> {:CueTrackPositions, :master}
              # \Segment\Cues\CuePoint\CueTrackPositions
              "F0" -> {:CueRelativePosition, :uint}
              "F1" -> {:CueClusterPosition, :uint}
              "F7" -> {:CueTrack, :uint}

        # data is stored here:
        "1F43B675" -> {:Cluster, :master}
        # \Segment\Cluster
          "A3" -> {:SimpleBlock, :binary}
          "E7" -> {:Timecode, :uint}

        "1254C367" -> {:Tags, :master}
        # \Segment\Tags
          "7373" -> {:Tag, :master}
          # \Segment\Tags\Tag
          "63C0" -> {:Targets, :master}
            # \Segment\Tags\Tag\Targets
            "63C5" -> {:TagTractUID, :uint}
          "67C8" -> {:SimpleTag, :master}
            # \Segment\Tags\Tag\SimpleTag
            "4487" -> {:TagString, :utf_8}
            "45A3" -> {:TagName, :utf_8}

        "1654AE6B" -> {:Tracks, :master}
          # \Segment\Tracks
          "AE" -> {:TrackEntry, :master}
            # \Segment\Tracks\TrackEntry
            "D7" -> {:TrackNumber, :uint}
            "73C5" -> {:TrackUID, :uint}
            "9C" -> {:FlagLacing, :uint}
            "22B59C" -> {:Language, :string}
            "86" -> {:CodecID, :string}
            "56AA" -> {:CodecDelay, :uint}
            "56BB" -> {:SeekPreRoll, :uint}
            "83" -> {:TrackType, :uint}
            "63A2" -> {:CodecPrivate, :binary}
            "E1" -> {:Audio, :master}
              # \Segment\Tracks\TrackEntry\Audio
              "9F" -> {:Channels, :uint}
              "B5" -> {:SamplingFrequency, :float}
              "6264" -> {:BitDepth, :uint}

        "1549A966" -> {:Info, :master}
          # \Segment\Info
          "2AD7B1" -> {:TimecodeScale, :uint}
          "7BA9" -> {:Title, :utf_8}
          "4D80" -> {:MuxingApp, :utf_8}
          "5741" -> {:WritingApp, :utf_8}
          "4489" -> {:Duration, :float}

        "114D9B74" -> {:SeekHead, :master}
          # \Segment\SeekHead
          "4DBB" -> {:Seek, :master}
            # \Segment\SeekHead\Seek
            "53AC" -> {:SeekPosition, :uint}
            "53AB" -> {:SeekID, :binary}

      _ -> {:UnknownName, :unknown}
    end
  end
end





        # if element_data_size != 4 do
        #   raise "CRC-32 element with wrong length (should be 4): #{element}"
        # else
        #   %{element | type: :CRC_32}
        # end
