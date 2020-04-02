defmodule ECS.System do
  alias ECS.Operator, as: Op
  @type system :: any
  @callback select(system, operator :: Op.t()) ::
              {:ok, Op.selection()} | {:error, reason :: any}

  @callback run(system, Op.selection(), Op.context()) ::
              {:ok, Op.changes()}
              | {:ok, Op.changes(), Op.events()}
              | {:ok, Op.changes(), Op.events(), Op.context()}
              | {:error, any}
end
