defmodule Mudbrick.ContentStream.TJ do
  @moduledoc false
  defstruct auto_kern: true,
            kerned_text: []

  defimpl Mudbrick.Object do
    def to_iodata(%Mudbrick.ContentStream.TJ{kerned_text: []}) do
      []
    end

    def to_iodata(op) do
      ["[ ", Enum.map(op.kerned_text, &write_glyph(op, &1)), "] TJ"]
    end

    defp write_glyph(%{auto_kern: true} = op, {glyph_id, kerning}) do
      write_glyph(op, glyph_id) ++ [to_string(kerning), " "]
    end

    defp write_glyph(op, {glyph_id, _kerning}) do
      write_glyph(op, glyph_id)
    end

    defp write_glyph(_op, glyph_id) do
      ["<", glyph_id, "> "]
    end
  end
end
