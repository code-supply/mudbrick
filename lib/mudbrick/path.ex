defmodule Mudbrick.Path do
  defmodule Rectangle do
    @type option ::
            {:lower_left, Mudbrick.coords()}
            | {:dimensions, Mudbrick.coords()}
            | {:line_width, number()}
            | {:colour, Mudbrick.colour()}
            | {:fill, Mudbrick.colour() | nil}
            | {:stroke, boolean()}

    @type options :: [option()]

    @typedoc """
    Without `:fill` a rectangle is stroked in `:colour`, as it always was.

    Given `:fill`, the interior is painted in that colour and the outline is
    dropped — which is what backgrounds, bars and QR modules want. Set
    `stroke: true` alongside it to get both, painted in one operation so the
    two stay aligned.
    """
    @type t :: %__MODULE__{
            lower_left: Mudbrick.coords(),
            dimensions: Mudbrick.coords(),
            line_width: number(),
            colour: Mudbrick.colour(),
            fill: Mudbrick.colour() | nil,
            stroke: boolean()
          }

    @enforce_keys [:lower_left, :dimensions]
    defstruct lower_left: nil,
              dimensions: nil,
              line_width: 1,
              colour: {0, 0, 0},
              fill: nil,
              stroke: false

    @doc false
    @spec new(options()) :: t()
    def new(opts) do
      struct!(__MODULE__, opts)
    end
  end

  defmodule Move do
    @type option :: {:to, Mudbrick.coords()}

    @type options :: [option()]

    @type t :: %__MODULE__{
            to: Mudbrick.coords()
          }

    @enforce_keys [:to]
    defstruct to: nil

    @doc false
    @spec new(options()) :: t()
    def new(opts) do
      struct!(__MODULE__, opts)
    end
  end

  defmodule Line do
    @type option ::
            {:to, Mudbrick.coords()}
            | {:width, number()}
            | {:colour, Mudbrick.colour()}

    @type options :: [option()]

    @type t :: %__MODULE__{
            to: Mudbrick.coords(),
            width: number(),
            colour: Mudbrick.colour()
          }

    @enforce_keys [:to]
    defstruct to: nil,
              width: 1,
              colour: {0, 0, 0}

    @doc false
    @spec new(options()) :: t()
    def new(opts) do
      struct!(__MODULE__, opts)
    end
  end

  @type sub_path ::
          Move.t()
          | Rectangle.t()
          | Line.t()

  @type t :: %__MODULE__{
          sub_paths: [sub_path()]
        }

  defstruct sub_paths: []

  @doc false
  @spec new :: t()
  def new do
    struct!(__MODULE__, [])
  end

  @spec move(t(), Move.options()) :: t()
  def move(path, opts) do
    add(path, Move.new(opts))
  end

  @spec line(t(), Line.options()) :: t()
  def line(path, opts) do
    add(path, Line.new(opts))
  end

  @spec rectangle(t(), Rectangle.options()) :: t()
  def rectangle(path, opts) do
    add(path, Rectangle.new(opts))
  end

  defp add(path, sub_path) do
    %{path | sub_paths: [sub_path | path.sub_paths]}
  end
end
