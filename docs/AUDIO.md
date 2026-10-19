# Tumbang Henyo: audio list

Every sound effect is a file in `art/Audio/sfx/`, named after the sound.
`Sfx.play("name")` plays `art/Audio/sfx/name.wav` (or `.ogg` / `.mp3`).
Numbered files (`step_1`, `step_2`, ...) are variants picked at random.

**To replace a sound:** drop a new file with the same name in the folder.
**To add a missing one** (the voice lines below): just add the file. The game
already calls these names and stays silent until the file exists.

The generated sounds come from `tools/make_sfx.py`
(`python tools/make_sfx.py art/Audio/sfx` rebuilds them).

Status: **made** = generated and in the game. **needs file** = hooked up,
waiting for a recording or a composed track.

## UI (every screen)

| Sound | When it plays | Status |
|---|---|---|
| ui_hover | Mouse moves onto any button | made |
| ui_click | Any button pressed | made |
| ui_back | Back / Close / Cancel / "<" buttons | made |
| ui_error | Clicking a disabled button (can't afford, locked) | made |
| ui_tick | Sliders moving, checkboxes | made |
| ui_whoosh | Main menu camera moving to another panel | made |
| ui_pop | Tip cards and tutorial cards popping in | made |
| ui_pause | Pause menu opens | made |
| ui_buy | Shop purchase ("ka-ching") | made |
| ui_equip | Character / tsinelas equipped; tutorial "Nice!" | made |
| coin | Settings SFX slider let go (volume preview) | made |
| achievement | Achievement popup | made |
| join | A student joins your class (host) / you join a class | made |
| whistle | Host presses Start in a class game | made |

## Quiz

| Sound | When it plays | Status |
|---|---|---|
| quiz_open | Question card swishes up | made |
| tick / tick_urgent | Last 5 seconds of the timer (urgent for the last 3) | made |
| correct / wrong | Answer right / wrong | made (existing mp3s) |
| timeout | Time ran out (buzzer) | made |
| hint | Hint bought (sparkle) | made |
| coin | Tansan earned (right answer, round clear, victory) | made |

## Throw

| Sound | When it plays | Status |
|---|---|---|
| charge (loop) | Holding the throw; pitch follows the power gauge | made |
| throw | Tsinelas leaves your hand (harder = sharper) | made |
| wind (loop) | On the throw line in windy rounds; louder in strong wind | made |
| slap_ground | A tsinelas first hits the ground (yours or a taya's) | made |
| lata_hit | Lata hit hard (clank + bounce rattle) | made |
| lata_set | Lata bouncing/rolling (soft clinks); a taya stands it back up | made |
| bonk | Your tsinelas hits a taya | made |
| miss | "Sablay!" | made |
| bullseye | Perfect shot slow-mo (boom + sting) | made |

## Run and the tayas

| Sound | When it plays | Status |
|---|---|---|
| step_1..4 | Footsteps (faster and louder when sprinting) | made |
| jump / land | Jump, and landing from a fall | made |
| exhausted | Energy runs out (out of breath) | made |
| alert | A taya winds up a throw (the "!" warning) | made |
| throw | A taya throws (from where the taya is) | made |
| slap | A tsinelas hits you ("PAK!") | made |
| tagged | "Taya ka!" | made |
| round_clear | Round cleared (fanfare) | made |
| banner | Big banners ("6:00 PM", "Time's up!", victory) | made |

## Mama's round and the end

| Sound | When it plays | Status |
|---|---|---|
| bell | 6:00 PM banner | made |
| mama_sting | Mama arrives | made |
| throw_heavy | Mama throws a hanger or walis | made |
| clatter | Hanger / walis lands (walis plays lower) | made |
| slap | A hanger or walis hits you (lower pitch) | made |
| tick / tick_urgent | Last 10 seconds of the run home | made |
| palo | Mama catches you | made |
| timeout | Too late | made |
| victory | Made it home (the game is won) | made |
| game_over | Out of Awra | made |

## Ambience

| Sound | When it plays | Status |
|---|---|---|
| crickets (loop) | All game long; fades up as the sky gets dark | made |

## Voices (record these)

Short, punchy, a little exaggerated. Mono WAV or OGG, peaks around -3 dB,
no silence before the word. Filipino/Taglish delivery.

| File name | Line | Who / when |
|---|---|---|
| voice_tumba | "Tumba!" | Player, the lata falls |
| voice_takbo | "Takbo!" | Player, start of the run |
| voice_aray | "Aray!" | Player, hit by a tsinelas / hanger |
| voice_taya_ka | "Taya ka!" | Taya, tags you |
| voice_mama_halika | "Hoy! Halika dito!" | Mama, starts chasing / throws |
| voice_mama_hoy | "Hoy!" | Mama, throws |
| voice_mama_lagot | "Lagot ka!" | Mama, throws |
| voice_mama_uwi | "Uwi na!" | Mama, throws |
| voice_mama_palo | "Palo ka sa'kin!" (or a loud "Ikaw talaga!") | Mama, catches you |

Tip: record 2-3 takes of each and save them as `voice_aray_1`, `voice_aray_2`, ...
and the game picks one at random.

## Music (compose / license these)

| File | What | Status |
|---|---|---|
| art/Audio/Bg music default.mp3 | Menu (and game, for now) | exists |
| art/Audio/music/game.ogg | Gameplay loop: light, playful, OPM/kalye feel, ~100-110 BPM | needs file (falls back to the menu song) |
| art/Audio/music/mama_chase.ogg | Mama's chase: tense, faster, ~140 BPM, 30 s+ loop | needs file (falls back to the gameplay song) |

Loop points: export OGG files with clean loops (start and end on the beat).
The game sets them to loop by itself.
