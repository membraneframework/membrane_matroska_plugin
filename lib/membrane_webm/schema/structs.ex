
defmodule Membrane.WebM.Schema.Structs.HeaderElement do
  defstruct name: nil, path: nil, id: nil, min_occurs: nil, max_occurs: nil, type: nil, description: nil
end

defmodule Membrane.WebM.Schema.Structs.Vint do
  defstruct vint: nil, vint_width: nil, vint_data: nil, element_id: nil
end
