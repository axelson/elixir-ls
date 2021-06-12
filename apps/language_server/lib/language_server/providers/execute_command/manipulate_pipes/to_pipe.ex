defmodule ElixirLS.LanguageServer.Providers.ExecuteCommand.ManipulatePipes.ToPipe do
  # defp to_pipe_at_cursor(text, line, col) do
  #              IO.inspect(text, label: "text")
  #   result =
  #     ElixirSense.Core.Source.walk_text(
  #       text,
  #       %{walked_text: "", function_call: nil, range: nil},
  #       fn current_char, remaining_text, current_line, current_col, acc ->
  #         if current_line - 1 == line and current_col - 1 == col do
  #           {:ok, function_call, call_range} =
  #             get_function_call(line, col, acc.walked_text, current_char, remaining_text)

  #           {remaining_text,
  #            %{
  #              acc
  #              | walked_text: acc.walked_text <> current_char,
  #                function_call: function_call,
  #                range: call_range
  #            }}
  #         else
  #           {remaining_text, %{acc | walked_text: acc.walked_text <> current_char}}
  #         end
  #       end
  #     )

  #   IO.inspect(result, label: "result")

  #   with {:result, %{function_call: function_call, range: range}}
  #        when not is_nil(function_call) and not is_nil(range) <- {:result, result},
  #        {:ok, piped_text} <- AST.to_pipe(function_call) do
  #          IO.inspect(function_call, label: "function_call")
  #          IO.inspect(piped_text, label: "piped_text")
  #     {:ok, %{edited_text: piped_text, edit_range: range}}
  #   else
  #     {:result, %{function_call: nil}} ->
  #       {:error, :function_call_not_found}

  #     {:error, :invalid_code} ->
  #       {:error, :invalid_code}
  #   end
  # end
end
