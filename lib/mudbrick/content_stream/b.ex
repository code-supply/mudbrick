defmodule Mudbrick.ContentStream.B do
  @moduledoc false

  defstruct []

  defimpl Mudbrick.Object do
    def to_iodata(_op) do
      ["B"]
    end
  end
end
