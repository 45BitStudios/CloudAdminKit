# Game feel & audio

## 7. Game feel & effects (what the good games do)

- **Juice checklist:** screen shake (SKTUtils `SKAction+SpecialEffects` / `ShakerComponent` in glide), hit-stop (brief `speed = 0` on the world node), squash-and-stretch scale actions, particle bursts on every pickup/death, subtle parallax background layers (2–3 layers at different scroll rates), flash/blink on damage (`BlinkerComponent`).
- Timing curves matter: use `timingMode = .easeOut/.easeIn` or SKTUtils' custom timing functions instead of linear for nearly everything UI-facing.
- Scale difficulty over time with a single tunable curve (spawn interval, speed multipliers) driven off elapsed time or score, defined in one constants/tuning file — not inline magic numbers.

## 8. Audio

- Centralize audio in one service (Terranous `GameAudio` / SKTAudio): background music via `AVAudioPlayer` (loopable, volume-controllable, survives scene transitions), one-shot SFX via `SKAction.playSoundFileNamed` (cheap, but no volume control) or preloaded `AVAudioPlayer`s/`SKAudioNode` when volume/positional control is needed.
- Preload/warm sounds at startup; first `playSoundFileNamed` on a cold file causes a hitch.
- Persist mute/music settings (`UserDefaults`-backed settings object — Terranous's `GameSettings`).
- Configure `AVAudioSession` category deliberately (`.ambient` so user music keeps playing is the usual arcade choice).

