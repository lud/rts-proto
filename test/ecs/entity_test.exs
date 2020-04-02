defmodule ECS.EntityTest do
  use ExUnit.Case
  alias ECS.Entity

  test "Create an entity" do
    assert entt = Entity.new(123)
    assert %{} = Entity.components(entt)
  end

  test "Create an entity with components" do
    assert entt = Entity.new(123, %{a: 1})
    assert %{a: 1} = Entity.components(entt)
  end
end
