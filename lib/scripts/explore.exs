defmodule Explore do
  alias Maze2, as: M

  def run() do
    :random.seed(1)
    maze = M.generate(79, 33)

    maze
    |> M.render()
    |> M.print()

    pos = {0, 0}

    state = %{
      pos: pos,
      grid: %{pos => :path},
      explored: %{pos => true},
      track: [],
      maze: maze
    }

    loop(state)
  end

  defp loop(%{pos: pos, maze: maze}) do
    # 1. check the neighbour paths
    # 2. check if some is not explored
    neighbour_paths =
      pos
      |> M.cardinal_neighbours()
      |> Enum.filter(&M.path?(maze, &1))
  end
end

IO.puts(IO.ANSI.clear())

Explore.run()
|> IO.inspect()

System.halt()
