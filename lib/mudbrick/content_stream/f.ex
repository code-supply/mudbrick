defmodule Mudbrick.ContentStream.F do
  @moduledoc false

  defstruct []

  defimpl Mudbrick.Object do
    def to_iodata(_op) do
      ["f"]
    end
  end
end
