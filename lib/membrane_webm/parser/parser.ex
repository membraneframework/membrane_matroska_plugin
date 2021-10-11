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



    vint = %{vint: %Vint{
        vint: vint,
        vint_width: vint_width,
        vint_data: vint_data,
        element_id: element_id},
      rest: rest_bytes}

    # IO.inspect(vint)

    vint
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



    vint = %{vint: %Vint{
        vint: vint,
        vint_width: vint_width,
        vint_data: vint_data,
        element_id: element_id},
      rest: rest_bytes}

    # IO.inspect(vint)

    vint
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
  alias Membrane.WebM.Schema.Structs.HeaderElement

  # def parse_ebml_file(<<id_bytes::binary-size(8)>> = bytes) do
  #   id = Vint.parse(id_bytes).element_id
  #   if classify(id) == :EBML do
  #     parse(type, bytes)
  #   else
  #     "Not an EBML file sorry"
  #   end
  # end

  def parse_chunk(acc, bytes) do
    %{element: element, rest: bytes} = parse_element(bytes)
    acc = [element | acc]
    if bytes == "" do
      acc
    else
      parse_chunk(acc, bytes)
    end
  end

  def parse(bytes, :File) do
    parse_chunk([], bytes)
  end

  def parse(bytes, :EBML) do
    parse_chunk([], bytes)
  end

  def parse(bytes, :DocTypeReadVersion) do
    uint(bytes)
  end

  def parse(bytes, :DocTypeVersion) do
    uint(bytes)
  end

  def parse(bytes, :DocType) do
    string(bytes)
  end

  def parse(bytes, :EBMLMaxSizeLength) do
    uint(bytes)
  end

  def parse(bytes, :EBMLMaxIDLength) do
    uint(bytes)
  end

  def parse(bytes, :EBMLReadVersion) do
    uint(bytes)
  end

  def parse(bytes, :EBMLVersion) do
    uint(bytes)
  end

  def parse(_bytes, :Void) do
    0
    # Base.encode16(bytes)
  end

  def parse(bytes, :Segment) do
    parse_chunk([], bytes)
  end

  # def parse(bytes, :Cluster) do
  #   parse_chunk([], bytes)
  # end

  def parse(bytes, :Unknown) do
    Base.encode16(bytes)
  end

  def parse_element(bytes) do
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    id = vint.element_id
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    data_size = vint.vint_data
    # TODO: deal with unknown data size
    type = classify_element(id)

    # debug
    element = %{
      id: id,
      data_size: data_size,
      type: type,
      data: "unprocessed"
    }
    IO.inspect(element)

    with %{bytes: data, rest: bytes} <- get_data(bytes, data_size) do
      element = %{
        id: id,
        data_size: data_size,
        type: type,
        data: parse(data, type)
      }

      %{element: element, rest: bytes}
    end
  end

  # def parse(bytes) do
  #     %{element: element, bytes: bytes} = parse_element(bytes)

  #     IO.inspect(element)

  #     element = %{
  #       element |
  #       data:
  #         if element_data_size <= 8 or dont_parse(type) do
  #           if  element_data_size >= 10000 do
  #             :HUGE
  #           else
  #             :binary.decode_unsigned(element_data)
  #           end
  #         else
  #           parse_chunk([], element_data, type)
  #         end
  #     }

  #     %{element: element, rest: bytes}
  #   else
  #     _ -> {:more_bytes_plz, bytes}
  #   end
  # end

  def uint(bytes) do
    :binary.decode_unsigned(bytes)
  end

  def string(bytes) do
    Enum.join(for <<c::utf8 <- bytes>>, do: <<c::utf8>>)
  end

  def get_data(bytes, how_many) do
    # if byte_size(bytes) < how_many do
    #   IO.inspect("split by #{how_many} (got: #{byte_size(bytes)})")
    #   :more_bytes_plz
    # else
    <<bytes::binary-size(how_many), rest::binary>> = bytes
    %{bytes: bytes, rest: rest}
    # {:ok, bytes: bytes, rest: rest}
    # end
  end

  def classify_element(element_id) do #(%{element_id: element_id, element_data_size: element_data_size, element_data: element_data} = element) do
    case element_id do
      # EBML elements:

      "1A45DFA3" -> :EBML #%{element | type: :EBML}
      "4286" -> :EBMLVersion #%{element | type: :EBMLVersion}
      "42F7" -> :EBMLReadVersion #%{element | type: :EBMLReadVersion}
      "42F2" -> :EBMLMaxIDLength #%{element | type: :EBMLMaxIDLength}
      "42F3" -> :EBMLMaxSizeLength #%{element | type: :EBMLMaxSizeLength}
      "4282" -> :DocType #%{element | type: :DocType}
      "4287" -> :DocTypeVersion #%{element | type: :DocTypeVersion}
      "4285" -> :DocTypeReadVersion #%{element | type: :DocTypeReadVersion}
      "4281" -> :DocTypeExtension #%{element | type: :DocTypeExtension}
      "4283" -> :DocTypeExtensionName #%{element | type: :DocTypeExtensionName}
      "4284" -> :DocTypeExtensionVersion #%{element | type: :DocTypeExtensionVersion}
      "BF" -> :CRC_32
        # if element_data_size != 4 do
        #   raise "CRC-32 element with wrong length (should be 4): #{element}"
        # else
        #   %{element | type: :CRC_32}
        # end
      "EC" -> :Void #%{element | type: :Void}

      # Matroska elements:
      "18538067" -> :Segment
      # "1F43B675" -> :Cluster
      # maaaany more
      _ -> :Unknown # raise "Unknown element type: #{element_id}"
    end
  end

end

defmodule Membrane.WebM.Parser.Document do
  @moduledoc """
  composed only of an EBML header and EBML body

  (an EBML Stream is a file that consists of one or more EBML documents concatenated together)
  """
end



# 8.1. EBML Header
# The EBML Header is a declaration that provides processing instructions and identification of the
# EBML Body. The EBML Header of an EBML Document is analogous to the XML Declaration of an
# XML Document.
# The EBML Header documents the EBML Schema (also known as the EBML DocType) that is used
# to semantically interpret the structure and meaning of the EBML Document. Additionally, the
# EBML Header documents the versions of both EBML and the EBML Schema that were used to
# write the EBML Document and the versions required to read the EBML Document.
# The EBML Header contain a single Master Element with an Element Name of EBML and
# Element ID of 0x1A45DFA3 (see Section 11.2.1); the Master Element may have any number of
# additional EBML Elements within it. The EBML Header of an EBML Document that uses an
# EBMLVersion of 1 only contain EBML Elements that are defined as part of this document.
# Elements within an EBML Header can be at most 4 octets long, except for the EBML Element with
# Element Name EBML and Element ID 0x1A45DFA3 (see Section 11.2.1); this Element can be up to 8
# octets long.
# MUST
# MUST
# 8.2. EBML Body
# All data of an EBML Document following the EBML Header is the EBML Body. The end of the
# EBML Body, as well as the end of the EBML Document that contains the EBML Body, is reached at
# whichever comes first: the beginning of a new EBML Header at the Root Level or the end of the
# file. This document defines precisely which EBML Elements are to be used within the EBML
# Header but does not name or define which EBML Elements are to be used within the EBML Body.
# The definition of which EBML Elements are to be used within the EBML Body is defined by an
# EBML Schema.
