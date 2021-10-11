# defmodule Membrane.WebM.Schema do
#   @moduledoc """
#   WebM structure schema for muxing and demuxing

#   A WebM file is defined as a Matroska file that satisfies strict constraints.
#   A Matroska file is an EBML file (Extendable-Binary-Meta-Language) with one segment and certain other constraints.

#   Docs:
#   - EBML https://www.rfc-editor.org/rfc/rfc8794.html
#   - WebM https://www.webmproject.org/docs/container/
#   - Matroska https://matroska.org/technical/basics.html

#   WebM codec formats:
#   - Video: VP8 or VP9
#   - Audio: Vorbis or Opus
#   """

#   @typedoc """
#     A typical EBML file has the following structure:
#   [Matroska]
#   [WebM]
#   EBML Header (master)
#   + DocType (string)
#   + DocTypeVersion (unsigned integer)
#   EBML Body Root (master)
#   + ElementA (utf-8)
#   + Parent (master)
#   + ElementB (integer)
#   + Parent (master)
#   + ElementB (integer)
#   """
#   @type ebml :: nil

#   @ebml_element %{element_id: :  element_data_size: :vint, element_data: :vint}

#   @vint [
#     vint_width: "zero or no bits of value 0 terminated by `:vint_marker`",
#     vint_marker: "1",
#     vint_data: "7 * (1 + :vint_width) bits of usable data. data must be left-padded with 0's"
#     # The VINT_DATA value be expressed as a big-endian unsigned integer.
#   ]

# end



defmodule Membrane.WebM.Schema do

  alias Membrane.WebM.Schema.Structs.HeaderElement

  def header_elements do
    [
      %HeaderElement{
        name: "EBML",
        path: "\\EBML",
        id: "1A45DFA3",
        min_occurs: 1,
        max_occurs: 1,
        type: :master_element,
        description: "Set the EBML characteristics of the data to follow. Each EBML Document has to
        start with this. "
      },
      %HeaderElement{
        name: "EBMLVersion",
        path: "\\EBML\\EBMLVersion",
        id: "4286",
        min_occurs: 1,
        max_occurs: 1,
        # range: not 0,
        # default: 1,
        type: :u_int,
        description: "The version of EBML specifications used to create the EBML Document. The
        version of EBML defined in this document is 1, so EBMLVersion be 1."
      },
      %HeaderElement{
        name: "EBMLReadVersion",
        path: "\\EBML\\EBMLReadVersion",
        id: "42F7",
        min_occurs: 1,
        max_occurs: 1,
        # range: 1,
        # default: 1,
        type: :u_int,
        description: "The minimum EBML version an EBML Reader has to support to read this EBML
        Document. The EBMLReadVersion Element be less than or equal to EBMLVersion."
      },
    ]
  end
end
