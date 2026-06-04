import gleam/bit_array
import gleam/dynamic
import gleam/int
import gleam/string

pub type Handle {
  Handle(port: dynamic.Dynamic)
}

pub type RecvResult {
  Data(BitArray)
  Timeout
  PortClosed
}

pub type StartError {
  EnsurePortFailed(String)
  OpenPortFailed(String)
  HandshakeFailed(String)
}

pub type Event {
  ButtonClicked(Int)
  Closed
  TextChanged(String)
  KeyDown(Int)
  Log(String)
  PortError(String)
}

@external(erlang, "minigui_ffi", "start")
fn start_ffi() -> Result(dynamic.Dynamic, String)

@external(erlang, "minigui_ffi", "start_with_path")
fn start_with_path_ffi(path: String) -> Result(dynamic.Dynamic, String)

@external(erlang, "minigui_ffi", "send_hello")
fn port_send_hello(port: dynamic.Dynamic, version: Int) -> Nil

@external(erlang, "minigui_ffi", "send_cmd")
fn port_send_cmd(port: dynamic.Dynamic, cmd: Int, req_id: Int, payload: String) -> Nil

@external(erlang, "minigui_ffi", "send_add_button")
fn port_send_add_button(port: dynamic.Dynamic, req_id: Int, id_u8: Int, label: String) -> Nil

@external(erlang, "minigui_ffi", "recv")
fn port_recv(port: dynamic.Dynamic, timeout_ms: Int) -> RecvResult

@external(erlang, "minigui_ffi", "unique_request_id")
fn unique_request_id() -> Int

pub fn start() -> Result(Handle, StartError) {
  // Opens the port using the bootstrap (download/use cache).
  case start_ffi() {
    Ok(port) -> {
      let handle = Handle(port: port)
      case handshake(handle) {
        Ok(_) -> Ok(handle)
        Error(e) -> Error(HandshakeFailed(e))
      }
    }
    Error(e) -> Error(map_start_error(e))
  }
}

pub fn start_with_path(path: String) -> Result(Handle, StartError) {
  case start_with_path_ffi(path) {
    Ok(port) -> {
      let handle = Handle(port: port)
      case handshake(handle) {
        Ok(_) -> Ok(handle)
        Error(e) -> Error(HandshakeFailed(e))
      }
    }
    Error(e) -> Error(map_start_error(e))
  }
}

fn map_start_error(msg: String) -> StartError {
  case string.contains(msg, "ensure_port_failed") {
    True -> EnsurePortFailed(msg)
    False ->
      case string.contains(msg, "open_port_failed") {
        True -> OpenPortFailed(msg)
        False -> OpenPortFailed(msg)
      }
  }
}

// --- Protocol v1 ------------------------------------------------------------
const protocol_version: Int = 1

fn mod_u8(n: Int) -> Int {
  case int.modulo(n, 256) {
    Ok(v) -> v
    Error(_) -> 0
  }
}

fn handshake(handle: Handle) -> Result(Nil, String) {
  // HELLO: 0x00 + u16 protocol_version
  port_send_hello(handle.port, protocol_version)

  case wait_for_message(handle, 2_000) {
    Ok(msg) ->
      case msg {
        // HELLO_ACK: 0xF0 + u16 protocol_version + u32 capabilities
        <<0xF0, v_hi, v_lo, _caps:bytes-size(4)>> -> {
          let v = v_hi * 256 + v_lo
          case v == protocol_version {
            True -> Ok(Nil)
            False -> Error("protocol mismatch: " <> int.to_string(v))
          }
        }
        _ ->
          Error("handshake: unexpected response")
      }
    Error(e) -> Error(e)
  }
}

fn wait_for_message(handle: Handle, timeout_ms: Int) -> Result(BitArray, String) {
  case port_recv(handle.port, timeout_ms) {
    Data(msg) -> Ok(msg)
    Timeout -> Error("timeout")
    PortClosed -> Error("port closed")
  }
}

fn send_cmd_wait_ok(handle: Handle, cmd: Int, payload: String) -> Result(Nil, String) {
  // cmd + request_id(u32).
  let req_id = unique_request_id()
  // To avoid alignment/bitstring issues, we build the message in Erlang.
  // Payload must be a String (binary) for text commands.
  port_send_cmd(handle.port, cmd, req_id, payload)
  wait_for_ok(handle, req_id, 5_000)
}

fn wait_for_ok(handle: Handle, req_id: Int, timeout_ms: Int) -> Result(Nil, String) {
  // There may be interleaved events; loop until OK/ERR.
  case port_recv(handle.port, timeout_ms) {
    Timeout -> Error("timeout waiting for OK/ERR")
    PortClosed -> Error("port closed")
    Data(msg) ->
      case msg {
        <<0x70, got:unsigned-int-size(32)>> ->
          case got == req_id {
            True -> Ok(Nil)
            False -> wait_for_ok(handle, req_id, timeout_ms)
          }

        <<0x71, got:unsigned-int-size(32), rest:bits>> -> {
          case got == req_id {
            True ->
              case bit_array.to_string(rest) {
                Ok(text) -> Error(text)
                Error(_) -> Error("error (invalid utf8)")
              }
            False ->
              wait_for_ok(handle, req_id, timeout_ms)
          }
        }
        _ ->
          // Ignore (events/logs)
          wait_for_ok(handle, req_id, timeout_ms)
      }
  }
}

// --- Public API -------------------------------------------------------------

pub fn create_window(handle: Handle, title: String) -> Result(Nil, String) {
  // CREATE_WINDOW = 0x10 + title utf-8
  send_cmd_wait_ok(handle, 0x10, title)
}

pub fn set_label(handle: Handle, text: String) -> Result(Nil, String) {
  // SET_LABEL = 0x11 + text utf-8
  send_cmd_wait_ok(handle, 0x11, text)
}

pub fn set_text(handle: Handle, text: String) -> Result(Nil, String) {
  // SET_TEXT = 0x12 + text utf-8
  send_cmd_wait_ok(handle, 0x12, text)
}

pub fn add_button(handle: Handle, id: Int, label: String) -> Result(Nil, String) {
  // ADD_BUTTON = 0x13 + u8 id + label utf-8
  let id_u8 = mod_u8(id)
  let req_id = unique_request_id()
  port_send_add_button(handle.port, req_id, id_u8, label)
  wait_for_ok(handle, req_id, 5_000)
}

pub fn run(handle: Handle, on_event: fn(Event) -> Nil) -> Result(Nil, String) {
  // RUN = 0x14
  case send_cmd_wait_ok(handle, 0x14, "") {
    Ok(_) -> loop_events(handle, on_event)
    Error(e) -> Error(e)
  }
}

pub fn quit(handle: Handle) -> Result(Nil, String) {
  // QUIT = 0x15
  send_cmd_wait_ok(handle, 0x15, "")
}

fn loop_events(handle: Handle, on_event: fn(Event) -> Nil) -> Result(Nil, String) {
  case port_recv(handle.port, 60_000) {
    Timeout -> loop_events(handle, on_event)
    PortClosed -> {
      on_event(Closed)
      Ok(Nil)
    }
    Data(msg) -> {
      let ev = decode_event(msg)
      on_event(ev)
      case ev {
        Closed -> Ok(Nil)
        _ -> loop_events(handle, on_event)
      }
    }
  }
}

fn decode_event(msg: BitArray) -> Event {
  case msg {
    <<0x81, id:unsigned-int-size(8)>> -> ButtonClicked(id)
    <<0x82>> -> Closed
    <<0x84, rest:bits>> -> {
      case bit_array.to_string(rest) {
        Ok(text) -> TextChanged(text)
        Error(_) -> PortError("text_changed (invalid utf8)")
      }
    }
    <<0x85, key:unsigned-int-size(32)>> -> KeyDown(key)
    <<0x83, rest:bits>> -> {
      case bit_array.to_string(rest) {
        Ok(text) -> Log(text)
        Error(_) -> Log("log (invalid utf8)")
      }
    }
    <<0x86, rest:bits>> -> {
      case bit_array.to_string(rest) {
        Ok(text) -> PortError(text)
        Error(_) -> PortError("error (invalid utf8)")
      }
    }
    _ -> Log("unknown message")
  }
}
