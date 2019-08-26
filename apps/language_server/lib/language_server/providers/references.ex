defmodule ElixirLS.LanguageServer.Providers.References do
  @moduledoc """
  This module provides References support by using
  the `Mix.Tasks.Xref.call/0` task to find all references to
  any function or module identified at the provided location.
  """
  require Logger

  alias ElixirLS.LanguageServer.{SourceFile, Build}

  def references(text, line, character, _include_declaration) do
    Build.with_build_lock(fn ->
      ElixirSense.all_modules()
      |> Enum.map(&to_string/1)
      |> Enum.filter(fn module_name ->
        String.contains?(module_name, "LsProxy") || String.contains?(module_name, "HNClient")
      end)
      |> JaxUtils.plog(label: "all modules filtered contains other")

      ElixirSense.all_modules()
      |> Enum.map(&to_string/1)
      |> Enum.filter(fn module_name ->
        String.starts_with?(module_name, "ElixirLS.LanguageServer.Providers")
      end)
      |> JaxUtils.plog(label: "all modules filtered ls")

      new_ref = new_references(text, line, character)
      JaxUtils.plog(new_ref, label: "new_ref")

      xref_at_cursor(text, line, character)
      |> JaxUtils.plog(label: "before_filter")
      |> Enum.filter(fn %{line: line} -> is_integer(line) end)
      |> JaxUtils.plog(label: "filtered")
      |> Enum.map(&build_location/1)
      |> JaxUtils.plog(label: "old references")

      # new_ref
    end)
    |> JaxUtils.plog(label: "final references")
  end

  def supported? do
    Mix.Tasks.Xref.__info__(:functions) |> Enum.member?({:calls, 0})
  end

  def new_references(text, line, character) do
    references =
      ElixirSense.references(text, line + 1, character + 1)
      |> JaxUtils.plog(label: "plain references")
      |> Enum.map(&build_reference/1)

    references
    |> Enum.map(fn reference ->
      build_loc(reference)
    end)
  end

  defp build_reference(ref) do
    %{
      range: %{
        start: %{line: ref.range.start.line, column: ref.range.start.column},
        end: %{line: ref.range.end.line, column: ref.range.end.column}
      },
      uri: ref.uri
    }
  end

  defp build_loc(reference) do
    # Adjust for ElixirSense 1-based indexing
    line_start = reference.range.start.line - 1
    line_end = reference.range.end.line - 1
    column_start = reference.range.start.column - 1
    column_end = reference.range.end.column - 1

    %{
      "uri" => SourceFile.path_to_uri(reference.uri),
      "range" => %{
        "start" => %{"line" => line_start, "character" => column_start},
        "end" => %{"line" => line_end, "character" => column_end}
      }
    }
  end

  defp xref_at_cursor(text, line, character) do
    env_at_cursor = line_environment(text, line)
    %{aliases: aliases} = env_at_cursor

    subject_at_cursor(text, line, character)
    # TODO: Don't call into here directly
    |> ElixirSense.Core.Source.split_module_and_func(aliases)
    |> expand_mod_fun(env_at_cursor)
    |> add_arity(env_at_cursor)
    |> callers()
  end

  defp line_environment(text, line) do
    # TODO: Don't call into here directly
    ElixirSense.Core.Parser.parse_string(text, true, true, line + 1)
    |> ElixirSense.Core.Metadata.get_env(line + 1)
  end

  defp subject_at_cursor(text, line, character) do
    # TODO: Don't call into here directly
    ElixirSense.Core.Source.subject(text, line + 1, character + 1)
  end

  defp expand_mod_fun({nil, nil}, _environment), do: nil

  defp expand_mod_fun(mod_fun, %{imports: imports, aliases: aliases, module: module}) do
    # TODO: Don't call into here directly
    mod_fun = ElixirSense.Core.Introspection.actual_mod_fun(mod_fun, imports, aliases, module)

    case mod_fun do
      {mod, nil} -> {mod, nil}
      {mod, fun} -> {mod, fun}
    end
  end

  defp add_arity({mod, fun}, %{scope: {fun, arity}, module: mod}), do: {mod, fun, arity}
  defp add_arity({mod, fun}, _env), do: {mod, fun, nil}

  defp callers(mfa) do
    if Mix.Project.umbrella?() do
      umbrella_calls()
    else
      Mix.Tasks.Xref.calls()
    end
    |> Enum.filter(caller_filter(mfa))
  end

  def umbrella_calls() do
    build_dir = Path.expand(Mix.Project.config()[:build_path])

    Mix.Project.apps_paths()
    |> Enum.flat_map(fn {app, path} ->
      Mix.Project.in_project(app, path, [build_path: build_dir], fn _ ->
        Mix.Tasks.Xref.calls()
        |> Enum.map(fn %{file: file} = call ->
          Map.put(call, :file, Path.expand(file))
        end)
      end)
    end)
  end

  defp caller_filter({module, nil, nil}), do: &match?(%{callee: {^module, _, _}}, &1)
  defp caller_filter({module, func, nil}), do: &match?(%{callee: {^module, ^func, _}}, &1)
  defp caller_filter({module, func, arity}), do: &match?(%{callee: {^module, ^func, ^arity}}, &1)

  defp build_location(%{file: file, line: line}) do
    %{
      "uri" => SourceFile.path_to_uri(file),
      "range" => %{
        "start" => %{"line" => line - 1, "character" => 0},
        "end" => %{"line" => line - 1, "character" => 0}
      }
    }
  end
end
