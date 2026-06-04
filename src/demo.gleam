import gleam/io
import gleam/int
import minigui

pub fn main() {
  io.println("Iniciando demo de minigui…")

  case minigui.start() {
    Error(e) -> io.println("Error al iniciar: " <> start_error_to_string(e))
    Ok(gui) -> {
      let _ = minigui.create_window(gui, "MiniGUI demo")
      let _ = minigui.set_label(gui, "Hola desde minigui")
      let _ = minigui.set_text(gui, "Escribe aquí…")
      let _ = minigui.add_button(gui, 1, "Click")

      io.println("Llamando a minigui.run(). Cierra la ventana para terminar.")

      let _ =
        minigui.run(gui, fn(ev) {
          case ev {
            minigui.ButtonClicked(id) ->
              io.println("Evento: ButtonClicked(" <> int.to_string(id) <> ")")

            minigui.TextChanged(text) ->
              io.println("Evento: TextChanged(" <> text <> ")")

            minigui.KeyDown(key) ->
              io.println("Evento: KeyDown(" <> int.to_string(key) <> ")")

            minigui.Log(msg) ->
              io.println("LOG: " <> msg)

            minigui.PortError(msg) ->
              io.println("ERROR: " <> msg)

            minigui.Closed ->
              io.println("Evento: Closed")
          }
        })

      Nil
    }
  }
}

fn start_error_to_string(e: minigui.StartError) -> String {
  case e {
    minigui.EnsurePortFailed(msg) -> msg
    minigui.OpenPortFailed(msg) -> msg
    minigui.HandshakeFailed(msg) -> msg
  }
}
