defmodule ElixirLS.LanguageServer.FormatterOpts do
  @moduledoc """
  Contains code to build the formatter opts for a given file. Code is copied
  from Elixir's Mix.Tasks.Format, but expanded to add support for passing in the path to be
  relative to instead of relying on the global state of CWD.
  """

  # I'm not super sure what algorithm we should use to find the correct .formatter.exs to apply
  # I guess I need to study the Elixir code some more to understand exactly what
  # it is doing. The `subdirectories` configuration is important.
  #
  # > :subdirectories (a list of paths and patterns) - specifies subdirectories
  # > that have their own formatting rules. Each subdirectory should have a
  # > .formatter.exs that configures how entries in that subdirectory should be
  # > formatted as. Configuration between .formatter.exs are not shared nor
  # > inherited. If a .formatter.exs lists "lib/app" as a subdirectory, the rules
  # > in .formatter.exs won't be available in lib/app/.formatter.exs. Note that
  # > the parent .formatter.exs must not specify files inside the "lib/app"
  # > subdirectory in its :inputs configuration. If this happens, the behaviour of
  # > which formatter configuration will be picked is unspecified.
  #
  # So how should ElixirLS choose the formatter configuration? Should we do
  # something a bit more defined?
  #
  # TODO: What does formatting wait for? Workspace symbols?
  # Dialyzer?

  @manifest "cached_dot_formatter"
  @manifest_vsn 1

  @doc """
  Returns formatter options to be used for the given file.
  """
  def formatter_opts_for_file(file, project_dir, opts \\ []) do
    {dot_formatter, formatter_opts} = eval_dot_formatter(project_dir, opts)

    {formatter_opts_and_subs, _sources} =
      eval_deps_and_subdirectories(dot_formatter, [], formatter_opts, [dot_formatter], project_dir)

    IO.puts("Finding formatter opts from #{File.cwd!}")
    old_split = file |> Path.relative_to_cwd() |> Path.split()
    IO.inspect(old_split, label: "old_split")
    split = file |> Path.relative_to(project_dir) |> Path.split()
    IO.inspect(split, label: "split")
    # IO.inspect(formatter_opts_and_subs, label: "formatter_opts_and_subs")

    res =
      find_formatter_opts_for_file(split, formatter_opts_and_subs)
      |> IO.inspect(label: "formatter opts")

    {res, ""}
  end

  defp eval_dot_formatter(project_dir, opts) do
    IO.inspect(project_dir, label: "project_dir")
    IO.inspect(opts, label: "eval_dot_formatter opts")
    formatter_abs_path = Path.join(project_dir, ".formatter.exs")
    cond do
      # TODO: How does this get set? Do we need to support it?
      dot_formatter = opts[:dot_formatter] ->
        IO.inspect(dot_formatter, label: "dot_formatter")
        IO.puts("WHO SET the dot_formatter?")
        {dot_formatter, eval_file_with_keyword_list(dot_formatter)}

      File.regular?(formatter_abs_path) ->
        {".formatter.exs", eval_file_with_keyword_list(formatter_abs_path)}

      true ->
        {".formatter.exs", []}
    end
  end

  # This function reads exported configuration from the imported
  # dependencies and subdirectories and deals with caching the result
  # of reading such configuration in a manifest file.
  defp eval_deps_and_subdirectories(dot_formatter, prefix, formatter_opts, sources, project_dir) do
    IO.inspect(formatter_opts, label: "formatter_opts")
    deps = Keyword.get(formatter_opts, :import_deps, [])
    subs = Keyword.get(formatter_opts, :subdirectories, [])
    IO.inspect(deps, label: "deps")
    IO.inspect(subs, label: "subs")

    if not is_list(deps) do
      Mix.raise("Expected :import_deps to return a list of dependencies, got: #{inspect(deps)}")
    end

    if not is_list(subs) do
      Mix.raise("Expected :subdirectories to return a list of directories, got: #{inspect(subs)}")
    end

    if deps == [] and subs == [] do
      {{formatter_opts, []}, sources}
    else
      manifest = Path.join(Mix.Project.manifest_path(), @manifest)
      IO.inspect(manifest, label: "manifest")

      maybe_cache_in_manifest(dot_formatter, manifest, project_dir, fn ->
        {subdirectories, sources} = eval_subs_opts(subs, prefix, sources, project_dir)
        {{eval_deps_opts(formatter_opts, deps), subdirectories}, sources}
      end)
    end
  end

  defp maybe_cache_in_manifest(dot_formatter, manifest, project_dir, fun) do
    cond do
      is_nil(Mix.Project.get()) or dot_formatter != ".formatter.exs" -> fun.()
      entry = read_manifest(manifest, project_dir) -> entry
      true -> write_manifest!(manifest, fun.())
    end
  end

  defp read_manifest(manifest, project_dir) do
    with {:ok, binary} <- File.read(manifest),
         {:ok, {@manifest_vsn, entry, sources}} <- safe_binary_to_term(binary),
           _ <- IO.inspect(sources, label: "sources before"),
           sources = Enum.map(sources, & prepend_project_directory(&1, project_dir)),
      # HERE also
           _ <- IO.inspect(sources, label: "sources after"),
    # TODO: Probably need to interpret these sources by the project directory
         expanded_sources = Enum.flat_map(sources, &Path.wildcard(&1, match_dot: true)),
         false <- Mix.Utils.stale?([Mix.Project.config_mtime() | expanded_sources], [manifest]) do
      {entry, sources}
    else
      _ -> nil
    end
  end

  defp prepend_project_directory(source, project_dir) do
    project_dir <> "/" <> source
    |> IO.inspect(label: "result")
  end

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  rescue
    _ -> :error
  end

  defp write_manifest!(manifest, {entry, sources}) do
    File.mkdir_p!(Path.dirname(manifest))
    File.write!(manifest, :erlang.term_to_binary({@manifest_vsn, entry, sources}))
    {entry, sources}
  end

  defp eval_deps_opts(formatter_opts, []) do
    formatter_opts
  end

  defp eval_deps_opts(formatter_opts, deps) do
    IO.puts("in eval_deps_opts")
    deps_paths = Mix.Project.deps_paths()

    parenless_calls =
      for dep <- deps,
          dep_path = assert_valid_dep_and_fetch_path(dep, deps_paths),
          dep_dot_formatter = Path.join(dep_path, ".formatter.exs"),
          File.regular?(dep_dot_formatter),
          dep_opts = eval_file_with_keyword_list(dep_dot_formatter),
          parenless_call <- dep_opts[:export][:locals_without_parens] || [],
          uniq: true,
          do: parenless_call

    Keyword.update(
      formatter_opts,
      :locals_without_parens,
      parenless_calls,
      &(&1 ++ parenless_calls)
    )
  end

  defp eval_subs_opts(subs, prefix, sources, project_dir) do
    IO.puts("In eval_subs_opts")
    {subs, sources} =
      Enum.flat_map_reduce(subs, sources, fn sub, sources ->
        prefix = Path.join(prefix ++ [sub])
        IO.inspect(prefix, label: "prefix (absolute?)")
        # TODO: Probably need to change here too
        {Path.wildcard(prefix), [Path.join(prefix, ".formatter.exs") | sources]}
      end)

    Enum.flat_map_reduce(subs, sources, fn sub, sources ->
      sub_formatter = Path.join(sub, ".formatter.exs")

      # TODO: and here
      IO.puts("checking sub_foramtter #{sub_formatter}")
      if File.exists?(sub_formatter) do
        formatter_opts = eval_file_with_keyword_list(sub_formatter)

        {formatter_opts_and_subs, sources} =
          eval_deps_and_subdirectories(:in_memory, [sub], formatter_opts, sources, project_dir)

        {[{sub, formatter_opts_and_subs}], sources}
      else
        {[], sources}
      end
    end)
  end

  defp assert_valid_dep_and_fetch_path(dep, deps_paths) when is_atom(dep) do
    IO.inspect(deps_paths, label: "deps_paths (absolute?)")
    case Map.fetch(deps_paths, dep) do
      {:ok, path} ->
        if File.dir?(path) do
          path
        else
          Mix.raise(
            "Unavailable dependency #{inspect(dep)} given to :import_deps in the formatter configuration. " <>
              "The dependency cannot be found in the file system, please run \"mix deps.get\" and try again"
          )
        end

      :error ->
        Mix.raise(
          "Unknown dependency #{inspect(dep)} given to :import_deps in the formatter configuration. " <>
            "The dependency is not listed in your mix.exs for environment #{inspect(Mix.env())}"
        )
    end
  end

  defp assert_valid_dep_and_fetch_path(dep, _deps_paths) do
    Mix.raise("Dependencies in :import_deps should be atoms, got: #{inspect(dep)}")
  end

  defp eval_file_with_keyword_list(path) do
    # FIXME: Ensure this is absolute
    IO.puts("Eval file (absolute?): #{path}")
    {opts, _} = Code.eval_file(path)

    unless Keyword.keyword?(opts) do
      Mix.raise("Expected #{inspect(path)} to return a keyword list, got: #{inspect(opts)}")
    end

    opts
  end

  defp find_formatter_opts_for_file(split, {formatter_opts, subs}) do
    IO.puts("HERE")
    IO.inspect(split, label: "split")
    IO.inspect(subs, label: "subs")
    IO.inspect(formatter_opts, label: "formatter_opts")
    Enum.find_value(subs, formatter_opts, fn {sub, formatter_opts_and_subs} ->
      if List.starts_with?(split, Path.split(sub)) do
        find_formatter_opts_for_file(split, formatter_opts_and_subs)
      end
    end)
  end
end
