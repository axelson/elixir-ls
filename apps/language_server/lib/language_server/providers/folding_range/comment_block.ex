defmodule ElixirLS.LanguageServer.Providers.FoldingRange.CommentBlock do
  @moduledoc """
  Code folding based on comment blocks.

  Note that this can create comment regions inside heredocs.
  It's a little sloppy, but I don't think it's a big problem.
  """

  alias ElixirLS.LanguageServer.Providers.FoldingRange
  alias ElixirLS.LanguageServer.Providers.FoldingRange.Line

  @doc """
  Provides ranges for the source text based on the indentation level.
  Note that we trim trailing empy rows from regions.
  """
  @spec provide_ranges(FoldingRange.input()) :: {:ok, [FoldingRange.t()]}
  def provide_ranges(%{lines: lines}) do
    ranges =
      lines
      |> group_comments()
      |> Enum.map(&convert_comment_group_to_range/1)

    {:ok, ranges}
  end

  @spec group_comments([Line.t()]) :: [{Line.cell(), String.t()}]
  defp group_comments(lines) do
    lines
    |> Enum.reduce([[]], fn
      {_, cell, "#"}, [[{_, "#"} | _] = head | tail] ->
        [[{cell, "#"} | head] | tail]

      {_, cell, "#"}, [[] | tail] ->
        [[{cell, "#"}] | tail]

      _, [[{_, "#"} | _] | _] = acc ->
        [[] | acc]

      _, acc ->
        acc
    end)
    |> Enum.filter(fn group -> length(group) > 1 end)
  end

  @spec group_comments([{Line.cell(), String.t()}]) :: [FoldingRange.t()]
  defp convert_comment_group_to_range(group) do
    {{{end_line, _}, _}, {{start_line, _}, _}} =
      group |> FoldingRange.Helpers.first_and_last_of_list()

    %{
      startLine: start_line,
      # We're not doing end_line - 1 on purpose.
      # It seems weird to show the first _and_ last line of a comment block.
      endLine: end_line,
      kind?: :comment
    }
  end
end