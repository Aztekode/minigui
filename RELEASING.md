# Publicación de minigui (checklist)

Este repositorio publica **dos cosas**:

1. **Paquete Gleam (Hex / Gleam Packages)**: código Gleam + Erlang helper.
2. **Assets nativos (GitHub Releases)**: `minigui` (Linux x64) y `minigui.exe` (Windows x64) + `.sha256`.

La librería descarga el port desde:

```
https://github.com/Aztekode/minigui/releases/download/v<VERSION>/<asset>
```

Por lo tanto, **el tag de git SIEMPRE debe ser `vX.Y.Z`** y la versión del paquete debe ser **`X.Y.Z`**.

---

## 0) Preparación

- Asegúrate de que `gleam.toml` tenga la versión final `X.Y.Z`.
- Actualiza `CHANGELOG.md`.
- (Opcional) corre el demo en headless:

```bash
make port
MINIGUI_HEADLESS=1 gleam run -m demo
```

---

## 1) Crear tag y release (assets nativos)

1. Commit de la versión:

```bash
git add -A
git commit -m "Release vX.Y.Z"
```

2. Tag:

```bash
git tag vX.Y.Z
git push origin main --tags
```

3. GitHub Actions ejecutará el workflow `release.yml` y adjuntará:
   - `minigui` + `minigui.sha256`
   - `minigui.exe` + `minigui.exe.sha256`

> Nota: el workflow falla si el tag `vX.Y.Z` no coincide con la versión `X.Y.Z` en `gleam.toml`.

---

## 2) Publicar el paquete en Hex / Gleam Packages

En la máquina donde tengas configuradas credenciales de Hex:

```bash
gleam publish
```

Si vas a usar CI para publicar, tendrás que configurar el token correspondiente (no se incluye en este repo).

