defmodule ElixirLS.LanguageServer.Protocol.WorkspaceEdit do
  @moduledoc """
  Corresponds to the LSP interface of the same name.

  For details see https://microsoft.github.io/language-server-protocol/specification#workspaceEdit
  """
  @derive JasonVendored.Encoder
  defstruct [:changes, :documentChanges, :changeAnnotations]

  def valid?(%__MODULE__{} = edit) do
    not (is_nil(edit.changes) && is_nil(edit.documentChanges))
  end
end
