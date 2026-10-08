# Doodle Bug (VIC-20) — Enhanced Edition

A fully commented KickAssembler source for **Doodle Bug**, the Commodore VIC-20 maze game
(original © Mastertronic), rebuilt from a disassembly of the PAL/IKARI release and extended.
It runs on an **unexpanded** VIC-20 and fits in a single file: [`DoodleBug.asm`](DoodleBug.asm).

## The game

You are a bug in a walled garden. Eat every dot before the hunting "devils" catch you.
Spray bombs leave a cloud that kills any devil that walks into it (+100 points) — but the
cloud is dangerous to you as well. Revolving doors swing through 90 degrees when pushed.
The middle row wraps round from one side of the maze to the other.

| | |
|---|---|
| Title screen | **F1** number of devils (1–5) · **F3** speed (1–6) · **FIRE** start |
| In game | **Joystick** move · **FIRE + up/down/left** move and spray a bomb |
| Start | 5 lives, 5 bombs; +1 bomb (max 9) per cleared level |
| Levels | Three mazes cycle 1 → 2 → 3 → 1 …; each level adds a devil (up to 5), then the game speeds up |
| Scoring | A dot is worth 2–6 points (more devils = more points); a destroyed devil is 100 |

## Building

Requires [KickAssembler](http://theweb.dk/KickAssembler/) (Java) and, to run it, the VICE `xvic` emulator.

```bash
java -jar KickAss.jar DoodleBug.asm -o build/DoodleBug.prg
xvic build/DoodleBug.prg
```

The program loads at `$1001` with a BASIC stub (`10 SYS 4535`). The assembler stops with an
error if the entry point ever moves and the SYS address needs updating.

`START_MAZE` (near the top of the file) chooses which maze a new game begins on:
`0` = maze 1 (normal), `1` = maze 2, `2` = maze 3. It is currently set to **2** for testing.

## What is different from the original

* The cracker's extra BASIC line, leftover data and other unused bytes are removed
* The 440-byte maze is stored as a 56-byte wall bitmap plus a few rules; the rest is rebuilt at run time
* **Two new mazes** (each a bitmap in the same packed form), alternating by level
* Level number on the status row, title tune, level-complete jingle and a **GAME OVER** screen with its own tune
* Joystick reading fixed for emulators (the original compared the whole port byte, whose
  serial-bus bits depend on the drive/IEC state), a slower menu key repeat, a leftover BASIC banner
  on the title screen cleared, and a speed value that could wrap and make the game suddenly very slow

The `FIX` comments in the source mark each change.

## Memory

The source header contains the full memory map. In short: code and data fill `$1001–$1BF6`,
the custom character set is fixed at `$1C00–$1DD7`, and only about 9 bytes remain free.

## Editing the mazes

Each maze is a picture of 20 rows × 22 columns near the end of the source (`mazeRows1/2/3`).
Only the `#` walls are used directly; dots, blanks and door cells are rebuilt by rule, and the
assembler counts dots and finds the six doors automatically. A maze must follow a few rules
(one connected area, no dead ends even with any door swung, fully open row 9, six doors, open
start squares). The rules are listed in the comment above maze 2 in the source.

## Credits and rights

* Original game: **Doodle Bug**, © Mastertronic
* Disassembly, comments, new mazes, music and fixes: Tony Brice

This is a fan edition built from a disassembly of a commercial game. Make sure you have the
right to distribute it before publishing any build.
