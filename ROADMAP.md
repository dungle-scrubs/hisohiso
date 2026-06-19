# Roadmap

## Voice-to-Text Enhancement Layer

Raw dictation is useful for capturing thoughts, but the output
often needs refinement before it's ready to use — and the *type*
of refinement depends entirely on *what it's for*.

### Two Modes

**1. Direct / Dump Mode**
Standard dictation → paste as-is. Fast, no processing.
This is what Hisohiso does today.

**2. Enhance Mode**
After dictating, a quick prompt appears:

> "What's this for?"

You answer (verbally or typed), and a model refines the message
accordingly — tone, structure, length — before you paste.

### Key Insight

The context layer shouldn't be app-dependent (e.g. "oh you're in
Gmail, so formal tone"). That's brittle and often wrong. Instead,
you *tell it* the intent on the fly:

- "This is a Slack message to a client"
- "This is a rough brief for a developer"
- "Just clean it up a little"

### Customization

- Trigger enhancement manually (not automatic)
- Optionally hit a custom API / model endpoint for the refinement
  step
- Iterable — refine, review, refine again before pasting

### Flow

```
Dictate → [Dump it] OR [Enhance it → "What's this for?" → Refined output] → Paste
```
