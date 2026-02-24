# Sinew Integration

Hisohiso publishes dictation state and audio levels to a custom Sinew module
that renders a waveform in the menu bar.

## Architecture

Sinew has a dedicated `hisohiso` module type (not a generic `external` module).
The module runs its own Unix socket listener and renders a native waveform with
state-dependent colors and animations.

```
┌─────────────┐    Unix socket    ┌──────────────────┐
│  Hisohiso   │ ──────────────── │  Sinew hisohiso  │
│ SinewBridge │   /tmp/hisohiso  │     module       │
│             │   -sinew.sock    │  (waveform UI)   │
└─────────────┘                  └──────────────────┘
```

When the Sinew module is active, Hisohiso's floating pill is suppressed.
When Sinew is not running, the floating pill appears at the bottom of the
screen as a fallback.

## IPC Protocol

- Socket: `/tmp/hisohiso-sinew.sock`
- Commands: newline-terminated strings

### Commands

| Command | Description |
|---------|-------------|
| `state idle` | Idle — subtle breathing animation |
| `state recording` | Recording — live waveform from audio levels |
| `state transcribing` | Transcribing — pulsing animation |
| `state error` | Error — flat red bars |
| `levels 50,60,70,80,70,60,50` | Audio levels (7 bars, 0–100) |

## Sinew Config

Add the hisohiso module to `~/.config/sinew/config.toml`:

```toml
[[modules.right.left]]
type = "hisohiso"
```

Position `right.left` places it on the right side of the bar, aligned left
(next to the notch on MacBooks).

Then reload Sinew:

```bash
sinew-msg reload
```

## Manual Testing

```bash
# Verify module is registered
sinew-msg list | grep hisohiso

# Simulate states (requires socat or similar)
echo "state recording" | socat - UNIX-CONNECT:/tmp/hisohiso-sinew.sock
echo "levels 20,40,80,100,80,40,20" | socat - UNIX-CONNECT:/tmp/hisohiso-sinew.sock
echo "state transcribing" | socat - UNIX-CONNECT:/tmp/hisohiso-sinew.sock
echo "state idle" | socat - UNIX-CONNECT:/tmp/hisohiso-sinew.sock
```

## Pill Suppression Logic

`SinewBridge.shouldShowFloatingPill` returns `true` only when:
- The user explicitly enabled the pill in preferences, OR
- The hisohiso Sinew module socket does not exist (Sinew is not running)

Availability is re-checked on every state change so the pill adapts
dynamically to Sinew starting or stopping.
