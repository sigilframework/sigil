defmodule Journal.Admin.SettingsLive do
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1]

  @impl true
  def mount(_params, socket) do
    settings = Journal.Settings.all()
    user = socket.assigns[:current_user]

    {:ok,
     Sigil.Live.assign(socket,
       site_name: settings["site_name"],
       site_tagline: settings["site_tagline"],
       email: user && user.email,
       flash: nil,
       flash_type: nil
     )}
  end

  @impl true
  def render(assigns) do
    """
    <div class="mx-auto max-w-3xl px-6 py-8 overflow-y-auto h-full">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-stone-900 dark:text-stone-100">Settings</h1>
        <p class="mt-1 text-sm text-stone-500">Manage your site and account settings.</p>
      </div>

      #{flash_banner(assigns)}

      <!-- Site Settings -->
      <form sigil-submit="save_site" class="mb-12">
        <div class="border-b border-stone-200 dark:border-stone-800 pb-8">
          <h2 class="text-base font-semibold text-stone-900 dark:text-stone-100">Site</h2>
          <p class="mt-1 text-sm text-stone-500">These settings control how your site appears to visitors.</p>

          <div class="mt-6 space-y-5">
            <div>
              <label for="site_name" class="block text-sm font-medium text-stone-700 dark:text-stone-300">Site Name</label>
              <input type="text" name="site_name" id="site_name" value="#{escape(assigns.site_name)}"
                class="mt-1.5 block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 shadow-sm focus:border-amber-500 focus:ring-amber-500 focus:outline-none transition-colors" />
              <p class="mt-1 text-xs text-stone-400">Shown in the sidebar, browser tab, and admin header.</p>
            </div>

            <div>
              <label for="site_tagline" class="block text-sm font-medium text-stone-700 dark:text-stone-300">Tagline</label>
              <input type="text" name="site_tagline" id="site_tagline" value="#{escape(assigns.site_tagline)}"
                class="mt-1.5 block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 shadow-sm focus:border-amber-500 focus:ring-amber-500 focus:outline-none transition-colors" />
              <p class="mt-1 text-xs text-stone-400">A short description displayed below the site name.</p>
            </div>
          </div>
        </div>

        <div class="mt-6 flex justify-end">
          <button type="submit"
            class="rounded-lg bg-stone-900 dark:bg-stone-100 px-4 py-2 text-sm font-semibold text-white dark:text-stone-900 shadow-sm hover:bg-stone-700 dark:hover:bg-stone-300 transition-colors">
            Save Site Settings
          </button>
        </div>
      </form>

      <!-- Account Settings -->
      <form sigil-submit="save_email" class="mb-12">
        <div class="border-b border-stone-200 dark:border-stone-800 pb-8">
          <h2 class="text-base font-semibold text-stone-900 dark:text-stone-100">Email</h2>
          <p class="mt-1 text-sm text-stone-500">Update your login email address.</p>

          <div class="mt-6">
            <label for="email" class="block text-sm font-medium text-stone-700 dark:text-stone-300">Email Address</label>
            <input type="email" name="email" id="email" value="#{escape(assigns.email || "")}"
              class="mt-1.5 block w-full max-w-md rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 shadow-sm focus:border-amber-500 focus:ring-amber-500 focus:outline-none transition-colors" />
          </div>
        </div>

        <div class="mt-6 flex justify-end">
          <button type="submit"
            class="rounded-lg bg-stone-900 dark:bg-stone-100 px-4 py-2 text-sm font-semibold text-white dark:text-stone-900 shadow-sm hover:bg-stone-700 dark:hover:bg-stone-300 transition-colors">
            Update Email
          </button>
        </div>
      </form>

      <!-- Password -->
      <form sigil-submit="save_password">
        <div class="border-b border-stone-200 dark:border-stone-800 pb-8">
          <h2 class="text-base font-semibold text-stone-900 dark:text-stone-100">Password</h2>
          <p class="mt-1 text-sm text-stone-500">Update your login password. Minimum 8 characters.</p>

          <div class="mt-6 space-y-5">
            <div>
              <label for="new_password" class="block text-sm font-medium text-stone-700 dark:text-stone-300">New Password</label>
              <input type="password" name="new_password" id="new_password" autocomplete="new-password"
                class="mt-1.5 block w-full max-w-md rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 shadow-sm focus:border-amber-500 focus:ring-amber-500 focus:outline-none transition-colors" />
            </div>
            <div>
              <label for="confirm_password" class="block text-sm font-medium text-stone-700 dark:text-stone-300">Confirm Password</label>
              <input type="password" name="confirm_password" id="confirm_password" autocomplete="new-password"
                class="mt-1.5 block w-full max-w-md rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 shadow-sm focus:border-amber-500 focus:ring-amber-500 focus:outline-none transition-colors" />
            </div>
          </div>
        </div>

        <div class="mt-6 flex justify-end">
          <button type="submit"
            class="rounded-lg bg-stone-900 dark:bg-stone-100 px-4 py-2 text-sm font-semibold text-white dark:text-stone-900 shadow-sm hover:bg-stone-700 dark:hover:bg-stone-300 transition-colors">
            Update Password
          </button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("save_site", params, socket) do
    Journal.Settings.put("site_name", params["site_name"] || "")
    Journal.Settings.put("site_tagline", params["site_tagline"] || "")

    {:noreply,
     Sigil.Live.assign(socket,
       site_name: params["site_name"],
       site_tagline: params["site_tagline"],
       flash: "Site settings saved.",
       flash_type: :success
     )}
  end

  def handle_event("save_email", params, socket) do
    user = socket.assigns[:current_user]
    new_email = String.trim(params["email"] || "")

    case Journal.Settings.update_email(user, new_email) do
      {:ok, updated_user} ->
        {:noreply,
         Sigil.Live.assign(socket,
           current_user: updated_user,
           email: updated_user.email,
           flash: "Email updated to #{updated_user.email}.",
           flash_type: :success
         )}

      {:error, changeset} ->
        msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)

        {:noreply, Sigil.Live.assign(socket, flash: msg, flash_type: :error)}
    end
  end

  def handle_event("save_password", params, socket) do
    user = socket.assigns[:current_user]
    new_pw = params["new_password"] || ""
    confirm_pw = params["confirm_password"] || ""

    cond do
      new_pw == "" ->
        {:noreply, Sigil.Live.assign(socket, flash: "Password cannot be blank.", flash_type: :error)}

      new_pw != confirm_pw ->
        {:noreply, Sigil.Live.assign(socket, flash: "Passwords do not match.", flash_type: :error)}

      true ->
        case Journal.Settings.update_password(user, new_pw) do
          {:ok, _} ->
            {:noreply, Sigil.Live.assign(socket, flash: "Password updated.", flash_type: :success)}

          {:error, msg} ->
            {:noreply, Sigil.Live.assign(socket, flash: msg, flash_type: :error)}
        end
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp flash_banner(assigns) do
    case assigns[:flash] do
      nil ->
        ""

      msg ->
        {bg, text, border} =
          case assigns[:flash_type] do
            :success -> {"bg-emerald-50 dark:bg-emerald-900/20", "text-emerald-800 dark:text-emerald-300", "border-emerald-200 dark:border-emerald-800"}
            :error -> {"bg-red-50 dark:bg-red-900/20", "text-red-800 dark:text-red-300", "border-red-200 dark:border-red-800"}
            _ -> {"bg-stone-50 dark:bg-stone-900/20", "text-stone-800 dark:text-stone-300", "border-stone-200 dark:border-stone-800"}
          end

        """
        <div class="mb-6 rounded-lg border #{border} #{bg} px-4 py-3">
          <p class="text-sm #{text}">#{escape(msg)}</p>
        </div>
        """
    end
  end
end
