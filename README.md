# AlloyX DOOM: *can it run DOOM?*

[Português (Brasil)](README-BR.md)

**Yes, and it's playable.** DOOM runs with its **engine written in Apex**, including an official WAD parser, fixed-point math, and a raycaster. [AlloyX](https://github.com/colatusso/alloyx) transpiles the Apex to Java, which runs **in real time in a graphical window** (color, ~60 fps) with keyboard controls.

The game loads **E1M1 (Hangar)** directly from the official `DOOM1.WAD` (id Software shareware, `md5 f0cefca49926d00903cf57551d901abe`).

## Play (graphics, real time)

Requires a JDK, Python 3, `allx` on your `PATH`, and the sibling `apex-local` project built. Place a legitimate copy of the shareware `doom1.wad` in this directory. Neither the WAD nor the derived `WadData.cls` is distributed in this repository. The first `./play.sh` run generates `WadData.cls` automatically.

```bash
./play.sh
```

This compiles the Apex engine to `.class` files through `allx`, compiles the Java host, and opens the game window.

**Controls:** `W`/`S` move forward/backward; `A`/`D` or arrow keys turn; `Q`/`E` strafe; `Ctrl` fires; `SPACE` uses/opens doors and switches; `2`-`7` select weapons; `TAB` opens the automap; `ESC` quits.

Monsters wake up only when they see you nearby (line of sight), and many of their shots miss. `TAB` overlays the actual E1M1 map.

There are **multiple levels**: E1M1 and E1M2 are loaded from `DOOM1.WAD`. The exit switch moves to the next map while preserving health, weapons, and ammo. Keys reset for each level, as in DOOM.

The DOOM gameplay loop runs in the Apex engine:

- **6 weapons** (pistol, shotgun, chaingun, rocket launcher, plasma gun, BFG) with WAD-driven data, their own ammo types (bullets, shells, rockets, cells), damage, fire rates, and sounds. Select them with `2`-`7` or collect them in the map; the **ARMS** panel updates accordingly.
- **Blue, yellow, and red keys**. Locked doors open only with the matching key.
- **Animated doors** opened with `SPACE`, height-aware collision for tall steps and closed doors, and a camera that follows each sector's floor height.
- **Platforms and lifts** triggered by crossing their lines, exit switches used with `SPACE`, and lowering floors, all driven by WAD line and sector tags.
- **E1M1 pickups** for weapons, ammo, health, and armor, with behavior based on the WAD thing type.
- **29 monsters** (zombiemen, shotgun guys, imps) with eight viewing angles. They chase, animate while walking, shoot back, and play death animations that leave corpses. Imps launch flying fireballs. Zombiemen drop five-bullet clips, and shotgun guys drop shotguns.
- **Player health and respawn**, with a red flash when taking damage.
- **WAD-based HUD** using the original STBAR, ammo, health, armor, the ARMS panel, and Doomguy's face with five damage levels.
- **Sector rendering** with a portal walker and actual floor/ceiling heights: steps, door frames, window frames, and sky in open areas.
- **Sound** from WAD SFX, decoded from DMX to PCM in Apex. The E1M1 music is converted from MUS to MIDI by the generator and loops during play. The engine queues events; the Java host handles audio I/O, just as it displays the framebuffer.
- **Textured walls and steps** with the actual upper/lower/middle textures, perspective-rendered sector floors and ceilings, per-sector lighting, and z-buffered sprites.

The resizable window starts at **1200×750**. Internal resolution is 400×250, in the style of DOOM.

> The **engine is 100% Apex** (`Doom.cls` and `Wad.cls`). The Java host (`Game.java`) only opens the window, reads the keyboard, and draws the RGB framebuffer computed by Apex each frame. At 320×200, the engine runs internally at approximately 2,000 fps; the game loop caps it at 60 fps.

### Why not use plain `allx run`?

`allx run` is one-shot: it executes a method and exits. It writes text to stdout, without a continuous input loop or graphical output, and each invocation takes about 0.5 seconds. For real-time play, the Apex engine is transpiled once and run inside a real-time Java host. The game logic remains in Apex; Java only handles the window, keyboard, display, and audio I/O.

## Bonus: the same Apex engine through `allx run` (text mode)

```bash
allx run Doom.cls --method Doom.automap   # E1M1 top-down map using the actual geometry
allx run Doom.cls --method Doom.fpv       # one first-person frame in ASCII
allx run Doom.cls --method Doom.demo      # autonomous 160-frame ASCII walkthrough
./run.sh                                  # animated ASCII walkthrough in the terminal
```

## How it works

```text
DOOM1.WAD (official)
  |  tools/wad2apex.py (Apex has no file I/O; this generator acts as a Static Resource)
  v
WadData.cls            Minimal PWAD for E1M1/E1M2 (THINGS/LINEDEFS/SIDEDEFS/VERTEXES/SECTORS
  |                    and sine lookup table), embedded in base64 chunks below Java's 64 KB
  |                    string-literal limit
  v
Wad.cls   (Apex)       WAD parser: header -> directory -> lumps; base64 decoding; LE int16/int32
  v
Doom.cls  (Apex)       Portal walker: traverses real linedefs in distance order per column;
  |                    renders floors/ceilings at sector heights, steps, sky, textures
  |                    (PLAYPAL, TEXTURE1/patches, flats), collision grid, and an RGB
  |                    framebuffer via init()/stepFrame(cmd)
  v
allx (transpile+javac) Apex -> compiled Java in .apexcache/*.class
  v
Game.java (host)       JFrame, BufferedImage, and keyboard; calls stepFrame() at 60 fps
  |                    and displays the framebuffer
```

`Wad.cls` parses the actual WAD and matches the E1M1 reference geometry: **467 vertices, 475 linedefs, 648 sidedefs, 85 sectors, player start at (1056, -3616, 90°).**

## Runtime limitations handled in Apex through AlloyX

| Limitation | Solution |
|---|---|
| No usable file I/O, `Blob`, or `EncodingUtil` | `wad2apex.py` embeds WAD bytes as base64; `Wad.decodeB64` decodes them in Apex |
| No `Long`, `L` literals, or Integer-to-Long widening | Use 32-bit integers; scale ray directions by `/256` to keep cross products below 2.1 billion |
| Case-insensitive Apex identifiers | Local names must not collide with fields or constants (`s` vs `S=16384`, `gW` vs `gw`). A loop such as `for (var s=1; S<steps; S++)` may never run after transpilation. Rename conflicting locals, for example `si`, `ls`, or `gunW`. |
| No `Math.sin/cos/sqrt` (only `mod/abs/min/max/round/random`) | Embed a 1,024-sample sine lookup table scaled by 16,384 as a `SINE` WAD lump; use Newton's method for integer square root |
| No bitwise or shift operations (`<<`, `>>`, `&`, `%`) | Use arithmetic such as `*64`, `/`, and `Math.mod` |
| `String.charAt` returns `char`, not `Integer` | `s.charAt(i) + 0` promotes it to an integer |
| Local variables use `var` and Java infers their type | Keep right-hand expressions integral to avoid `Decimal` (for example, `2.0` becomes `Decimal`) |
| In text mode, `'\n'` does not produce a newline | Emit one scanline per `System.debug`; `run.sh` strips the `DEBUG\|` prefix |

## Regenerate `WadData.cls` (or use another map or WAD)

```bash
python3 tools/wad2apex.py doom1.wad E1M1,E1M2 --out WadData.cls
```

`doom1.wad` is the official shareware WAD. The generator also accepts another locally supplied IWAD/PWAD and extracts available maps; `Wad.cls` parses them normally.

## Files

- `Doom.cls`: raycaster, graphics API (`init`/`stepFrame`), automap, and ASCII walkthrough (Apex)
- `Wad.cls`: WAD parser, base64 decoder, and little-endian reader (Apex)
- `WadData.cls`: **generated locally and excluded from Git**; map PWAD encoded as base64
- `Game.java`: real-time Java host (window, keyboard, display)
- `play.sh`: compiles everything and starts the game
- `run.sh`: terminal player for the ASCII walkthrough
- `tools/wad2apex.py`: generator that reads the official WAD and produces `WadData.cls`
- `doom1.wad`: official shareware IWAD, supplied locally and excluded from Git

## License and trademarks

The code in this project is licensed under **GPL-3.0-or-later**. See [LICENSE](LICENSE) and [NOTICE](NOTICE); the latter also credits the adapted Chocolate Doom MUS-to-MIDI converter. AlloyX is a separate project with its own license.

DOOM and its data belong to their respective rights holders. The WAD, graphics, sounds, and data generated from them are not included in this repository. This independent project is not affiliated with id Software, Bethesda, or Salesforce.
