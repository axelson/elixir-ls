defmodule ElixirLS.LanguageServer.FormatterOpts do
  @moduledoc """
  Contains code to build the formatter opts for a given file. Code is copied
  from Elixir's Mix.Tasks.Format, but expanded to add support for passing in the path to be
  relative to instead of relying on the global state of CWD.
  """

  @manifest "cached_dot_formatter"
  @manifest_vsn 1

  @doc """
  Returns formatter options to be used for the given file.
  """
  def formatter_opts_for_file(file, project_dir, opts \\ []) do
    {dot_formatter, formatter_opts} = eval_dot_formatter(opts)

    {formatter_opts_and_subs, _sources} =
      eval_deps_and_subdirectories(dot_formatter, [], formatter_opts, [dot_formatter])

    split = file |> Path.relative_to(project_dir) |> Path.split()
    find_formatter_opts_for_file(split, formatter_opts_and_subs)
  end

  defp eval_dot_formatter(opts) do
    cond do
      dot_formatter = opts[:dot_formatter] ->
        {dot_formatter, eval_file_with_keyword_list(dot_formatter)}

      File.regular?(".formatter.exs") ->
        {".formatter.exs", eval_file_with_keyword_list(".formatter.exs")}

      true ->
        {".formatter.exs", []}
    end
  end

  # This function reads exported configuration from the imported
  # dependencies and subdirectories and deals with caching the result
  # of reading such configuration in a manifest file.
  defp eval_deps_and_subdirectories(dot_formatter, prefix, formatter_opts, sources) do
    deps = Keyword.get(formatter_opts, :import_deps, [])
    subs = Keyword.get(formatter_opts, :subdirectories, [])

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

      maybe_cache_in_manifest(dot_formatter, manifest, fn ->
        {subdirectories, sources} = eval_subs_opts(subs, prefix, sources)
        {{eval_deps_opts(formatter_opts, deps), subdirectories}, sources}
      end)
    end
  end

  defp maybe_cache_in_manifest(dot_formatter, manifest, fun) do
    cond do
      is_nil(Mix.Project.get()) or dot_formatter != ".formatter.exs" -> fun.()
      entry = read_manifest(manifest) -> entry
      true -> write_manifest!(manifest, fun.())
    end
  end

  defp read_manifest(manifest) do
    with {:ok, binary} <- File.read(manifest),
         {:ok, {@manifest_vsn, entry, sources}} <- safe_binary_to_term(binary),
         expanded_sources = Enum.flat_map(sources, &Path.wildcard(&1, match_dot: true)),
         false <- Mix.Utils.stale?([Mix.Project.config_mtime() | expanded_sources], [manifest]) do
      {entry, sources}
    else
      _ -> nil
    end
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

  defp eval_subs_opts(subs, prefix, sources) do
    {subs, sources} =
      Enum.flat_map_reduce(subs, sources, fn sub, sources ->
        prefix = Path.join(prefix ++ [sub])
        {Path.wildcard(prefix), [Path.join(prefix, ".formatter.exs") | sources]}
      end)

    Enum.flat_map_reduce(subs, sources, fn sub, sources ->
      sub_formatter = Path.join(sub, ".formatter.exs")

      if File.exists?(sub_formatter) do
        formatter_opts = eval_file_with_keyword_list(sub_formatter)

        {formatter_opts_and_subs, sources} =
          eval_deps_and_subdirectories(:in_memory, [sub], formatter_opts, sources)

        {[{sub, formatter_opts_and_subs}], sources}
      else
        {[], sources}
      end
    end)
  end

  defp assert_valid_dep_and_fetch_path(dep, deps_paths) when is_atom(dep) do
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
    {opts, _} = Code.eval_file(path)

    unless Keyword.keyword?(opts) do
      Mix.raise("Expected #{inspect(path)} to return a keyword list, got: #{inspect(opts)}")
    end

    opts
  end

  defp find_formatter_opts_for_file(split, {formatter_opts, subs}) do
    Enum.find_value(subs, formatter_opts, fn {sub, formatter_opts_and_subs} ->
      if List.starts_with?(split, Path.split(sub)) do
        find_formatter_opts_for_file(split, formatter_opts_and_subs)
      end
    end)
  end
end
