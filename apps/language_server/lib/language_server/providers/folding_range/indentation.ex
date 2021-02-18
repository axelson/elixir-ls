defmodule ElixirLS.LanguageServer.Providers.FoldingRange.Indentation do
  @moduledoc """
  Code folding based on indentation only.
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
      |> Enum.map(&extract_cell/1)
      |> pair_cells()
      |> pairs_to_ranges()

    {:ok, ranges}
  end

  defp extract_cell({_line, cell, _first}), do: cell

  @doc """
  Pairs cells into {start, end} tuples of regions
  Public function for testing
  """
  @spec pair_cells([Line.cell()]) :: [{Line.cell(), Line.cell()}]
  def pair_cells(cells) do
    do_pair_cells(cells, [], [], [])
  end

  # Base case
  defp do_pair_cells([], _, _, pairs) do
    pairs
    |> Enum.map(fn
      {cell1, cell2, []} -> {cell1, cell2}
      {cell1, _, empties} -> {cell1, List.last(empties)}
    end)
    |> Enum.reject(fn {{r1, _}, {r2, _}} -> r1 + 1 >= r2 end)
  end

  # Empty row
  defp do_pair_cells([{_, nil} = head | tail], stack, empties, pairs) do
    do_pair_cells(tail, stack, [head | empties], pairs)
  end

  # Empty stack
  defp do_pair_cells([head | tail], [], empties, pairs) do
    do_pair_cells(tail, [head], empties, pairs)
  end

  # Non-empty stack: head is to the right of the top of the stack
  defp do_pair_cells([{_, x} = head | tail], [{_, y} | _] = stack, _, pairs) when x > y do
    do_pair_cells(tail, [head | stack], [], pairs)
  end

  # Non-empty stack: head is equal to or to the left of the top of the stack
  defp do_pair_cells([{_, x} = head | tail], stack, empties, pairs) do
    # If the head is <= to the top of the stack, then we need to pair it with
    # everything on the stack to the right of it.
    # The head can also start a new region, so it's pushed onto the stack.
    {leftovers, new_tail_stack} = stack |> Enum.split_while(fn {_, y} -> x <= y end)
    new_pairs = leftovers |> Enum.map(&{&1, head, empties})
    do_pair_cells(tail, [head | new_tail_stack], [], new_pairs ++ pairs)
  end

  @spec pairs_to_ranges([{Line.cell(), Line.cell()}]) :: [FoldingRange.t()]
  defp pairs_to_ranges(pairs) do
    pairs
    |> Enum.map(fn {{r1, _}, {r2, _}} ->
      %{
        startLine: r1,
        endLine: r2 - 1,
        kind?: :region
      }
    end)
  end
end
