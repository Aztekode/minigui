# Releasing minigui (checklist)

This repository publishes **two things**:

1. **Gleam package (Hex / Gleam Packages)**: Gleam code + Erlang helper.
2. **Native assets (GitHub Releases)**: `minigui` (Linux x64) and `minigui.exe` (Windows x64) + `.sha256`.

The library downloads the port from:

```
https://github.com/Aztekode/minigui/releases/download/v<VERSION>/<asset>
```

Therefore, **the git tag MUST ALWAYS be `vX.Y.Z`** and the package version must be **`X.Y.Z`**.

---

## 0) Preparation

- Ensure `gleam.toml` has the final version `X.Y.Z`.
- Update `CHANGELOG.md`.
- (Optional) run the headless demo:

```bash
make port
MINIGUI_HEADLESS=1 gleam run -m demo
```

---

## 1) Create tag and release (native assets)

1. Commit the version:

```bash
git add -A
git commit -m "Release vX.Y.Z"
```

2. Tag:

```bash
git tag vX.Y.Z
git push origin main --tags
```

3. GitHub Actions will run the `release.yml` workflow and attach:
   - `minigui` + `minigui.sha256`
   - `minigui.exe` + `minigui.exe.sha256`

> Note: the workflow fails if the `vX.Y.Z` tag does not match the `X.Y.Z` version in `gleam.toml`.

---

## 2) Publish the package to Hex / Gleam Packages

On the machine where you have Hex credentials configured:

```bash
gleam publish
```

If you are going to use CI to publish, you will need to configure the corresponding token (not included in this repo).
