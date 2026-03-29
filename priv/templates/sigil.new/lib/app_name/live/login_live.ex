defmodule MyApp.LoginLive do
  use Sigil.Live

  @impl true
  def mount(params, socket) do
    error = params["error"]
    {:ok, Sigil.Live.assign(socket, error: error)}
  end

  @impl true
  def render(assigns) do
    error_html =
      if assigns[:error] do
        """
        <div class="rounded-lg bg-red-50 dark:bg-red-500/10 border border-red-200 dark:border-red-500/20 px-4 py-3 text-sm text-red-600 dark:text-red-400">
          Invalid email or password.
        </div>
        """
      else
        ""
      end

    """
    <div class="flex min-h-full flex-col justify-center px-6 py-12 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-sm">
        <h1 class="text-center font-serif text-3xl font-semibold tracking-tight text-stone-900 dark:text-stone-100">My App</h1>
        <h2 class="mt-6 text-center text-2xl/9 font-bold tracking-tight text-stone-900 dark:text-stone-100">Sign in to your account</h2>
        <p class="mt-2 text-center text-sm text-stone-500">Admin access to manage posts and agents</p>
      </div>

      <div class="mt-10 sm:mx-auto sm:w-full sm:max-w-sm">
        #{error_html}

        <form method="post" action="/auth/login" class="space-y-6">
          <div>
            <label for="email" class="block text-sm/6 font-medium text-stone-700 dark:text-stone-300">Email address</label>
            <div class="mt-2">
              <input type="email" id="email" name="email" autocomplete="email" required
                class="block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 dark:placeholder-stone-500 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 transition-colors" />
            </div>
          </div>

          <div>
            <label for="password" class="block text-sm/6 font-medium text-stone-700 dark:text-stone-300">Password</label>
            <div class="mt-2">
              <input type="password" id="password" name="password" autocomplete="current-password" required
                class="block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 dark:placeholder-stone-500 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 transition-colors" />
            </div>
          </div>

          <div>
            <button type="submit"
              class="flex w-full justify-center rounded-lg bg-stone-900 dark:bg-stone-100 px-3 py-2.5 text-sm font-semibold text-white dark:text-stone-900 shadow-sm hover:bg-stone-800 dark:hover:bg-stone-200 transition-colors">
              Sign in
            </button>
          </div>
        </form>

        <p class="mt-10 text-center text-sm text-stone-500">
          <a href="/" class="font-medium text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-300 transition-colors">← Back</a>
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}
end
