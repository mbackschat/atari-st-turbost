# Turbo ST

![Turbo ST Title Screen](misc/converted_images/TITLE.PNG)

**Reverse-engineering of a 1987 Atari ST racing game.**

Turbo ST is a pseudo-3D car racing game with a built-in track editor, originally published by Prism PLC with conversion by Capital Software Developments Ltd. It was programmed by Martin Backschat in Motorola 68000 assembly language.

This repository contains the fully commented source code, original game resources, and comprehensive documentation produced through reverse-engineering the game from its assembly source.

## The Game

- **Track Editor**: Design your own circuits on an 18x9 grid using 18 different track components (straights, curves, diagonals). Save and load tracks from disk.
- **Racing**: Race on your tracks with pseudo-3D perspective rendering, scrolling scenery, roadside billboards, and engine sound simulation.
- **Multiplayer**: 1-4 players in hot-seat mode, each racing the same track.
- **3 Sceneries**: Rising Sun/City, High Noon/City, Alps/Village - each with unique color palettes and skyline graphics.
- **High Scores**: Leaderboard for 1-lap races with name entry and a champion celebration screen.

### Controls

Uses **joystick port 1** (the right port on the Atari ST; the left port is the mouse).

| Input | Action |
|-------|--------|
| Joystick Up/Down | Accelerate / Brake |
| Joystick Left/Right | Steer |
| Fire + Up/Down | Shift gear up/down |
| Space | Pause |
| Undo (ESC) | Abort race |

## Repository Structure

```
src/                    68000 assembly source (fully commented)
  TURBOST.S               Complete game source (~5000 lines with comments)

game/                   Game assets loaded at runtime
  *.PI1                   Atari ST Degas images (title, dashboard, signs, etc.)
  *.SND, *.SEQ            Sound effects and music data
  DEFAULT, EASY, DEVIL    Pre-built track layouts with high scores (.TOP)
  TURBOST.PRG             Compiled game executable

doc/                    Reverse-engineering documentation
  MANUAL.md               User manual (controls, editor, gameplay, scoring)
  ANALYSIS.md             Technical deep-dive (architecture, algorithms, pseudocode)

misc/                   Supplementary material
  game_disks/             Original game disk images (.st) as sold
  screenshots/            In-game screenshots (editor, racing, explosion)
  converted_images/       PI1 game screens converted to PNG (modern format)
  TURBOST-Original.S      Original source code without annotated comments
  additional_material.zip Atari ST SDK docs, 68000 reference, and hardware
                          specs used during reverse-engineering
```

## Documentation

### [Game Manual](doc/MANUAL.md)

How to play: track editor usage, racing controls, gear system, scoring, multiplayer, scenery selection, and high score mechanics.

### [Technical Analysis](doc/ANALYSIS.md)

Comprehensive reverse-engineering analysis including:
- Program architecture and memory layout (371KB BSS for graphics buffers)
- 18 pseudocode blocks for all major algorithms (rendering, physics, sound, track generation)
- Atari ST hardware details: raster split palette trick, ROXR scenery pre-shifting, double buffering with vcounthi sync, Timer A digital music playback
- Full TOS/GEMDOS/XBIOS/AES/VDI/Line-A call inventory with official SDK symbol names
- Surprise findings: scenery palette swap bug, Kbdvbase stack bug

## Technical Highlights

The game demonstrates several impressive 68000 programming techniques for 1987:

- **Pseudo-3D road rendering** using perspective line repetition and curve accumulation
- **Raster split** for two independent 16-color palettes on one screen (sky + road)
- **16-copy scenery pre-shifting** using ROXR carry chains for smooth pixel scrolling (80KB lookup table)
- **Digital music playback** via MFP Timer A interrupts driving the YM2149 PSG through a 64-entry waveform table
- **movem.l PSG blast** writing 3 register/value pairs to the sound chip in a single instruction
- **BCD score arithmetic** using the 68000's SBCD instruction with X-flag borrow propagation

## Building

The original source assembles with the Atari ST `as68` assembler and links with `link68` (part of the Atari ST Developer Kit). The game requires an Atari ST with color monitor in low resolution (320x200, 16 colors).

To run the pre-built game, use an Atari ST emulator (e.g., Hatari, Steem) and load `resources/TURBOST.PRG` with the resource files in the same directory.

## Credits

- **Programming**: Martin Backschat
- **Graphics**: Nusrath J. Patel
- **Publisher**: Prism PLC (1987)
- **Conversion**: Capital Software Developments Ltd
- **Reverse-engineering & documentation**: Generated with assistance from Claude Code

## License

This reverse-engineering work (documentation, source comments, analysis) is released under the [MIT License](LICENSE).

The original game assets and source code are copyright (c) 1987 Prism PLC / Capital Software Developments Ltd.
