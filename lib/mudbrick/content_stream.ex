defmodule Mudbrick.ContentStream do
  @enforce_keys [:page]
  defstruct page: nil, operations: []

  alias Mudbrick.Document

  defmodule Tf do
    defstruct [:font, :size]

    defimpl Mudbrick.Object do
      def from(tf) do
        [Mudbrick.Object.from(tf.font.resource_identifier), " ", to_string(tf.size), " Tf"]
      end
    end
  end

  defmodule Td do
    defstruct [:tx, :ty]

    defimpl Mudbrick.Object do
      def from(td) do
        [td.tx, td.ty, "Td"] |> Enum.map(&to_string/1) |> Enum.intersperse(" ")
      end
    end
  end

  defmodule Tj do
    defstruct [:text]

    defimpl Mudbrick.Object do
      def from(tj) do
        [Mudbrick.Object.from(tj.text), " Tj"]
      end
    end
  end

  defmodule TJ do
    defstruct [:font, :text]

    defimpl Mudbrick.Object do
      def from(tj) do
        data = tj.font.descendant.value.descriptor.value.file.value.data

        {glyph_ids_decimal, _positions} =
          OpenType.new()
          |> OpenType.parse(data)
          |> OpenType.layout_text(tj.text)

        glyph_ids_hex =
          glyph_ids_decimal
          |> Enum.map(fn id ->
            id
            |> Integer.to_string(16)
            |> String.pad_leading(4, "0")
          end)

        ["[<", glyph_ids_hex, ">] TJ"]
      end
    end
  end

  defmodule Ts do
    defstruct [:rise]

    defimpl Mudbrick.Object do
      def from(ts) do
        [Mudbrick.Object.from(ts.rise), " Ts"]
      end
    end
  end

  def new(opts \\ []) do
    struct!(Mudbrick.ContentStream, opts)
  end

  def add({doc, contents_obj}, Tj, opts) do
    Document.update(doc, contents_obj, fn contents ->
      Map.update!(contents, :operations, fn ops ->
        [%Tj{text: opts[:text]} | ops]
      end)
    end)
  end

  def add({doc, contents_obj}, mod, opts) do
    Document.update(doc, contents_obj, fn contents ->
      Map.update!(contents, :operations, fn ops ->
        [struct(mod, opts) | ops]
      end)
    end)
  end

  defimpl Mudbrick.Object do
    def from(stream) do
      inner = [
        "BT\n",
        Enum.map_join(Enum.reverse(stream.operations), "\n", &Mudbrick.Object.from/1),
        "\nET"
      ]

      [
        Mudbrick.Object.from(%{Length: :erlang.iolist_size(inner)}),
        "\nstream\n",
        inner,
        "\nendstream"
      ]
    end
  end
end
