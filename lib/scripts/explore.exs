defmodule Explore do
  alias Maze2, as: M

  require Record
  Record.defrecord(:rcell, explored: false, type: :path, team: nil)

  def run() do
    seed = :rand.uniform(999_999)
    :random.seed(seed)
    # :random.seed(2)
    maze = M.generate(79, 33)

    maze
    |> M.render()
    |> M.print()

    pos = {0, 0}
    pos2 = {M.x_max(maze), M.y_max(maze)}

    state = %{
      pos: nil,
      team: :a,
      grid: %{
        pos => rcell(explored: false, type: :path),
        pos2 => rcell(explored: false, type: :path)
      },
      track: [],
      maze: maze,
      action: {:move_to, pos}
    }

    state =
      state
      |> loop
      |> Map.put(:action, {:move_to, pos2})
      |> Map.put(:team, :b)
      |> loop

    state |> render() |> print()
    IO.inspect(seed, label: :seed)
  end

  defp loop(%{action: :finished} = state), do: state

  defp loop(state) do
    state = handle_action(state)
    # IO.inspect(state.grid, label: "state grid")
    # state |> render() |> print()
    loop(state)
  end

  defp handle_action(%{action: {:move_to, pos}} = state) do
    state = %{state | pos: pos}

    case explore_pos(state) do
      {state, []} ->
        backtrack(state)

      {state, explorables} ->
        count = length(explorables)

        # add some randomness to have a random exploration pattern
        [{next_pos, rcell(explored: false)} | _] = Enum.shuffle(explorables)

        %{state | action: {:move_to, next_pos}, track: [{pos, count} | state.track]}
    end
  end

  defp handle_action(%{action: {:backtrack, pos}} = state) do
    backtrack(%{state | pos: pos})
  end

  defp backtrack(state) do
    case state.track do
      [] ->
        %{state | action: :finished}

      [{next_pos, 1} | track_tail] ->
        %{state | action: {:backtrack, next_pos}, track: track_tail}

      [{next_pos, n} | track_tail] when n > 1 ->
        %{state | action: {:move_to, next_pos}, track: track_tail}
    end
  end

  defp explore_pos(%{pos: pos, maze: maze, grid: grid, team: team} = state) do
    # 1. check the neighbour paths, add the new discovered cells in the grid
    # 2. check if some is not explored
    # 3. if found, go there ; if not, backtrack
    explorables_xys =
      pos
      |> M.cardinal_neighbours()
      |> Enum.filter(&M.path?(maze, &1))
      |> Enum.filter(fn xy ->
        case Map.fetch(grid, xy) do
          {:ok, rcell(explored: false)} -> true
          :error -> true
          _ -> false
        end
      end)

    # IO.inspect(explorables_xys, label: "explorables_xys")

    grid =
      explorables_xys
      |> Enum.reduce(grid, fn xy, grid ->
        case Map.fetch(grid, xy) do
          {:ok, _} -> grid
          :error -> Map.put(grid, xy, rcell(explored: false, type: :path))
        end
      end)
      |> Map.update!(pos, fn r -> rcell(r, explored: true, team: team) end)

    # |> IO.inspect(label: "new grid")

    explorables =
      grid
      |> Map.take(explorables_xys)
      |> Enum.reject(fn {_, cell} -> rcell(cell, :explored) end)

    # IO.inspect(explorables, label: "explorables")

    state = %{state | grid: grid}

    {state, explorables}
  end

  def render(%{pos: pos, grid: grid, maze: %{dim: {x_min, y_min, x_max, y_max}}}) do
    grid = Map.put(grid, pos, :pos)

    for y <- (y_min - 1)..(y_max + 1) do
      for x <- (x_min - 1)..(x_max + 1) do
        render_tile(Map.get(grid, {x, y}, :undef))
      end
    end
  end

  defp render_tile(:pos), do: bgcolor("O", :green)
  defp render_tile(:undef), do: bgcolor(32, :black)
  defp render_tile(rcell(type: {:unknown, _})), do: bgcolor(32, :black)
  defp render_tile(rcell(explored: true, type: :path, team: :a)), do: bgcolor(32, :red)
  defp render_tile(rcell(explored: true, type: :path, team: :b)), do: bgcolor(32, :blue)
  defp render_tile(rcell(explored: false, type: :path)), do: bgcolor(32, :light_black)

  defp bgcolor(io, :green), do: [IO.ANSI.green_background(), io, IO.ANSI.reset()]
  defp bgcolor(io, :white), do: [IO.ANSI.white_background(), io, IO.ANSI.reset()]
  defp bgcolor(io, :black), do: [IO.ANSI.black_background(), io, IO.ANSI.reset()]
  defp bgcolor(io, :red), do: [IO.ANSI.red_background(), io, IO.ANSI.reset()]
  defp bgcolor(io, :blue), do: [IO.ANSI.blue_background(), io, IO.ANSI.reset()]
  defp bgcolor(io, :light_black), do: [IO.ANSI.light_black_background(), io, IO.ANSI.reset()]

  def print(rendered) do
    IO.puts(IO.ANSI.cursor(0, 0))

    rendered
    |> Enum.intersperse(?\n)
    |> IO.puts()

    # Process.sleep(15)
  end
end

IO.puts(IO.ANSI.clear())

Explore.run()

System.halt()
