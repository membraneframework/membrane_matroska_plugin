defmodule Membrane.WebM.Serializer.EBML do
  @moduledoc false

  alias Membrane.WebM.Schema

  @doc "
  Encodes the provided number as a VINT ready for serialization

  See https://datatracker.ietf.org/doc/html/rfc8794#section-4
  "
  @spec encode_vint(non_neg_integer) :: binary
  def encode_vint(number) do
    # +==============+======================+
    # | Octet Length | Possible Value Range |
    # +==============+======================+
    # | 1            | 0 to 2^(7) - 2       |
    # +--------------+----------------------+
    # | 2            | 0 to 2^(14) - 2      |
    # +--------------+----------------------+
    # | 3            | 0 to 2^(21) - 2      |
    # +--------------+----------------------+
    # | 4            | 0 to 2^(28) - 2      |
    # +--------------+----------------------+
    # | 5            | 0 to 2^(35) - 2      |
    # +--------------+----------------------+
    # | 6            | 0 to 2^(42) - 2      |
    # +--------------+----------------------+
    # | 7            | 0 to 2^(49) - 2      |
    # +--------------+----------------------+
    # | 8            | 0 to 2^(56) - 2      |
    # +--------------+----------------------+

    limits = [
      126,
      16_382,
      2_097_150,
      268_435_454,
      34_359_738_366,
      4_398_046_511_102,
      562_949_953_421_310,
      72_057_594_037_927_936
    ]

    octets = Enum.find_index(limits, fn max_num -> number < max_num end) + 1
    width_bits = octets - 1
    data_bits = octets * 7

    <<0::size(width_bits), 1::1, number::big-size(data_bits)>>
  end

  @doc "
  Returns the Element's ELEMENT_ID ready for serialization

  See https://datatracker.ietf.org/doc/html/rfc8794#section-5
  Matroska elements and id's https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-matroska-schema
  WebM supported Matroska elements https://www.webmproject.org/docs/container/#EBML
  "
  @spec encode_element_id(atom) :: binary
  def encode_element_id(name) do
    id = Schema.name_to_element_id(name)
    :binary.encode_unsigned(id, :big)
  end
end
