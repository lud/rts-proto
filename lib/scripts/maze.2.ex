defmodule Maze2 do
  def generate(width, height) do
    x_min = 0
    x_max = width - 1
    y_min = 0
    y_max = height - 1

    # maze = %{
    #   grid: %{{0, 0} => :path, {1, 0} => :path, {2, 0} => :path},
    #   dim: {x_min, y_min, x_max, y_max},
    #   # {:edge, {1, 0}, 2}} is {:edge, parent, weight}}
    #   edges: [{{3, 0}, {:edge, {2, 0}, 2}}, {{2, 1}, {:edge, {2, 0}, 2}}]
    # }

    maze = %{
      grid: %{
        {0, 0} => :path,
        {x_max, y_max} => :path
        # {div(x_max, 4), div(y_max, 4)} => :path,
        # {div(x_max, 4) * 3, div(y_max, 4)} => :path,
        # {div(x_max, 4), div(y_max, 4) * 3} => :path,
        # {div(x_max, 4) * 3, div(y_max, 4) * 3} => :path
      },
      dim: {x_min, y_min, x_max, y_max},
      # One set of edges per team
      edges:
        {[
           # {:edge, {1, 0}, 2}} is {:edge, parent, weight}}
           {{1, 0}, {:edge, {0, 0}, 0}},
           {{0, 1}, {:edge, {0, 0}, 0}}
         ],
         [
           {{x_max, y_max - 1}, {:edge, {x_max, y_max}, 0}},
           {{x_max - 1, y_max}, {:edge, {x_max, y_max}, 0}}
         ]}
    }

    maze |> loop(1_000_000)
  end

  def in_bounds?(%{dim: {x_min, y_min, x_max, y_max}}, {x, y})
      when x < x_min or x > x_max or y < y_min or y > y_max,
      do: false

  def in_bounds?(%{dim: _grid}, {_x, _y}),
    do: true

  def get(%{dim: {x_min, y_min, x_max, y_max}}, {x, y})
      when x < x_min or x > x_max or y < y_min or y > y_max do
    throw(:out_of_bounds)
  end

  def get(%{grid: grid}, {x, y}) do
    Map.get(grid, {x, y}, {:unknown, {x, y}})
  end

  def path?(%{grid: grid}, {x, y}) do
    Map.get(grid, {x, y}) == :path
  end

  def x_min(%{dim: {x_min, _, _, _}}), do: x_min
  def x_max(%{dim: {_, _, x_max, _}}), do: x_max
  def y_min(%{dim: {_, y_min, _, _}}), do: y_min
  def y_max(%{dim: {_, _, _, y_max}}), do: y_max

  defp loop(maze, 0),
    do: maze

  defp loop(%{edges: {[], []}} = maze, _),
    do: maze

  defp loop(%{edges: {[], other_team_edges}} = maze, steps),
    do: loop(%{maze | edges: {other_team_edges, []}}, steps)

  defp loop(maze, steps) when steps > 0 do
    # - first we pick an edge randomly with the most weight
    # - then we check if it can become a path (not connecting to other
    #   paths besindes its parent)
    # - and also if the next cell in this direction can become a path,
    #   for we will advance two cells at once.
    # - if yes, we set it as a path, compute new edges, and loop
    # - if no we try with another edge
    # - we do not set walls on the map

    # case get_random_edge_deep(edges) do
    %{edges: {edges, other_team_edges}, grid: grid} = maze

    case get_random_edge_deep(edges) do
      {nil, _edges} ->
        maze

      {edge, new_edges} ->
        next_cell_as_edge = forward_edge(edge)

        maze =
          if could_be_path?(edge, maze) and could_be_path?(next_cell_as_edge, maze) do
            {xy, {:edge, _, _}} = edge
            {next_xy, {:edge, _, _}} = next_cell_as_edge

            grid = grid |> Map.put(xy, :path) |> Map.put(next_xy, :path)
            new_edges = insert_edges(compute_edges(next_cell_as_edge, grid), new_edges)
            # we flip the edges so at each iteration we handle the other team
            %{maze | grid: grid, edges: {other_team_edges, new_edges}}
          else
            # edge was invalid, it is discarded
            %{maze | edges: {other_team_edges, new_edges}}
          end

        # maze |> render() |> print()
        loop(maze, steps - 1)
    end
  end

  defp insert_edges([], acc),
    do: acc

  defp insert_edges([h | t], acc),
    do: insert_edges(t, insert_edge(h, acc))

  # defp insert_edge(e, [h | t]), do: [h | insert_edge(e, t)]
  # defp insert_edge(e, []), do: [e]

  defp insert_edge({_, {:edge, _, weight}} = e, [{_, {:edge, _, higher_weight}} = next | tail])
       when weight < higher_weight,
       do: [next | insert_edge(e, tail)]

  defp insert_edge(e, acc),
    do: [e | acc]

  # select all edges with the top weight, the pick one randomly
  # then subtract it from the list and return edge and new list
  defp get_random_edge_breadth([]), do: {nil, []}

  defp get_random_edge_breadth(edges) do
    edge = random_edge(edges)
    edges = edges -- [edge]
    {edge, edges}
  end

  defp get_random_edge_deep([]), do: {nil, []}

  defp get_random_edge_deep(edges) do
    edge =
      edges
      |> top_edges()
      |> random_edge()

    edges = edges -- [edge]
    {edge, edges}
  end

  defp get_random_edge_deep_2nd([], _), do: {nil, []}

  # take the 2nd top edges, start by removing the top edges, then run top edges again
  defp get_random_edge_deep_2nd(edges, count) do
    tops = top_edges(edges)

    others = edges -- tops

    case get_random_edge_deep(others) do
      # if we do not have 2nd edges, we will fallback to the top ones
      {nil, []} -> get_random_edge_deep(edges)
      {edge, others2} -> {edge, tops ++ others2}
    end
  end

  defp random_edge(list) do
    index = :random.uniform(length(list)) - 1
    Enum.at(list, index)
  end

  # we return the weight so we can substract from the list
  defp top_edges([]), do: []

  defp top_edges([{_, {:edge, _parent, weight}} = e | edges]),
    do: [e | top_edges(edges, weight)]

  defp top_edges([{_, {:edge, _parent, weight}} = e | edges], weight),
    do: [e | top_edges(edges, weight)]

  defp top_edges(_, _), do: []

  defp could_be_path?({{x, y}, {:edge, _, _}} = e, %{
         grid: grid,
         dim: {x_min, y_min, x_max, y_max}
       })
       when x >= x_min and x <= x_max and y >= y_min and y <= y_max do
    could_be_path_2?(e, grid)
  end

  defp could_be_path?({{_, _}, {:edge, _, _}}, _), do: false

  defp could_be_path_2?({{x, y}, {:edge, parent, _}}, grid) do
    # we will check if all carninal neighbours are not paths
    neighbours = cardinal_neighbours({x, y}) -- [parent]
    Enum.all?(neighbours, fn xy -> Map.get(grid, xy) != :path end)
  end

  defp compute_edges({{x, y}, {:edge, parent, weight}}, _grid) do
    # we will use a tric as we know we create a grid of squares.
    # edges coordinates can only have some properties
    (cardinal_neighbours({x, y}) -- [parent])
    |> Enum.filter(fn
      {x, y} when rem(x, 2) != rem(y, 2) -> true
      # {x, y} when rem(x, 2) == 1 and rem(y, 2) == 0 -> true
      # {x, y} when rem(x, 2) == 0 and rem(y, 2) == 1 -> true
      _ -> false
    end)
    |> Enum.map(fn xy -> {xy, {:edge, {x, y}, weight + 1}} end)
  end

  def cardinal_neighbours({x, y}) do
    [{x, y - 1}, {x, y + 1}, {x + 1, y}, {x - 1, y}]
  end

  defp forward_edge({{x, y}, {:edge, {parent_x, parent_y}, weight}}) do
    {diff_x, diff_y} = {x - parent_x, y - parent_y}
    added = {x + diff_x, y + diff_y}
    {added, {:edge, {x, y}, weight + 1}}
  end

  def render(%{grid: grid, dim: {x_min, y_min, x_max, y_max}, edges: {edges_a, edges_b}}) do
    grid =
      grid
      |> Map.merge(Map.new(edges_a))
      |> Map.merge(Map.new(edges_b))

    for y <- (y_min - 1)..(y_max + 1) do
      for x <- (x_min - 1)..(x_max + 1) do
        render_tile(Map.get(grid, {x, y}, :undef))
      end
    end
  end

  defp render_tile(:undef), do: bgcolor(" ", :black)
  defp render_tile(:path), do: bgcolor(32, :white)
  defp render_tile({:edge, _, _}), do: bgcolor(32, :light_black)

  defp bgcolor(io, :white), do: [IO.ANSI.white_background(), io, IO.ANSI.reset()]
  defp bgcolor(io, :black), do: [IO.ANSI.black_background(), io, IO.ANSI.reset()]
  defp bgcolor(io, :light_black), do: [IO.ANSI.light_black_background(), io, IO.ANSI.reset()]

  def print(rendered) do
    IO.puts(IO.ANSI.cursor(0, 0))

    rendered
    |> Enum.intersperse(?\n)
    |> IO.puts()

    # Process.sleep(15)
  end
end
