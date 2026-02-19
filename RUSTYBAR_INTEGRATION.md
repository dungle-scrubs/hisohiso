# Sinew Integration

Hisohiso can publish dictation state to Sinew using Sinew IPC + an `external` module.

> This file keeps its legacy name for compatibility, but the integration target is **Sinew**.

## IPC Endpoint

- Socket: `${XDG_RUNTIME_DIR:-/tmp}/sinew.sock`
- Command style: `set <module_id> key=value [key=value ...]`

## Commands sent by Hisohiso

Hisohiso targets module id `hisohiso`:

```bash
set hisohiso drawing=off
set hisohiso drawing=on label=● color=#ff5555
set hisohiso drawing=on label=◐ color=#f9e2af
set hisohiso drawing=on label=✗ color=#ff5555
```

State mapping:

| Hisohiso state | Sinew command |
|---|---|
| `idle` | `set hisohiso drawing=off` |
| `recording` | `set hisohiso drawing=on label=● color=#ff5555` |
| `transcribing` | `set hisohiso drawing=on label=◐ color=#f9e2af` |
| `error` | `set hisohiso drawing=on label=✗ color=#ff5555` |

## Sinew config example

Add an external module with id `hisohiso`:

```toml
[[modules.right.left]]
type = "external"
id = "hisohiso"
label = ""
drawing = false
```

Then reload Sinew:

```bash
sinew-msg reload
```

## Manual testing

```bash
# List modules and verify `hisohiso` exists
sinew-msg list

# Simulate states
sinew-msg set hisohiso drawing=on label=● color=#ff5555
sinew-msg set hisohiso drawing=on label=◐ color=#f9e2af
sinew-msg set hisohiso drawing=off
```
