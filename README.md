# minigui

`minigui` is an experimental library for creating graphical user interfaces from **Gleam (Erlang target)** using a native **external C port**.

## Status / scope

- **Windows**: **Win32** backend (window + label + textbox + button).
- **Linux**: **GTK3** backend (window + label + textbox + button).
- **macOS**: for now, **headless mode** only (simulated).

> Note: on Linux the `minigui` binary links against GTK3, so the system must have GTK3 available at runtime (common on desktops; on minimal servers you may need to install packages).

The goal is to keep a small, stable API in Gleam, while enabling native per-platform backends.

## Releases / publishing

See the checklist: [`RELEASING.md`](./RELEASING.md)

## Installation (Gleam Packages)

```bash
gleam add minigui
```

### "Build-dependency-free" (precompiled binary)

To avoid requiring your users to install a C compiler or headers (`libx11-dev`, etc.), `minigui` is designed to use a **precompiled executable** as a bridge (a *port*) and download it automatically into `priv/` on first use.

By default it builds the URL like this:

```
https://github.com/Aztekode/minigui/releases/download/v<version>/<asset>
```

Where `<version>` comes from the package `vsn` (e.g. `0.1.0`) and `<asset>` depends on the OS/architecture, for example:

- `minigui.exe` (Windows x64)
- `minigui` (Linux x64)

You can override the download base with:

```bash
MINIGUI_RELEASE_BASE_URL="https://github.com/Aztekode/minigui/releases/download/v0.1.2"
```

If you prefer an exact link like `.../minigui.exe`, you can set the full URL:

```bash
MINIGUI_PORT_URL="https://github.com/Aztekode/minigui/releases/download/v0.1.2/minigui.exe"
```

Security/cache options:

- By default, `minigui` **requires** `minigui(.exe).sha256` to exist and validates the SHA256.
- `MINIGUI_REQUIRE_SHA=0`: disables validation (not recommended).
- The binary is cached per user (Linux: `~/.cache/minigui/<version>/`, Windows: `%LOCALAPPDATA%\\minigui\\<version>\\`).

> Runtime requirement: a "full" Erlang/OTP installation that includes the standard `inets` + `ssl` applications (they usually ship with OTP; on some Linux distros they may be split into separate packages).

## Protocolo (v1)

The port is opened with `open_port(..., [{packet, 2}, binary, ...])`.

- Handshake:
  - `0x00` `HELLO` + `u16 version`
  - `0xF0` `HELLO_ACK` + `u16 version` + `u32 capabilities`

- Commands:
  - `0x10` `CREATE_WINDOW` + `u32 request_id` + UTF-8 title
  - `0x11` `SET_LABEL` + `u32 request_id` + UTF-8 text
  - `0x12` `SET_TEXT` + `u32 request_id` + UTF-8 text
  - `0x13` `ADD_BUTTON` + `u32 request_id` + `u8 id` + UTF-8 label
  - `0x14` `RUN` + `u32 request_id`
  - `0x15` `QUIT` + `u32 request_id`
- Responses:
  - `0x70` `OK` + `u32 request_id`
  - `0x71` `ERR` + `u32 request_id` + UTF-8 message
- Events:
  - `0x81` `BUTTON_CLICKED` + `u8 id`
  - `0x82` `CLOSED`
  - `0x83` `LOG` + UTF-8 text
  - `0x84` `TEXT_CHANGED` + UTF-8 text
  - `0x85` `KEY_DOWN` + `u32 keycode`
  - `0x86` `ERROR` + UTF-8 text

## Build (Linux)

Requirements: `gcc`, `make`, `pkg-config`, `libgtk-3-dev`, `Erlang/OTP`, `gleam`.

> Tested with **Gleam v1.17.0**.

```bash
make port
gleam build
make demo
```

If you're in an environment without an X server (CI/headless), force simulated mode:

```bash
MINIGUI_HEADLESS=1 make demo
```

## Build (Windows)

1. Compile the port:

```bash
make port
```

2. Run the demo:

```powershell
gleam build
gleam run -m demo
```

> Note: the Win32 code is inside `#ifdef _WIN32`.
