defmodule MyApp.Router do
  use Sigil.Router

  # Public
  live "/", MyApp.HomeLive, layout: {MyApp.Layout, :app}
  live "/entry/:id", MyApp.EntryLive, layout: {MyApp.Layout, :app}
  live "/chat", MyApp.ChatLive, layout: {MyApp.Layout, :app}
  live "/chat/:slug", MyApp.ChatLive, layout: {MyApp.Layout, :app}

  # Auth
  live "/login", MyApp.LoginLive, layout: {MyApp.Layout, :app}

  post "/auth/login" do
    MyApp.AuthController.login(conn, [])
  end

  post "/auth/logout" do
    MyApp.AuthController.logout(conn, [])
  end

  # Uploads
  post "/admin/uploads" do
    MyApp.UploadController.upload(conn, [])
  end

  # Admin (protected)
  live "/admin", MyApp.Admin.DashboardLive, auth: true, layout: {MyApp.Layout, :admin}

  live "/admin/conversations", MyApp.Admin.ConversationsLive, auth: true, layout: {MyApp.Layout, :admin}
  live "/admin/conversations/:id", MyApp.Admin.ConversationsLive, auth: true, layout: {MyApp.Layout, :admin}

  live "/admin/posts", MyApp.Admin.PostsLive, auth: true, layout: {MyApp.Layout, :admin}
  live "/admin/posts/new", MyApp.Admin.PostsLive, auth: true, layout: {MyApp.Layout, :admin}
  live "/admin/posts/:id/edit", MyApp.Admin.PostsLive, auth: true, layout: {MyApp.Layout, :admin}

  live "/admin/agents", MyApp.Admin.AgentsLive, auth: true, layout: {MyApp.Layout, :admin}
  live "/admin/agents/new", MyApp.Admin.AgentsLive, auth: true, layout: {MyApp.Layout, :admin}
  live "/admin/agents/:id/edit", MyApp.Admin.AgentsLive, auth: true, layout: {MyApp.Layout, :admin}

  live "/admin/tools", MyApp.Admin.ToolsLive, auth: true, layout: {MyApp.Layout, :admin}

  live "/admin/settings", MyApp.Admin.SettingsLive, auth: true, layout: {MyApp.Layout, :admin}

  sigil_routes()
end
