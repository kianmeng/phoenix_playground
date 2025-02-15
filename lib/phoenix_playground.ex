defmodule PhoenixPlayground do
  @moduledoc """
  Phoenix Playground makes it easy to create single-file Phoenix applications.
  """

  @doc """
  Starts Phoenix Playground.

  This functions starts Phoenix with a LiveView (`:live`), a controller (`:controller`),
  or a router (`:router`).

  ## Options

    * `:live` - a LiveView module.

    * `:controller` - a controller module.

    * `:plug` - a plug.

    * `:port` - port to listen on, defaults to: `4000`.

    * `:open_browser` - whether to open the browser on start, defaults to `true`.

    * `:child_specs` - child specs to run in Phoenix Playground supervision tree. The playground
      Phoenix endpoint is automatically added and is always the last child spec. Defaults to `[]`.
  """
  def start(options) do
    options = Keyword.put_new(options, :file, get_file())

    options =
      if router = options[:router] do
        IO.warn("setting :router is deprecated in favour of setting :plug")

        options
        |> Keyword.delete(:router)
        |> Keyword.put(:plug, router)
      else
        options
      end

    if plug = options[:plug] do
      Application.put_env(:phoenix_playground, :plug, plug)
    end

    case Supervisor.start_child(PhoenixPlayground.Application, {PhoenixPlayground, options}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      other ->
        other
    end
  end

  defp get_file do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    get_file(stacktrace)
  end

  defp get_file([
         {PhoenixPlayground, :start, 1, _},
         {_, :__FILE__, 1, meta} | _
       ]) do
    Path.expand(Keyword.fetch!(meta, :file))
  end

  defp get_file([_ | rest]) do
    get_file(rest)
  end

  defp get_file([]) do
    nil
  end

  @doc false
  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(options) do
    options =
      Keyword.validate!(options, [
        :live,
        :controller,
        :plug,
        :file,
        child_specs: [],
        port: 4000,
        open_browser: true
      ])

    {child_specs, options} = Keyword.pop!(options, :child_specs)

    {type, module} =
      cond do
        live = options[:live] ->
          {:live, live}

        controller = options[:controller] ->
          {:controller, controller}

        options[:plug] ->
          {:plug, :fetch_from_env}

        true ->
          raise "missing :live, :controller, or :plug"
      end

    if options[:open_browser] do
      Application.put_env(:phoenix, :browser_open, true)
    end

    path = options[:file] || to_string(module.__info__(:compile)[:source])
    basename = Path.basename(path)

    # PhoenixLiveReload requires Hex
    Application.ensure_all_started(:hex)
    Application.ensure_all_started(:phoenix_live_reload)

    Application.put_env(:phoenix_live_reload, :dirs, [
      Path.dirname(path)
    ])

    options =
      [
        type: type,
        module: module,
        basename: basename
      ] ++ Keyword.take(options, [:port])

    children =
      child_specs ++
        [
          {Phoenix.PubSub, name: PhoenixPlayground.PubSub},
          {PhoenixPlayground.Reloader, path},
          {PhoenixPlayground.Endpoint, options}
        ]

    System.no_halt(true)
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
