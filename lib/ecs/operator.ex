defmodule ECS.Operator do
  alias ECS.{Entity}

  defstruct entities: %{}, ctx: %{}, dispatch_event: nil

  @type t :: %__MODULE__{entities: %{optional(any) => Entity.t()}, ctx: %{optional(atom) => any}}
  @type selection :: :all

  def new(opts \\ []) when is_list(opts) do
    dispatch_event = resolve_dispatcher(Keyword.get(opts, :dispatch_event, NoDispatcher))
    %__MODULE__{dispatch_event: dispatch_event}
  end

  defp resolve_dispatcher(mod) when is_atom(mod),
    do: {mod, :dispatch_event, []}

  defp resolve_dispatcher({mod, args}) when is_atom(mod) and is_list(args),
    do: {mod, :dispatch_event, args}

  defp resolve_dispatcher({mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args),
    do: {mod, fun, args}

  def entities_count(%__MODULE__{entities: entities}),
    do: Kernel.map_size(entities)

  def fetch_entity!(%__MODULE__{entities: entities}, id) do
    case lookup_entity(entities, id) do
      {:ok, entt} -> entt
      {:error, reason} -> raise reason
    end
  end

  def fetch_entity(%__MODULE__{entities: entities}, id),
    do: lookup_entity(entities, id)

  defp lookup_entity(entities, id) do
    case Map.fetch(entities, id) do
      {:ok, data} -> {:ok, data}
      :error -> {:error, {:not_found, id}}
    end
  end

  def add_entity(%__MODULE__{entities: entts} = this, %Entity{id: id} = entt) do
    if Map.has_key?(entts, id) do
      {:error, {:exists, id}}
    else
      entts = Map.put(entts, id, entt)
      {:ok, Map.put(this, :entities, entts)}
    end
  end

  def add_entity(%__MODULE__{}, other),
    do: {:error, {:bad_entity, other}}

  def replace_entity(%__MODULE__{entities: entts} = this, %Entity{id: id} = entt) do
    if Map.has_key?(entts, id) do
      entts = Map.put(entts, id, entt)
      {:ok, Map.put(this, :entities, entts)}
    else
      {:error, {:not_found, id}}
    end
  end

  def replace_entity(%__MODULE__{}, other),
    do: {:error, {:bad_entity, other}}

  def remove_entity(%__MODULE__{entities: entts} = this, id) do
    with {:ok, _} <- fetch_entity(this, id) do
      entts = Map.delete(entts, id)
      {:ok, Map.put(this, :entities, entts)}
    end
  end

  def dispatch(%__MODULE__{} = this, system) do
    {mod, sstate} = expand_system(system)

    # @todo pass to update system state before the dispatch, then do not pass
    # context at all. After the dispatch, allow the system to update the context

    rselect =
      sstate
      # @todo do not pass operator, only sstate for select()
      |> mod.select(this)
      |> resolve_selection(this)

    with {:ok, changes, events, sstate} <- run_system(this, mod, sstate, rselect),

         # @todo @optimize Allow to disable reversing in production
         # @todo @optimize If changes validation is disabled, do reverse then flatten as for events

         # events were stacked reversely, but we expect that inside each
         # batch they were in order. So we reverse the top list, and flatten after
         #  [[:a2, :b2], [:a1, :b1]] --> [[:a1, :b1], [:a2, :b2]] --> [:a1, :b1, :a2, :b2]
         events = events |> :lists.reverse() |> :lists.flatten(),

         # change have the same behaviour but were reversed when validated so we flatten first
         # [[:b2, :a2], [:b1, :a1]] --> [:b2, :a2, :b1, :a1] --> [:a1, :b1, :a2, :b2]
         changes = changes |> :lists.flatten() |> :lists.reverse(),
         {this, _change_events} <- apply_changes(this, changes) do
      # @todo Should we dispatch change_events too ? If a system want to handle
      # entity update events, they are hooks to do san, or it can return a
      # custom event. So not need atm.

      # @todo try/catch the dispatch
      dispatch_events(this, events)
      {:ok, this}
    end
  end

  defp expand_system(%mod{} = system), do: {mod, system}
  defp expand_system({mod, system}) when is_atom(mod), do: {mod, system}

  defp resolve_selection(:all, %__MODULE__{entities: entities}),
    # @todo @optimize keep an index of all ids
    do: {:map_ids, Map.keys(entities)}

  defp resolve_selection({:id, id}, _),
    # @todo @optimize Separate implementation of the loop in run_system to
    # be able to directly act on the entities when the selection is not a list
    do: {:map_ids, [id]}

  # Running a system for all entities matched by id
  defp run_system(%{entities: entities}, mod, sstate, {:map_ids, ids}) do
    # We will stack the add_changes list on top of the changes list. which
    # means that "changes" in the accumulator is a list of list of
    # changes.
    # Same for events.
    {changes, events, sstate} =
      List.foldl(ids, {[], [], sstate}, fn id, {changes, events, sstate} ->
        with {:ok, entity} <- lookup_entity(entities, id),
             {:ok, add_changes, add_events, sstate} <- call_system(mod, sstate, entity) do
          {[add_changes | changes], [add_events | events], sstate}
        else
          {:error, _} = error -> throw(error)
        end
      end)

    {:ok, changes, events, sstate}
  catch
    {:error, _} = error -> error
  end

  # entt is an entity if our selection was {:map_ids, _}, but it can be also
  # a custom data structure containing multiple entities. The system that
  # defines a selection must handle the shape.
  # We do not check if events is a list, because in the end the top list is
  # flattened, so any value is OK (the operator do not handle events).
  defp call_system(mod, sstate, entt) do
    ran =
      case mod.run(sstate, entt) do
        :ok ->
          {:ok, [], [], sstate}

        {:ok, %Entity{} = entt} ->
          {:ok, [entt], [], sstate}

        {:ok, changes} when is_list(changes) ->
          {:ok, changes, [], sstate}

        {:ok, changes, events} when is_list(changes) ->
          {:ok, changes, events, sstate}

        {:ok, changes, _events, _new_sstate} = full when is_list(changes) ->
          full

        {:error, _reason} = error ->
          error

        other ->
          {:error, {:bad_return, other}}
      end

    # @todo @optimize disable validate changes in production ?
    with {:ok, changes, events, sstate} <- ran,
         # @todo @optimize pass the full changes lists here as the base acc so we do
         # not need to flatten in the end
         {:ok, changes} <- validate_changes(changes, []) do
      {:ok, changes, events, sstate}
    end
  end

  defp validate_changes([h | t], acc) do
    with {:ok, h} <- validate_change(h) do
      validate_changes(t, [h | acc])
    end
  end

  defp validate_changes([], acc), do: {:ok, acc}

  defp validate_change(%Entity{} = entt), do: {:ok, entt}
  defp validate_change(other), do: {:error, {:bad_change, other}}

  defp apply_changes(this, changes) do
    %{entities: entts} = this

    {entts, events} =
      for change <- changes, reduce: {entts, []} do
        {entts, events} -> apply_change(change, {entts, events})
      end

    # @todo @optimize Do not reverse list
    {%__MODULE__{this | entities: entts}, events |> :lists.reverse()}
  end

  defp apply_change(%Entity{id: id} = entt, {entts, events}) do
    {Map.put(entts, id, entt), [{:updated, id} | events]}
  end

  # @todo @optimize do not flatten the events, just recurse into lists here
  defp dispatch_events(%{dispatch_event: {m, f, a}}, events) do
    :lists.foreach(fn event -> apply(m, f, [event | a]) end, events)
  end
end
