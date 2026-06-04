# Changelog

## v0.1.0

- Toolchain-free installation: automatic port download from GitHub Releases, with per-user cache.
- v1 protocol with handshake (`HELLO`/`HELLO_ACK`) and `OK/ERR` per `request_id`.
- Backends:
  - Windows: Win32 (Window + Label + TextBox + Button)
  - Linux: GTK3 (Window + Label + TextBox + Button)
- Gleam API based on `Result` and commands with ACK.
