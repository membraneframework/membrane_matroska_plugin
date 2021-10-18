defmodule Membrane.WebM.Parser.Vint do
  @moduledoc """
  VINT - variable length integer

  Numbers are encoded as VINTs in EBML.
  A VINT consists of three parts:
  - VINT_WIDTH - the number N of leading `0` bits in the first byte of the VINT signifies how many bytes the VINT takes up in total: N+1; having no leading `0` bits is also allowed in which case the VINT takes 1 byte
  - VINT_MARKER - the `1` bit immediately following the VINT_WIDTH `0` bits
  - VINT_DATA - the 7*N bits following the VINT_MARKER
  """

  # nice bitmap library: https://gitlab.com/Project-FiFo/DalmatinerDB/bitmap https://github.com/gausby/bit_field_set

  use Bitwise

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

    %{vint: %{
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

    %{vint: %{
        vint: vint,
        vint_width: vint_width,
        vint_data: vint_data,
        element_id: element_id},
      rest: rest_bytes
    }
  end
end
