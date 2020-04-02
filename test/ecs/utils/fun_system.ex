defmodule ECS.TestUtils.FunSystem do
  defstruct impls: %{}
  @behaviour ECS.System

  def new(impls) when is_map(impls),
    do: {__MODULE__, impls}

  def select(impls, op),
    do: impls.select.(op)

  def run(impls, entities),
    do: impls.run.(entities)
end
