defmodule RtsWeb.PageController do
  use RtsWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
