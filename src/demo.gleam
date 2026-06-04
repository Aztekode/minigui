import gleam/io
import gleam/int
import minigui

pub fn main() {
  io.println("Starting minigui demo…")

  case minigui.start() {
    Error(e) -> io.println("Error starting: " <> start_error_to_string(e))
    Ok(gui) -> {
      let _ = minigui.create_window(gui, "MiniGUI demo")
      let _ = minigui.set_label(gui, "Hello from minigui")
      let _ = minigui.set_text(gui, "Type here…")
      let _ = minigui.add_button(gui, 1, "Click")

      io.println("Calling minigui.run(). Close the window to finish.")

      let _ =
        minigui.run(gui, fn(ev) {
          case ev {
            minigui.ButtonClicked(id) ->
              io.println("Event: ButtonClicked(" <> int.to_string(id) <> ")")

            minigui.TextChanged(text) ->
              io.println("Event: TextChanged(" <> text <> ")")

            minigui.KeyDown(key) ->
              io.println("Event: KeyDown(" <> int.to_string(key) <> ")")

            minigui.Log(msg) ->
              io.println("LOG: " <> msg)

            minigui.PortError(msg) ->
              io.println("ERROR: " <> msg)

            minigui.Closed ->
              io.println("Event: Closed")
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
