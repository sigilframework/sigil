defmodule Journal.Layout do
  @moduledoc "Layout module for Sigil Journal using Tailwind CSS with dark/light mode."

  def app(_assigns, inner_content) do
    """
    <!DOCTYPE html>
    <html lang="en" class="h-full">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Adam's Journal</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:wght@400;500;600;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
      <script src="https://cdn.tailwindcss.com"></script>
      <script src="https://cdn.tailwindcss.com?plugins=typography"></script>
      <script>
        tailwind.config = {
          darkMode: 'class',
          theme: {
            extend: {
              fontFamily: {
                serif: ['EB Garamond', 'Georgia', 'serif'],
                sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'sans-serif'],
              }
            }
          }
        }
      </script>
      <script>
        // Theme: default to light, persist choice
        (function() {
          var theme = localStorage.getItem('theme');
          if (theme === 'dark') {
            document.documentElement.classList.add('dark');
          }
        })();
      </script>
      <style>
        body { font-family: 'Inter', ui-sans-serif, system-ui, -apple-system, sans-serif; -webkit-font-smoothing: antialiased; }
      </style>
    </head>
    <body class="h-full bg-stone-50 text-stone-900 dark:bg-stone-950 dark:text-stone-100 transition-colors duration-200">
      <!-- Theme Toggle -->
      <button onclick="toggleTheme()" id="theme-toggle"
        class="fixed top-4 right-4 z-50 p-2 rounded-full bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 shadow-sm hover:bg-stone-100 dark:hover:bg-stone-700 transition-colors"
        aria-label="Toggle dark mode">
        <svg id="sun-icon" class="w-4 h-4 text-stone-500 hidden dark:block" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" />
        </svg>
        <svg id="moon-icon" class="w-4 h-4 text-stone-500 block dark:hidden" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z" />
        </svg>
      </button>
      #{inner_content}
      <script src="/assets/sigil.js?v=#{System.system_time(:second)}"></script>
      <script>
        function toggleTheme() {
          document.documentElement.classList.toggle('dark');
          localStorage.setItem('theme', document.documentElement.classList.contains('dark') ? 'dark' : 'light');
        }
      </script>
    </body>
    </html>
    """
  end

  def admin(_assigns, inner_content) do
    """
    <!DOCTYPE html>
    <html lang="en" class="h-full">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Admin — Adam's Journal</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
      <script src="https://cdn.tailwindcss.com"></script>
      <script src="https://cdn.tailwindcss.com?plugins=typography"></script>
      <script>
        tailwind.config = {
          darkMode: 'class',
          theme: {
            extend: {
              fontFamily: {
                serif: ['EB Garamond', 'Georgia', 'serif'],
                sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'sans-serif'],
              }
            }
          }
        }
      </script>
      <script>
        (function() {
          var theme = localStorage.getItem('theme');
          if (theme === 'dark') document.documentElement.classList.add('dark');
        })();
      </script>
      <style>
        body { font-family: 'Inter', ui-sans-serif, system-ui, -apple-system, sans-serif; -webkit-font-smoothing: antialiased; }
      </style>
    </head>
    <body class="h-full bg-stone-50 text-stone-900 dark:bg-stone-950 dark:text-stone-100 transition-colors duration-200">
      <!-- Theme Toggle -->
      <button onclick="toggleTheme()" id="theme-toggle-admin"
        class="fixed top-4 right-4 z-50 p-2 rounded-full bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 shadow-sm hover:bg-stone-100 dark:hover:bg-stone-700 transition-colors"
        aria-label="Toggle dark mode">
        <svg class="w-4 h-4 text-stone-500 hidden dark:block" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" />
        </svg>
        <svg class="w-4 h-4 text-stone-500 block dark:hidden" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z" />
        </svg>
      </button>
      <!-- Admin Nav -->
      <nav class="border-b border-stone-200 dark:border-stone-800 bg-white/80 dark:bg-stone-900/80 backdrop-blur-sm sticky top-0 z-40">
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div class="flex h-14 items-center justify-between">
            <a href="/admin" class="text-sm font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">
              <span class="text-amber-500">⚡</span> Journal Admin
            </a>
            <div class="flex items-center gap-6">
              <a href="/admin/conversations" class="text-sm text-stone-500 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">Conversations</a>
              <a href="/admin/posts" class="text-sm text-stone-500 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">Posts</a>
              <a href="/admin/agents" class="text-sm text-stone-500 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">Agents</a>
              <a href="/admin/tools" class="text-sm text-stone-500 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">Tools</a>
              <a href="/admin/settings" class="text-sm text-stone-500 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">Settings</a>
              <a href="/" target="_blank" class="text-sm text-stone-500 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">View Site ↗</a>
              <form method="post" action="/auth/logout" class="inline">
                <button type="submit" class="text-sm text-stone-500 hover:text-stone-700 dark:hover:text-stone-300 border border-stone-300 dark:border-stone-700 rounded-lg px-3 py-1 transition-colors">Logout</button>
              </form>
            </div>
          </div>
        </div>
      </nav>
      <!-- Admin Content -->
      <main class="h-[calc(100vh-3.5rem)] flex flex-col overflow-hidden">
        #{inner_content}
      </main>
      <script src="/assets/sigil.js?v=#{System.system_time(:second)}"></script>
      <script>
        function toggleTheme() {
          document.documentElement.classList.toggle('dark');
          localStorage.setItem('theme', document.documentElement.classList.contains('dark') ? 'dark' : 'light');
        }
      </script>
    </body>
    </html>
    """
  end
end
