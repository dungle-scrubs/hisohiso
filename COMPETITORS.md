# Competitive Landscape

Last updated: 2026-03-05

## Summary

Hisohiso competes in the macOS voice-to-text space against four main
products. The market splits into two camps: **local-first tools** (Sotto,
HyperWhisper, Superwhisper) and **cloud-AI-powered assistants** (Wispr Flow).

Hisohiso is a commercial product differentiated by **local-first
processing, developer-friendly tooling (CLI/API), and unique features**
like speaker verification and wake word activation that no competitor
offers.

## Quick Comparison

| | Hisohiso | Sotto | HyperWhisper | Wispr Flow | Superwhisper |
|---|---|---|---|---|---|
| **Price** | TBD | $49 one-time | Free / $39 lifetime | $9.99/mo | $9.99/mo |
| **Platforms** | macOS | macOS | macOS, Windows (beta) | Mac, Win, iOS, Android | macOS |
| **Local processing** | ✅ Default | ✅ Default | ✅ + cloud hybrid | ❌ Cloud-only | ✅ Default |
| **Cloud fallback** | OpenAI, Groq | OpenAI, Groq | 12+ providers | Built-in (proprietary) | ❌ |
| **Transcription backends** | Parakeet v2/v3, WhisperKit | WhisperKit, Parakeet | Whisper variants, cloud APIs | Proprietary | Whisper variants |
| **Languages** | 100+ (Whisper), English (Parakeet) | 90+ | 100+ | 100+ | 100+ |
| **Best English WER** | 1.69% (Parakeet v2) | ~2% (Parakeet) | Varies by model | Unknown | Varies by model |
| **AI text rewriting** | ❌ | ❌ | ❌ | ✅ Auto-edits | ✅ AI modes |
| **Activation** | Globe key, hotkey, wake word | Push-to-talk hotkey | Hotkey | Hotkey | Hotkey |
| **Wake word** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **CLI / headless mode** | ✅ Full CLI + Unix socket API | ❌ | ❌ | ❌ | ❌ |
| **History** | ✅ Searchable + quick-paste | ✅ Recording history | ✅ | ✅ | ✅ |
| **Custom vocabulary** | ❌ | ✅ | ✅ | ✅ (personal dictionary) | ❌ |
| **Smart formatting** | ✅ Auto-caps, filler removal | ✅ | ✅ | ✅ (AI-powered) | ✅ |
| **File import** | ❌ | ✅ Audio files | ✅ Audio files | ❌ | ❌ |
| **Screen OCR** | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Speaker verification** | ✅ | ❌ | ❌ | ❌ | ❌ |

## Competitor Profiles

### Sotto

**URL:** <https://sotto.to>
**Pricing:** $49 one-time purchase

A one-person indie Mac app. Same tech stack — WhisperKit, Parakeet, native
Swift. Their pitch is "private dictation that just works." Consumer product
with no team features, no API, no platform ambitions. Going after the
individual Mac user who wants local transcription with a polished UI and
doesn't want a subscription.

**Strengths vs Hisohiso:**

- Custom vocabulary / dictionary for domain-specific terms
- Audio file import for transcribing recordings
- More polished onboarding and UI
- Cloud model support (OpenAI, Groq) as first-class feature

**Weaknesses vs Hisohiso:**

- No wake word activation
- No CLI or programmatic control
- No speaker verification

### HyperWhisper

**URL:** <https://www.hyperwhisper.com/en>
**Pricing:** Free tier (3 min/day) / $39 lifetime Pro

The kitchen-sink option. Supports everything — 12+ cloud providers, 30+
models, local and cloud, Mac and Windows beta, screen OCR, file import.
Free tier (3 min/day) funnels into a $39 lifetime purchase. Targeting the
prosumer/power user who wants maximum flexibility and model choice. More of
a "transcription workbench" than a focused product.

**Strengths vs Hisohiso:**

- Cross-platform (macOS + Windows beta)
- 12+ cloud API providers, 30+ models
- Screen OCR — reads on-screen text for context
- Custom vocabulary
- Audio file import
- Real-time streaming transcription
- Free tier available

**Weaknesses vs Hisohiso:**

- No wake word
- No CLI mode
- No speaker verification
- Free tier is very limited (3 min/day)

### Wispr Flow

**URL:** <https://wisprflow.ai>
**Pricing:** $9.99/mo (14-day free trial)

In a different category entirely. A cloud AI writing tool that uses voice
as the input method — it doesn't just transcribe, it rewrites speech into
polished text, adjusts tone per-app, and expands snippets. SOC 2 Type II
certified, enterprise customers include Clay, OpenAI, and Vercel.
Cross-platform (Mac, Windows, iOS, Android). Competes more with Grammarly
than with dictation tools. Going after knowledge workers and teams who
write all day — Slack, email, docs.

**Strengths vs Hisohiso:**

- AI auto-editing cleans up speech into polished prose
- Per-app tone adjustment (casual in Slack, formal in email)
- Snippet library for repeated phrases
- Cross-platform (Mac, Windows, iOS, Android)
- Enterprise-grade security (SOC 2 Type II)
- Personal dictionary learns your terminology

**Weaknesses vs Hisohiso:**

- Subscription-only ($9.99/mo)
- Cloud-dependent — no offline mode
- No wake word
- No CLI mode
- No speaker verification
- Privacy trade-off: all audio goes to cloud

### Superwhisper

**URL:** <https://superwhisper.com>
**Pricing:** $9.99/mo subscription

Sits between Sotto and Wispr Flow. Local processing like Sotto, but with
AI rewriting modes like Wispr Flow. Going after the individual professional
who wants dictation *plus* text transformation — dictate messy thoughts,
get clean prose back. Less enterprise ambition than Wispr Flow, more
feature-rich than Sotto.

**Strengths vs Hisohiso:**

- AI modes for different writing styles
- More mature product with broader awareness

**Weaknesses vs Hisohiso:**

- Subscription-only ($9.99/mo)
- macOS only (same as Hisohiso)
- No wake word
- No CLI mode
- No speaker verification

## Hisohiso's Differentiators

1. **Zero data exfiltration** — all processing on-device by default; no
   audio or text ever leaves the machine unless the user explicitly
   configures a cloud fallback.
2. **Speaker verification** — prevents unauthorized dictation; no
   competitor offers this.
3. **CLI + Unix socket API** — scriptable, automatable, integrates into
   developer workflows. Unique in the market.
4. **Wake word activation** — hands-free "hey computer" trigger; no
   competitor offers this.
5. **Parakeet v2 at 1.69% WER** — best-in-class English accuracy among
   local models.

## Gaps to Close

1. **Custom vocabulary** — Sotto and HyperWhisper both offer this;
   important for domain-specific terms (medical, legal, technical).
2. **AI text rewriting** — Wispr Flow and Superwhisper rewrite speech into
   polished text. Biggest feature gap.
3. **Audio file import** — Sotto and HyperWhisper can transcribe existing
   recordings.
4. **Snippet library** — Wispr Flow's text expansion for repeated phrases.
5. **Cross-platform** — HyperWhisper (Windows) and Wispr Flow (all
   platforms) have broader reach.

## Market Positioning

```
                    Local-first ←————————————→ Cloud-dependent
                         │                          │
             ─── Sotto ──┤                          │
                         │                          │
          ── HyperWhisper (hybrid) ─────────────────┤
                         │                          │
         ─── Hisohiso ───┤                   Wispr Flow
                         │                          │
         ── Superwhisper ┤                          │
                         │                          │
           Raw transcription ←———————————→ AI rewriting
```

Hisohiso sits in the local-first / raw transcription quadrant alongside
Sotto and Superwhisper. The unique features (speaker verification, wake
word, CLI/API) don't have a clean axis on this chart but are meaningful
differentiators regardless of target market.

### Where Hisohiso fits

In terms of actual functionality today, Hisohiso is closest to Sotto —
local-first Mac dictation, same backends, similar core experience. But
Hisohiso has things nobody else has: wake word, speaker verification,
and a full CLI/API.

The open question is whether to lean into those unique features to carve
out a distinct position, or compete head-on with Sotto/Superwhisper on
polish and features like custom vocabulary and AI rewriting. The unique
features point toward audiences the others aren't serving
(automation-heavy users, accessibility, privacy-strict environments),
but that's not a commitment yet — just where the product naturally
diverges from the field.

## Potential Markets

- **Individual professionals** — writers, developers, anyone who dictates
  daily and cares about privacy and accuracy
- **Corporate / enterprise** — regulated industries where data can't leave
  the device (HIPAA, finance, legal); CLI/API enables IT automation
- **Accessibility** — wake word and hands-free activation for users with
  motor impairments or hands-busy workflows
- **Developers** — CLI-first users who want scriptable dictation

## Pricing Landscape

| Model | Examples | Typical price |
|-------|----------|---------------|
| One-time purchase | Sotto ($49), HyperWhisper ($39) | $39–$49 |
| Subscription | Wispr Flow ($9.99/mo), Superwhisper ($9.99/mo) | $10/mo |
