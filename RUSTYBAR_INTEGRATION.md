# RustyBar Integration

Hisohiso sends recording state to RustyBar via Unix socket IPC.

## Protocol

```
Socket: /tmp/rustybar.sock
Command: set <module_id> <state>
Example: set hisohiso recording
```

## States

| State | Meaning |
|-------|---------|
| `idle` | Not recording (module hidden) |
| `recording` | Actively capturing audio |
| `transcribing` | Processing with WhisperKit |
| `error` | Transcription failed |

## RustyBar Changes Required

### 1. New file: `src/gpui_app/modules/external.rs`

```rust
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use gpui::*;
use crate::theme::Theme;
use super::GpuiModule;

lazy_static::lazy_static! {
    static ref EXTERNAL_STATES: Arc<RwLock<HashMap<String, String>>> =
        Arc::new(RwLock::new(HashMap::new()));
}

pub fn set_external_state(id: &str, state: &str) {
    let mut states = EXTERNAL_STATES.write().unwrap();
    states.insert(id.to_string(), state.to_string());
}

pub fn get_external_state(id: &str) -> Option<String> {
    let states = EXTERNAL_STATES.read().unwrap();
    states.get(id).cloned()
}

pub struct ExternalModule {
    id: String,
    states: HashMap<String, StateConfig>,
    default_state: String,
}

struct StateConfig {
    icon: String,
    color: Option<String>,
    text: Option<String>,
}

impl ExternalModule {
    pub fn new(config: &toml::Value) -> Self {
        let id = config.get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("external")
            .to_string();

        let mut states = HashMap::new();
        if let Some(state_table) = config.get("states").and_then(|v| v.as_table()) {
            for (state_name, state_config) in state_table {
                states.insert(state_name.clone(), StateConfig {
                    icon: state_config.get("icon")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string(),
                    color: state_config.get("color")
                        .and_then(|v| v.as_str())
                        .map(String::from),
                    text: state_config.get("text")
                        .and_then(|v| v.as_str())
                        .map(String::from),
                });
            }
        }

        let default_state = config.get("default_state")
            .and_then(|v| v.as_str())
            .unwrap_or("idle")
            .to_string();

        Self { id, states, default_state }
    }

    fn current_state(&self) -> String {
        get_external_state(&self.id).unwrap_or_else(|| self.default_state.clone())
    }
}

impl GpuiModule for ExternalModule {
    fn id(&self) -> &str {
        &self.id
    }

    fn render(&self, theme: &Theme) -> AnyElement {
        let state = self.current_state();
        let config = self.states.get(&state);

        let icon = config.map(|c| c.icon.as_str()).unwrap_or("");
        let text = config.and_then(|c| c.text.as_deref()).unwrap_or("");
        let color = config
            .and_then(|c| c.color.as_deref())
            .and_then(|c| parse_color(c))
            .unwrap_or(theme.foreground);

        // Hidden when idle with no icon/text
        if state == "idle" && icon.is_empty() && text.is_empty() {
            return div().into_any();
        }

        div()
            .flex()
            .items_center()
            .gap_1()
            .child(div().child(icon).text_color(color))
            .when(!text.is_empty(), |d| d.child(div().child(text).text_color(color)))
            .into_any()
    }

    fn update(&mut self) -> bool {
        true  // Always dirty since state comes from IPC
    }
}
```

### 2. Extend IPC handler in `src/main.rs`

Add to the match statement in the IPC command handler:

```rust
line if line.starts_with("set ") => {
    let parts: Vec<&str> = line.splitn(3, ' ').collect();
    if parts.len() >= 3 {
        let module_id = parts[1];
        let state = parts[2].trim();
        crate::gpui_app::modules::external::set_external_state(module_id, state);
        cx.refresh();  // Trigger redraw
    }
    "OK"
}
```

### 3. Register in module factory

In `src/gpui_app/modules/mod.rs`, add:

```rust
mod external;

// In create_module():
"external" => Box::new(external::ExternalModule::new(config)),
```

### 4. Add dependency to `Cargo.toml`

```toml
[dependencies]
lazy_static = "1.4"
```

## Config Example

Add to `~/.config/rustybar/config.toml`:

```toml
[[modules.right.left]]
type = "external"
id = "hisohiso"
default_state = "idle"

[modules.right.left.states.idle]
icon = ""

[modules.right.left.states.recording]
icon = "●"
color = "#ff5555"

[modules.right.left.states.transcribing]
icon = "◐"
color = "#f1fa8c"

[modules.right.left.states.error]
icon = "✗"
color = "#ff5555"
```

## Testing

```bash
# Start RustyBar
cargo run --release

# Test IPC manually
echo "set hisohiso recording" | nc -U /tmp/rustybar.sock
echo "set hisohiso transcribing" | nc -U /tmp/rustybar.sock
echo "set hisohiso idle" | nc -U /tmp/rustybar.sock
```
