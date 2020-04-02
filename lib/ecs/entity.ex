defmodule ECS.Entity do
  defstruct id: nil, cs: %{}

  @type t() :: %__MODULE__{}

  def new(id) when nil != id,
    do: %__MODULE__{id: id}

  def new(id, comps) when nil != id and is_map(comps),
    do: %__MODULE__{id: id, cs: comps}

  def components(%__MODULE__{cs: comps}),
    do: comps
end
