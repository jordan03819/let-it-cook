# Audio credits

Every sound in this folder is **CC0** (public domain): free for commercial and
personal use, no attribution required. The credits below are given because the
authors deserve them, and so the provenance of each file is on record.

Files were trimmed, converted to mono Ogg Vorbis and level-matched for this
game; the originals are linked.

| file | used for | source | author | licence |
|---|---|---|---|---|
| `fire_crackle.ogg` | burning-ambience loop | [Fireplace Sound loop](https://opengameart.org/content/fireplace-sound-loop) (trimmed to 8 s) | pagdev | CC0 |
| `ignite.ogg` | a building catching (swell from the same recording) | as above | pagdev | CC0 |
| `rain.ogg` | torrential-rain ambience loop | [Rain (loopable)](https://opengameart.org/content/rain-loopable) (first loop, 12 s) | ylmir | CC0 |
| `wind_gust.ogg` | Wind Gust ability | [wind whoosh loop](https://opengameart.org/content/wind-whoosh-loop) | sketchman3 | CC0 |
| `helicopter.ogg` | helicopter water-drop threat | [Helicopter Sounds](https://opengameart.org/content/helicopter-sounds) (trimmed to 6 s) | aquinn | CC0 |
| `siren.ogg` | firefighter wave arrival | [30 CC0 SFX loops](https://opengameart.org/content/30-cc0-sfx-loops) — `alarm_02` | rubberduck | CC0 |
| `last_spark.ogg` | "Last Spark" smoulder cue | same pack — `alarm_03` | rubberduck | CC0 |
| `shaman_cue.ogg` | shaman ritual cue | same pack — `weird_02` | rubberduck | CC0 |
| `explosion.ogg` | explosive barrels (pitched down, shaped) | same pack — `noise_03` | rubberduck | CC0 |
| `splash.ogg` | water hitting a building | [40 CC0 water / splash / slime SFX](https://opengameart.org/content/40-cc0-water-splash-slime-sfx) — `splash_03` | rubberduck | CC0 |
| `collapse.ogg` | a building burning out | [35 wooden cracks/hits/destructions](https://opengameart.org/content/35-wooden-crackshitsdestructions) | qubodup | CC0 |

## How they are wired

`scenes/sound_manager.gd` loads these by name (`AUDIO_FILES`, plus
`LOOPING_SOUNDS` for the three ambiences) and falls back to its own synthesiser
for anything missing, so the game still makes sound if a file is dropped from a
build. To swap a sound, replace the file — the name is the contract, not the
recording.
