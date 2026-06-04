# Changelog

## v0.1.0

- Instalación “sin toolchain”: descarga automática del port desde GitHub Releases, con cache por usuario.
- Protocolo v1 con handshake (`HELLO`/`HELLO_ACK`) y `OK/ERR` por `request_id`.
- Backends:
  - Windows: Win32 (Window + Label + TextBox + Button)
  - Linux: GTK3 (Window + Label + TextBox + Button)
- API de Gleam basada en `Result` y comandos con ACK.

