defmodule ECS.OperatorTest do
  use ExUnit.Case
  alias ECS.Operator, as: Op
  alias ECS.Entity

  @id_1 90001
  @id_2 90002

  defp make_op(entities \\ [], opts \\ [])

  defp make_op(entities, opts) when is_list(entities) and is_list(opts) do
    Enum.reduce(entities, Op.new(opts), fn entt, op ->
      {:ok, op} = Op.add_entity(op, entt)
      op
    end)
  end

  defp make_sys(selection, run) do
    ECS.TestUtils.FunSystem.new(%{
      select: fn _op -> selection end,
      run: run
    })
  end

  def dispatch_event(event), do: send(self, {:dispatched, event})

  defmacro dispatch(op, system) do
    quote do
      label = elem(__ENV__.function(), 0)
      op = unquote(op)
      system = unquote(system)
      {t, val} = :timer.tc(Op, :dispatch, [op, system])
      IO.puts("[#{label}] dispatch took #{t / 100} ms")
      val
    end
  end

  test "Create an operator" do
    assert op = Op.new()
    assert 0 = Op.entities_count(op)
    assert {:error, {:not_found, 123}} = Op.fetch_entity(op, 123)
  end

  test "Add, remove, replace entities" do
    op = make_op()

    # Add
    assert {:error, {:bad_entity, :x}} = Op.add_entity(op, :x)
    entity = Entity.new(@id_1)
    assert {:ok, op} = Op.add_entity(op, entity)
    assert 1 = Op.entities_count(op)
    assert {:ok, entity} == Op.fetch_entity(op, @id_1)

    # Replace
    entity1 = Entity.new(@id_1, %{thing: :stuff})
    assert {:error, {:exists, @id_1}} = Op.add_entity(op, entity1)
    assert {:error, {:bad_entity, :x}} = Op.replace_entity(op, :x)
    assert {:ok, op} = Op.replace_entity(op, entity1)
    assert {:ok, entity1} == Op.fetch_entity(op, @id_1)

    # Remove
    assert {:ok, op} = Op.remove_entity(op, @id_1)
    assert 0 = Op.entities_count(op)
    assert {:error, {:not_found, @id_1}} = Op.fetch_entity(op, @id_1)
  end

  test "Dispatch a simple system on all entities" do
    op = make_op([Entity.new(@id_1, %{thing: :stuff}), Entity.new(@id_2, %{thing: :gear})])

    spid = self()

    system =
      ECS.TestUtils.FunSystem.new(%{
        select: fn op -> :all end,
        run: fn %Entity{cs: %{thing: thing}} when thing in [:gear, :stuff] ->
          send(spid, {:thing, thing})
          :ok
        end
      })

    assert {:ok, op} = dispatch(op, system)

    # Entities order is not a guarantee
    assert_receive {:thing, :gear}
    assert_receive {:thing, :stuff}
  end

  test "Dispatch events from a system" do
    op =
      make_op(
        [
          Entity.new(@id_1, %{thing: :stuff}),
          Entity.new(@id_2, %{thing: :gear})
        ],
        dispatch_event: __MODULE__
      )

    system =
      ECS.TestUtils.FunSystem.new(%{
        select: fn _op -> :all end,
        run: fn %Entity{id: id, cs: %{thing: thing}} when thing in [:gear, :stuff] ->
          {:ok, [], {:some_event, id, thing}}
        end
      })

    assert {:ok, op} = dispatch(op, system)

    # Entities order is not a guarantee
    assert_receive {:dispatched, {:some_event, @id_1, :stuff}}
    assert_receive {:dispatched, {:some_event, @id_2, :gear}}
  end

  test "A system can update a selection" do
    op = make_op([Entity.new(@id_1, %{thing: :stuff}), Entity.new(@id_2, %{thing: :gear})])

    system =
      make_sys(:all, fn entity ->
        entity = update_in(entity.cs.thing, fn thing -> thing |> to_string |> String.upcase() end)

        {:ok, [entity]}
      end)

    assert {:ok, op_after} = dispatch(op, system)
    assert "STUFF" = Op.fetch_entity!(op_after, @id_1).cs.thing
    assert "GEAR" = Op.fetch_entity!(op_after, @id_2).cs.thing
  end

  test "A system can return an entity to update instead of a list" do
    op = make_op([Entity.new(@id_1, %{thing: :stuff}), Entity.new(@id_2, %{thing: :gear})])

    system =
      make_sys(:all, fn entity ->
        entity = update_in(entity.cs.thing, fn thing -> thing |> to_string |> String.upcase() end)

        {:ok, entity}
      end)

    assert {:ok, op_after} = dispatch(op, system)
    assert "STUFF" = Op.fetch_entity!(op_after, @id_1).cs.thing
    assert "GEAR" = Op.fetch_entity!(op_after, @id_2).cs.thing
  end

  test "A system must return valid changes" do
    op = make_op([Entity.new(@id_1, %{thing: :stuff}), Entity.new(@id_2, %{thing: :gear})])

    system =
      make_sys(:all, fn entity ->
        entity = update_in(entity.cs.thing, fn thing -> thing |> to_string |> String.upcase() end)

        {:ok, [:some_non_entity_value]}
      end)

    assert {:error, {:bad_change, :some_non_entity_value}} = dispatch(op, system)
  end

  test "A system can update a single entity" do
    op = make_op([Entity.new(@id_1, %{thing: :stuff}), Entity.new(@id_2, %{thing: :gear})])

    system =
      make_sys({:id, @id_1}, fn entity ->
        entity = update_in(entity.cs.thing, fn thing -> thing |> to_string |> String.upcase() end)

        {:ok, entity}
      end)

    assert {:ok, op_after} = dispatch(op, system)
    assert "STUFF" = Op.fetch_entity!(op_after, @id_1).cs.thing
    assert :gear = Op.fetch_entity!(op_after, @id_2).cs.thing
  end
end
