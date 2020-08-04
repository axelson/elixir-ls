defmodule ElixirLS.LanguageServer.CLI do
  alias ElixirLS.Utils.{WireProtocol, Launch}
  alias ElixirLS.LanguageServer.JsonRpc

  def main do
    WireProtocol.intercept_output(&JsonRpc.print/1, &JsonRpc.print_err/1)
    Launch.start_mix()

    {:ok, _} = Application.ensure_all_started(:language_server, :temporary)
    IO.puts("Started ElixirLS v#{Launch.language_server_version()}")
    Launch.print_versions()

    start_node()

    Mix.shell(ElixirLS.LanguageServer.MixShell)
    # FIXME: Private API
    Mix.Hex.ensure_updated?()

    WireProtocol.stream_packets(&JsonRpc.receive_packet/1)
  end

  def start_node(number \\ 0) do
    node_name = node_name(number)

    case Node.start(node_name, :shortnames) do
      {:error, _error} ->
        start_node(number + 1)

      {:ok, _pid} ->
        IO.puts(
          """
          Started node with name #{inspect(node_name)}. Connect by running:
          `iex --sname local --cookie cookie`
          Then within iex run `Node.connect(#{inspect(node_name)})`
          Now you can run `:observer.start()` and switch to the #{inspect(node_name)} and analyze ElixirLS
          """
        )

        Node.set_cookie(node_name, :cookie)
    end
  end

  def node_name(number) do
    {:ok, hostname} = :inet.gethostname()

    "elixirls-#{number}@#{hostname}"
    |> String.to_atom()
  end
end
