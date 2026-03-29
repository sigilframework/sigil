defmodule Journal.Router do
  use Sigil.Router

  # Public
  live "/", Journal.HomeLive, layout: {Journal.Layout, :app}
  live "/entry/:id", Journal.EntryLive, layout: {Journal.Layout, :app}
  live "/chat", Journal.ChatLive, layout: {Journal.Layout, :app}
  live "/chat/:slug", Journal.ChatLive, layout: {Journal.Layout, :app}

  # Auth
  live "/login", Journal.LoginLive, layout: {Journal.Layout, :app}

  post "/auth/login" do
    Journal.AuthController.login(conn, [])
  end

  post "/auth/logout" do
    Journal.AuthController.logout(conn, [])
  end

  # Uploads
  post "/admin/uploads" do
    Journal.UploadController.upload(conn, [])
  end

  # Admin (protected)
  live "/admin", Journal.Admin.DashboardLive, auth: true, layout: {Journal.Layout, :admin}

  live "/admin/conversations", Journal.Admin.ConversationsLive, auth: true, layout: {Journal.Layout, :admin}
  live "/admin/conversations/:id", Journal.Admin.ConversationsLive, auth: true, layout: {Journal.Layout, :admin}

  live "/admin/posts", Journal.Admin.PostsLive, auth: true, layout: {Journal.Layout, :admin}
  live "/admin/posts/new", Journal.Admin.PostsLive, auth: true, layout: {Journal.Layout, :admin}
  live "/admin/posts/:id/edit", Journal.Admin.PostsLive, auth: true, layout: {Journal.Layout, :admin}

  live "/admin/agents", Journal.Admin.AgentsLive, auth: true, layout: {Journal.Layout, :admin}
  live "/admin/agents/new", Journal.Admin.AgentsLive, auth: true, layout: {Journal.Layout, :admin}
  live "/admin/agents/:id/edit", Journal.Admin.AgentsLive, auth: true, layout: {Journal.Layout, :admin}

  live "/admin/tools", Journal.Admin.ToolsLive, auth: true, layout: {Journal.Layout, :admin}

  live "/admin/settings", Journal.Admin.SettingsLive, auth: true, layout: {Journal.Layout, :admin}

  sigil_routes()
end
