# minigui

`minigui` es una biblioteca experimental para crear interfaces gráficas desde **Gleam (target Erlang)** usando un **port externo en C** (nativo).

## Estado / alcance

- **Windows**: backend **Win32** (ventana + label + textbox + botón).
- **Linux**: backend **GTK3** (ventana + label + textbox + botón).
- **macOS**: por ahora solo **modo headless** (simulado).

> Nota: en Linux el binario `minigui` enlaza con GTK3, por lo que el sistema debe tener GTK3 disponible en runtime (en desktops es común; en servidores minimalistas puede requerir instalar paquetes).

El objetivo es mantener una API pequeña y estable en Gleam, y permitir backends nativos por plataforma.

## Releases / publicación

Ver el checklist: [`RELEASING.md`](./RELEASING.md)

## Instalación (Gleam Packages)

```bash
gleam add minigui
```

### “Sin dependencias de build” (binario precompilado)

Para evitar que tus usuarios tengan que instalar un compilador C o headers (`libx11-dev`, etc.), `minigui` está pensado para usar un **ejecutable precompilado** como puente (un *port*) y descargarlo automáticamente a `priv/` en el primer uso.

Por defecto construye la URL así:

```
https://github.com/Aztekode/minigui/releases/download/v<version>/<asset>
```

Donde `<version>` sale del `vsn` del paquete (ej. `0.1.0`) y `<asset>` depende del OS/arquitectura, por ejemplo:

- `minigui.exe` (Windows x64)
- `minigui` (Linux x64)

Puedes sobreescribir la base de descargas con:

```bash
MINIGUI_RELEASE_BASE_URL="https://github.com/Aztekode/minigui/releases/download/v0.1.0"
```

Si prefieres un enlace exacto tipo `.../minigui.exe`, puedes fijar la URL completa:

```bash
MINIGUI_PORT_URL="https://github.com/Aztekode/minigui/releases/download/v0.1.0/minigui.exe"
```

Opciones de seguridad/cache:

- Por defecto, `minigui` **requiere** que exista `minigui(.exe).sha256` y valida el SHA256.
- `MINIGUI_REQUIRE_SHA=0`: desactiva la validación (no recomendado).
- El binario se cachea por usuario (Linux: `~/.cache/minigui/<version>/`, Windows: `%LOCALAPPDATA%\\minigui\\<version>\\`).

> Requisito de runtime: una instalación “completa” de Erlang/OTP que incluya las aplicaciones estándar `inets` + `ssl` (normalmente ya vienen con OTP; en algunas distros Linux pueden venir en paquetes separados).

## Protocolo (v1)

El port se abre con `open_port(..., [{packet, 2}, binary, ...])`.

- Handshake:
  - `0x00` `HELLO` + `u16 version`
  - `0xF0` `HELLO_ACK` + `u16 version` + `u32 capabilities`

- Comandos:
  - `0x10` `CREATE_WINDOW` + `u32 request_id` + título UTF-8
  - `0x11` `SET_LABEL` + `u32 request_id` + texto UTF-8
  - `0x12` `SET_TEXT` + `u32 request_id` + texto UTF-8
  - `0x13` `ADD_BUTTON` + `u32 request_id` + `u8 id` + etiqueta UTF-8
  - `0x14` `RUN` + `u32 request_id`
  - `0x15` `QUIT` + `u32 request_id`
- Respuestas:
  - `0x70` `OK` + `u32 request_id`
  - `0x71` `ERR` + `u32 request_id` + mensaje UTF-8
- Eventos:
  - `0x81` `BUTTON_CLICKED` + `u8 id`
  - `0x82` `CLOSED`
  - `0x83` `LOG` + texto UTF-8
  - `0x84` `TEXT_CHANGED` + texto UTF-8
  - `0x85` `KEY_DOWN` + `u32 keycode`
  - `0x86` `ERROR` + texto UTF-8

## Compilar (Linux)

Requisitos: `gcc`, `make`, `pkg-config`, `libgtk-3-dev`, `Erlang/OTP`, `gleam`.

> Probado con **Gleam v1.17.0**.

```bash
make port
gleam build
make demo
```

Si estás en un entorno sin servidor X (CI/headless), fuerza el modo simulado:

```bash
MINIGUI_HEADLESS=1 make demo
```

## Compilar (Windows)

1. Compila `c_src/minigui_port.c` a `priv/minigui_port.exe` (MSVC o mingw).
2. Ejecuta el demo:

```powershell
gleam build
gleam run -m demo
```

> Nota: el código Win32 está dentro de `#ifdef _WIN32`.
