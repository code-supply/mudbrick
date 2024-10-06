defmodule Mudbrick.Indirect do
  defmodule Ref do
    defstruct [:number]

    def new(number) do
      %__MODULE__{number: number}
    end

    defimpl Mudbrick.Object do
      def from(%Mudbrick.Indirect.Ref{number: number}) do
        [to_string(number), " 0 R"]
      end
    end
  end

  defmodule Object do
    defstruct [:value, :ref]

    alias Mudbrick.Indirect

    def new(ref, value) do
      %__MODULE__{value: value, ref: ref}
    end

    def renumber(obj, number) do
      %__MODULE__{obj | ref: %Indirect.Ref{obj.ref | number: number}}
    end

    defimpl Mudbrick.Object do
      def from(%Mudbrick.Indirect.Object{value: value, ref: ref}) do
        [to_string(ref.number), " 0 obj\n", Mudbrick.Object.from(value), "\nendobj"]
      end
    end
  end
end
