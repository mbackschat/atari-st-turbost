# Turbo ST - Technical Analysis

## 1. Overview

Turbo ST is an Atari ST racing game written in Motorola 68000 assembly language, copyright 1987 by Prism PLC, with conversion by Capital Software Developments Ltd. The programmer is Martin Backschat. The game features a track editor and a pseudo-3D racing mode with perspective rendering, joystick control, PSG sound effects, digital music playback, and high score tracking.

The entire game is contained in a single source file `TURBOST.S` (4193 lines original, 5600 lines with comments added during this reverse-engineering) that assembles into a 16KB executable (TURBOST.PRG) with a 371KB BSS section for runtime buffers.

## 2. Program Structure

### 2.1 Memory Layout

The program is divided into three sections:
- **TEXT segment** (~11,544 bytes): Code
- **DATA segment** (~4,106 bytes): Initialized data (strings, tables, palettes, sound data)
- **BSS segment** (~371,158 bytes): Uninitialized runtime buffers

Key BSS allocations:
| Buffer | Size | Purpose |
|--------|------|---------|
| `scndscr` | 32,256 bytes | Secondary screen buffer (256-byte aligned) |
| `playseq` | 2,000 bytes | Generated track sequence |
| `aktseq` | 5,832 bytes | Decompressed active sequence (6*6*162) |
| `datascr1` | 32,034 bytes | Cockpit/dashboard sprite data |
| `signscr1` | 32,034 bytes | Sign sprites (screen 1) |
| `signscr2` | 32,000 bytes | Signs + pause image + 3 scenery bitmaps (see §5.4.1) |
| `film` | 32,034 bytes | Explosion animation frame |
| `bitscene` | 81,920 bytes | 16 bit-shifted scenery variants (16 * 5120) |
| `explsnd` | 5,888 bytes | Explosion sound sample |
| `digisnd` | 78,000 bytes | Digital music sample |
| `pic` | 32,066 bytes | Working picture buffer (editor background) |
| `playdat` | 200 bytes | Track editor grid data (18x9 + padding) |
| `sprwork1` | 1,600 bytes | Sprite compositing workspace |
| `screen` | 4 bytes (ptr) | Primary screen address |
| `screen2` | 4 bytes (ptr) | Secondary screen address (double-buffering) |

### 2.2 Entry Point and Initialization (Lines 1-17)

```
start:  save stack pointer -> a5
        set user stack -> #usersp
        calculate program size from basepage (TEXT+DATA+BSS+$100)
        GEMDOS Mshrink ($4a) to release unused memory
        call main
        GEMDOS Pterm0 ($00) to exit
```

The basepage is at 4(a5), with TEXT size at offset $c, DATA at $14, BSS at $1c.

### 2.3 Main Program Flow (Lines 1574-1800)

```
main:
  1. Enter supervisor mode (GEMDOS Super $20)
  2. Detect 50/60Hz from $ff820a (sets waitcnt for VBL sync: 680 for 50Hz, 790 for 60Hz)
  3. Save hardware palette from $ff8240, set screen to black
  4. Return to user mode
  5. Initialize AES (appl_init), VDI (open workstation), Line-A
  6. Get screen addresses (XBIOS Logbase $03, Getrez $04)
  7. Set low resolution (XBIOS Setscreen $05 with rez=0)
  8. Align secondary screen buffer to 256-byte boundary
  9. Load resources:
     - heavy.seq -> digisnd (digital music, 78KB)
     - title.pi1 -> screen (title picture)
     - Display title palette, play digital music until keypress
     - dashbord.pi1 -> screen2 (cockpit), copy sprite area to datascr1
     - signs.pi1 -> signscr1
     - signs2.pi1 -> signscr2
     - film.pi1 -> film (explosion animation)
     - expl.snd -> explsnd (explosion sound)
  10. Install custom joystick IRQ handler for port 1 via XBIOS Kbdvbase ($22)
      (IKBD protocol: $ff header = joystick 1; $fe would be joystick 0/mouse port)
  11. Load editor background: trcs.pi1 -> pic, set its palette
  12. Reset timer, return to user mode
  13. Load default track (file "default") -> playdat
  14. Load default high scores ("default.top") -> hiscore
  15. Set mouse cursor to finger pointer (gr_mouse #3)
  16. Enable mouse via XBIOS Ikbdws ($19) 
  17. Build display from playdat, enter editor loop
```

### 2.4 Editor Loop (Lines 1785-1800)

```
loop1:
  Query mouse position and button state (vq_mouse VDI #124)
  If left button pressed -> call click handler
  Loop forever
```

## 3. Two Main Modes

### 3.1 Track Editor Mode

The editor presents an 18x9 grid (playfield) where the user places track components using the mouse. The screen layout:
- **Top bar** (y=0..11): 6 command buttons, each 48 pixels wide:
  - LOAD (0-48), SAVE (48-96), CLEAR (96-144), SCENERY (144-192), PLAY (192-240), QUIT (240-288)
- **Playfield** (x=16..303, y=16..159): 18 columns x 9 rows of 16x16 pixel cells
- **Component palette** (y=163+): 19 selectable track pieces arranged in 2 rows

> **Note**: The playfield bounds check uses `bge` (greater-or-equal), so x=304 and y=160 are *outside* the playfield.

The coordinate-to-command mapping is in `koordtab` (line 4683).

**Click Handling** (`click`, line 912):
1. Test if click is within playfield bounds -> `infield`
2. Test against command button table (`koordtab`) -> dispatch to handler
3. Test against component palette (`click3`) -> select active component with XOR flash

**Placing Components** (`infield`, line 852):
- Converts mouse pixel coordinates to grid indices (dividing by 16)
- Stores component number in `playdat` array at calculated offset
- Copies 16x16 pixel block from component palette area to grid position

**File Browser** (`opndsk`, line 1112):

The file browser is invoked by both LOAD and SAVE commands. It uses GEMDOS directory search functions to list files in a two-column layout, then prompts for a filename. The VT52 terminal escape sequences are used for cursor positioning — a pattern common in Atari ST applications that need simple text output without GEM dialog boxes.

```pseudocode
function opndsk() -> (filename, byte_count, buffer):
    save_pic()                               // save editor screen
    clr_pic()                                // clear screen for listing

    // Set DTA (Disk Transfer Address) for GEMDOS file search
    GEMDOS_Fsetdta(dta)                      // 50-byte buffer for search results
    result = GEMDOS_Fsfirst("*.*", 0)        // search for first file, normal attribs

    column = 4; row_count = 0                // start in column 4
    while result == 0:                       // 0 = file found
        // Position cursor using VT52: ESC 'Y' row+$20 col+$20
        postxt[2] = row_count + $20          // row (encoded)
        postxt[3] = column + $20             // column
        print(postxt)                        // move cursor
        print(dta + 30)                      // filename is at offset 30 in DTA

        row_count++
        if row_count == 23:                  // first column full (23 files)
            if column == 24: break           // second column also full -> done
            column = 24; row_count = 0       // switch to second column

        result = GEMDOS_Fsnext()             // search for next file

    print(endpost)                           // reset text color
    print("Enter name: ")
    filename = getinput()                    // keyboard input, up to 12 chars
    return (filename, 164, playdat)          // 164 bytes = track + scenery
```

**Findings.** The VT52 cursor positioning (`ESC Y row col`) encodes row and column by adding `$20` (space character = 32). This means row 0 is encoded as space, row 1 as `!`, etc. The postxt string is patched in place before each `print` call — a form of self-modifying data that avoids allocating separate strings for each cursor position. The two-column layout (column 4 and column 24) supports up to 46 files, which was generous for 1987 floppy disks.

**Grid Rebuild** (`build`, line 1305):

After loading a track or clearing the grid, `build` reconstructs the entire playfield display by copying each component's graphic from the palette area to its grid position. The palette area is laid out on-screen below the playfield (starting at y=163), with components arranged in a 2-row grid at 32-pixel intervals.

```pseudocode
function build():
    mouseoff()
    for index = 0 to 161:                   // 162 cells (18 columns × 9 rows)
        component = playdat[index]           // 0 = empty, 1-18 = track piece

        // Calculate destination: grid cell position on screen
        row = 1; col = index
        while col >= 18:                     // manual divmod (no DIVU for small values)
            col -= 18; row++
        dest = screen + (col+1)*8 + row*2560 // +1 for 16px left margin; 2560 = 16 lines × 160

        // Calculate source: component graphic in palette area
        // Palette layout: components at x=0,2,4,...,18 word-groups, y starting at 163
        // Row 2 starts at x=2, y=183 (y+20)
        src_x = 0; src_y = 163
        for i = 0 to component-1:            // count to the right component
            src_x += 2                       // advance by 32 pixels (2 word-groups)
            if src_x >= 19:                  // past right edge of palette row?
                src_x = 2; src_y += 20       // wrap to next row

        source = screen + src_x*8 + src_y*160

        // Copy 16×16 pixel block (8 bytes per line, 16 lines)
        for line = 0 to 15:
            dest[0:3] = source[0:3]          // planes 0+1 (longword)
            dest[4:7] = source[4:7]          // planes 2+3
            dest += 160; source += 160
    mouseon()
```

**Findings.** The `build1a` loop implements integer division by repeated subtraction (`while d6 >= 18: d6 -= 18; d1++`) rather than using the 68000's `DIVU` instruction. This is faster for small dividends: the maximum value of `d6` is 161, so the loop executes at most 9 times (8 `SUB` + 8 `CMP` = ~80 cycles) vs. `DIVU`'s fixed ~140 cycles. For the source component lookup, the same pattern appears in `build1c`: counting down `d0` while advancing through the palette grid. The entire `build` routine saves/restores all registers via `movem.l` for each of the 162 cells — this is expensive (~200 cycles per save/restore pair) but keeps the code simple by allowing `build1` to freely use all registers.

### 3.2 Play/Race Mode

Activated via PLAY button (`com_play`, line 1207):
1. Save editor state
2. Generate track sequence from playfield (`generate`)
3. Switch to joystick mode (XBIOS Ikbdws with `joyon` packet: $12,$14)
4. Call `play` subroutine
5. On return, switch back to mouse mode and restore editor

### 3.3 Main Game Loop (`pl2`) — Pseudocode

**Motivation.** The main game loop is the largest contiguous block of code in the program (~380 lines of assembly). It interleaves joystick polling, physics simulation, road rendering, sign drawing, and crash detection — all in a single function with no subroutine boundaries between them. In the source, register assignments shift mid-function (e.g., `a0` starts as the track pointer, gets aliased to `a1`, then `a3` becomes `fakttab`), making the data flow hard to trace. The pseudocode separates the logical phases.

**Key insight.** The game has no explicit frame rate limiter. Each iteration of this loop *is* one frame: the VBL interrupt handles scenery scrolling and the palette split in the background, while this loop redraws the road area on the off-screen buffer. The time it takes to render one frame implicitly determines the frame rate — the double buffer swap at the top naturally synchronizes to the VBL.

```pseudocode
function game_loop():
    while true:
        // --- Input Phase ---
        if keybd == $39: handle_pause()   // Space bar: direct ACIA read
        if keybd == $61: abort_to_editor() // Undo key

        swap_screen_buffers()              // see §5.1
        update_score_display()             // every 3 frames: score -= 2 (BCD)

        // --- Joystick Processing Phase ---
        // joystat is written asynchronously by the joyirq IKBD handler
        if joy_left:
            scroll += 1; joydir += 4      // scenery scroll + steering wheel
            xadd += (randtab2 - getfak + 4) // lateral push, proportional to speed
        if joy_right:
            scroll -= 1; joydir -= 4
            xadd -= (randtab2 - getfak + 4)
        if joy_up:
            if fire_button AND rounds==3 AND gang<3:
                gang++; rounds=0           // shift up (requires max RPM + fire)
            elif rounds < 3 AND getfak > 0:
                rounds++; getfak--         // accelerate within current gear
                speedfak++                 // increase track advancement speed
        if joy_down:
            if fire_button AND rounds==0 AND gang>0:
                gang--; rounds=3           // shift down (requires min RPM + fire)
            else: decspeed()               // brake: decrease rounds and speedfak

        // Auto-center steering (2 units per frame toward zero)
        if joydir > 0: joydir -= 2
        if joydir < 0: joydir += 2
        update_steering_wheel_display()

        // --- Curve Physics Phase ---
        curve = sign_extend_nibble(current_track_segment & 0x0F)
        speed_factor = getfak + 1          // 1 (fast) to 16 (stopped)
        if curve != 0:
            // Curve: car drifts laterally
            table = (steering_this_frame ? faktab : faktab2)
            response = table[speed_factor - 1]  // 7-86 or 14-172
            base = (|curve| == 1 ? 220 : 300)   // gentle vs sharp curve
            drift = base / response              // signed: positive = push left
            xadd += drift
        else:
            // Straight: gradual centering (xadd decays toward 0)
            xadd += (xadd / 8) / speed_factor

        if speed == 0:                     // car is stationary
            // Only direct steering input affects position, no curve drift
            xadd += xadd2; scroll += scroll1; drift = 0

        // Apply total offset to road edges
        road_left = 0 + xadd;  road_right = 319 + xadd

        // --- Rendering Phase ---
        fill_road_area_with_grass()        // movem.l fast fill, 70 lines at row 71+

        curve_accum = 0
        for row = 69 downto 0:             // bottom (close) to top (far)
            segment = read_next_track_byte()
            curve_val = sign_extend_nibble(segment)
            repeat_count = fakttab[segment_index]  // 8 at bottom, 0 at top

            for line = 0 to repeat_count:
                // Edge color stripes alternate 12/13, duration from randtab
                update_edge_color_stripe()

                // Perspective curve: accumulate and divide by distance
                curve_accum += curve_val
                perspective = curve_accum / (2*row + 1)
                road_left += perspective;  road_right += perspective

                // Lateral distortion: car offset projected by distance
                distortion = xadd * (row - 70) / 100
                edge_width = row / 4 + 1

                draw_hline(road_left - distortion - edge_width,
                           road_left - distortion, randcol)   // left edge
                draw_hline(road_left + distortion,
                           road_right + distortion, 0)        // road (black)
                draw_hline(road_right + distortion,
                           road_right + distortion + edge_width, randcol) // right edge

                road_left += rowtab[row]   // road widening
                road_right -= rowtab[row]

        draw_roadside_sign_if_visible()
        check_crash_conditions()           // |xadd| >= 300 or sign collision
        advance_track_if_speed_allows()    // speed counts down; at 0: advance 1 segment
```

**Findings and cross-reference notes.**

*Perspective formula.* The expression `curve_accum / (2*row + 1)` (source: `divs d0,d6` where `d0 = aktrow*2+1`) is a cheap approximation of true perspective division. At the bottom of the screen (row 69), the divisor is 139, so curves barely shift. At the top (row 0), the divisor is 1, so curves shift aggressively — creating the impression of a road curving toward the horizon. This avoids any trigonometry. The 68000's `DIVS` (signed 32÷16→16 division) is relatively expensive (~140 cycles), but only executes once per scanline, which is acceptable.

*Two-table curve response.* `faktab` (7–86) vs `faktab2` (14–172) is a subtle game-feel design: when you steer into a curve, you "grip" the road (tight response, small drift). When you don't steer, the car "slides" (wide response, large drift). This rewards active driving. The table selection is at source label `setfak2` where `tst.w xadd2` tests whether the player steered this frame.

*Edge color stripes.* The countdown is a subtraction, not a division: `randcnt -= speedfak` (source: `sub.w d0,randcnt`). When `randcnt` goes negative, the next `randtab` entry is loaded and the edge color toggles between 12 and 13. Faster speed (higher `speedfak`) drains the counter faster, producing shorter color bands — simulating faster road movement.

*Straight road centering.* The formula `(xadd / 8) / speed_factor` uses two chained `DIVS` instructions with `ext.l` between them. The first `ext.l` sign-extends the 16-bit quotient to 32 bits for the second division. This is a common 68000 pattern for chained divisions since `DIVS` produces a 16-bit quotient in the low word and a 16-bit remainder in the high word — `ext.l` clears the remainder to prevent it from corrupting the next division.

## 4. Track System

### 4.1 Track Components (Lines 4841-4924)

There are 18 track pieces (`bau1`-`bau18`), each defined as:
```
bauN:
  .dc.w  exit_dir1, entry_dir, exit_dir2   ; direction codes
  .dc.b  curve_values..., $80              ; sequence data (terminated by $80)
```

The direction encoding uses a compass rose:
```
      5  1  6
       \ | /
    4-- *** --2
       / | \
      8  3  7
```

The `offs` table (line 4851) maps these directions to grid offsets:
| Direction | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|-----------|---|---|---|---|---|---|---|---|---|
| Offset    | 0 | -18 | 1 | 18 | -1 | -19 | -17 | 19 | 17 |

### 4.2 Track Generation (`generate`, lines 1464-1556)

**Motivation.** This is the algorithm that bridges the 2D editor and the 1D racing engine. It walks the grid following component connections, producing the linear byte stream that the renderer consumes. The trickiest aspect is handling reversed components: when a piece's entry direction doesn't match the direction we're coming from, the entire sequence is read backward with negated curve values. This reversal logic is scattered across several branch targets in the assembly (`gen1c`, `gen1d`, `gen2`, `gen3`) and is much clearer in pseudocode.

```pseudocode
function generate() -> length:
    src = playdat.begin()
    dst = playseq.begin()

    // Step 1: Linear scan for start piece (#9 or #18)
    while src.component not in {9, 18}:
        src.advance()
    start_pos = src
    start_component = src.component

    passes_remaining = 1   // we cross the start piece twice: entering + exiting the loop

    loop:
        // Step 2: Look up component definition
        component = playtab[src.component - 1]   // -1 because component 0 is "empty"
        exit1_dir = component.word[0]             // primary exit direction
        entry_dir = component.word[1]             // expected entry direction
        exit2_dir = component.word[2]             // alternate exit direction

        // Grid offsets for both exits
        offset1 = offs[exit1_dir]   // e.g., direction 1 (N) -> -18 cells
        offset2 = offs[exit2_dir]

        // Step 3: Determine read direction
        if src == start_pos OR entry_dir == last_exit_dir:
            // FORWARD: entry direction matches — read sequence normally
            for each byte in component.sequence (until $80 terminator):
                dst.write(byte)
        else:
            // REVERSED: entry direction doesn't match
            // This means we're entering from the "wrong" end of the piece.
            // Swap exits so we leave through the correct one,
            // and read the curve data backward with negated values
            // (a left curve becomes a right curve when traversed in reverse).
            swap(exit1_dir, exit2_dir)
            swap(offset1, offset2)
            ptr = end_of(component.sequence)   // find $80 terminator
            while ptr > component.sequence:
                ptr--
                dst.write(-(*ptr))             // negate each curve byte

        // Step 4: Follow the exit to the next grid cell
        last_exit_dir = exit1_dir
        if src.component == start_component AND src != start_pos:
            // Back at start: the loop is complete
            if passes_remaining > 0:
                passes_remaining--
                src += offset1
                continue                       // process start piece a second time
            else:
                dst.write($80)                 // end marker
                return dst - playseq           // total sequence length
        src += offset1
```

**Findings and cross-reference notes.**

*"Process start piece twice" via `DBF`.* The 68000 `DBF` (Decrement and Branch if False — always false, so it always decrements and branches until -1) initializes `d1=1`. The loop body executes, then `DBF` decrements to 0 and branches back (0 ≠ -1). It executes again, `DBF` decrements to -1, and now the loop exits. So `d1=1` yields exactly **2 iterations** — the start piece is processed at the initial `gen1a` entry and again via the `gen4` re-entry. This exists because the race starts *at* the start piece and must end *at* the start piece — the racer crosses it as both the starting line and the finish line.

*Direction system.* The 8-way compass with grid offsets (`offs` table: N=-18, E=+1, S=+18, W=-1, NW=-19, NE=-17, SE=+19, SW=+17) is elegant for a grid editor. By storing just 3 direction codes per component, the generator can follow any path. The reversal logic (`exg d4,d6` + backward read with `neg.b`) means users don't need to worry about component orientation — the generator handles both directions automatically.

*Reversal detection.* The code uses `cmp.w olddir,d2` to compare the component's `entry_dir` field against the direction we came from. If they don't match, the piece is oriented the "wrong way" and must be read in reverse. The `EXG` instruction (exchange two data registers, 6 cycles, no flags affected) swaps exit directions and their corresponding grid offsets in a single operation.

### 4.3 Sequence Decompression (Lines 1905-1930)

Each byte in `playseq` is expanded into 6 bytes in `aktseq`:
- Lower nibble: track curve data (replicated 3x as words with both nibbles identical)
- Upper nibble: sign information (billboard placement)

The end marker is track value 7 (`%0111`).

### 4.4 Sign Placement (Lines 1934-1947)

After decompression, signs are randomly placed:
- Starting at sequence position 35, every 40 positions
- XBIOS Random ($11) generates sign type (0-3) and side (left/right via bit 3)
- Sign types: 0=Prism Leisure Logo, 1=ST Ad, 2=Capital Software, 3=GO!

## 5. Rendering Engine

### 5.1 Double Buffering

**Motivation.** Double buffering is a standard technique, but the Atari ST implementation has a subtlety that makes it easy to get wrong. The ST's video hardware reads from a *physical* base address (`dbaseh`/`dbasel`), while TOS maintains a *logical* screen address (`_v_bas_ad` at $44e). These are separate: TOS uses `_v_bas_ad` for GEM drawing calls, but the video chip reads from `dbaseh/dbasel`. The game must update both, and it must also verify that the hardware has actually latched the new address before starting to draw — otherwise, it might modify a buffer that's still being displayed.

The three variables involved are:
- `screen`: the primary buffer (fixed address, determined at startup)
- `screen2`: the secondary buffer (aligned to 256-byte boundary)
- `aktscr`: tracks which buffer the game is *currently drawing to*

The trick is that `aktscr` is compared against `screen` to decide the swap direction. After each frame, the roles flip: what was drawn becomes displayed, and what was displayed becomes the new drawing target.

```pseudocode
function swap_screen_buffers():
    // Determine which buffer to display and which to draw to
    if aktscr == screen:
        // We just finished drawing to screen (primary)
        // -> Display primary, start drawing to secondary
        aktscr = screen2                   // next frame: draw to screen2
        _v_bas_ad = screen                 // tell TOS: logical screen = primary
    else:
        // We just finished drawing to screen2 (secondary)
        // -> Display secondary, start drawing to primary
        aktscr = screen                    // next frame: draw to screen
        _v_bas_ad = screen2                // tell TOS: logical screen = secondary

    // Write the NEW display address to the video hardware
    // The Shifter latches this address at the start of the next frame,
    // NOT immediately. dbaseh/dbasel are write-only byte registers.
    dbaseh = high_byte(aktscr)             // $ff8201 = high byte of video base
    dbasel = low_byte(aktscr)              // $ff8203 = low byte

    // CRITICAL: Wait for the hardware to actually start using the new address.
    // Without this sync, we might start modifying a buffer that the Shifter
    // is still reading from the *previous* frame, causing tearing.
    //
    // The sync reads vcounthi ($ff8205), which reflects the high byte of the
    // address the Shifter is *currently* reading from. When it matches the
    // high byte we just wrote, the new address has been latched.
    expected = high_byte(aktscr)
    while vcounthi != expected:
        spin                               // typically 0-2 iterations
```

**Findings and cross-reference notes.**

*24-bit address layout.* The 68000 has 32-bit address registers but only a 24-bit address bus. The Atari ST stores screen addresses as 24-bit values in 32-bit longwords (byte 0 unused, byte 1 = high, byte 2 = mid/low). The source writes `move.b 1(a1),$ff8201` and `move.b 2(a1),$ff8203` — extracting bytes at offsets +1 and +2 from the `aktscr` variable's address. The Shifter only has two writable base address registers (`dbaseh` and `dbasel`), giving 16-bit precision (256-byte alignment required). This is why `screen2` must be aligned to a 256-byte boundary during initialization.

*Sync via video counter.* The Shifter's read counter at `vcounthi`/`vcountmid`/`vcountlow` (`$ff8205`–`$ff8209`) continuously reflects the address being *currently fetched*, not the base address. The code reads `vcounthi` ($ff8205) and compares it against the high byte of the newly-programmed base address. When they match, the Shifter has started reading from the new buffer. Per the Atari ST hardware documentation, the base address is latched at the start of each frame (during the vertical blank), so the comparison succeeds within microseconds after the VBL occurs.

*Same-high-byte risk.* If both buffers share the same high byte (within 64KB of each other), the sync loop would pass immediately with no protection. However, `screen` is assigned by TOS (typically in the $70000–$80000 range) and `screen2` is in the program's BSS (typically much lower), so their high bytes are virtually always different.

*Why not XBIOS Vsync?* The alternative, `XBIOS Vsync` (function $25, documented in `XBIOS.TXT`), blocks until the next vertical blank — potentially wasting up to 20ms (one full frame). The polling approach here completes in a few iterations (typically <100 cycles), allowing the game to start drawing the next frame immediately after the swap. For a game targeting consistent frame timing, this difference is significant.

### 5.2 Perspective Road Rendering (Lines 2483-2570)

The road is drawn from bottom (row 69, near camera) to top (row 0, horizon), 70 scanlines total. Each scanline involves 3 `hline` calls (left edge, road surface, right edge). See **Section 3.3** for the full game loop pseudocode including the rendering phase.

Key data tables that control the perspective effect:

- **`fakttab`** (line 4938): 70 word entries. Each value = additional scanlines to repeat for that track segment. Bottom values are 8 (thick, close to camera), decreasing to 0 at top (thin, far away). This creates the perspective foreshortening — nearby road sections are tall, distant ones are compressed.

- **`rowtab`** (line 5180): 70 word entries (values 2-3). Applied per scanline to widen the road toward the bottom, simulating perspective divergence.

- **`randtab`** (line 4950): 100+ byte entries controlling edge color band duration. Decreases from 15 at bottom to 0 at top. Combined with the color toggle (12↔13), this produces alternating stripes that appear to move faster near the horizon — a classic speed-illusion technique.

### 5.3 Grass/Background (Lines 2483-2501)

Before road drawing, the entire road area (70 scanlines starting at row 71) is filled with grass pattern using a fast `movem.l` block copy. The `wiese` pattern data (line 4973) represents color 14 (green) in all 4 bitplanes.

### 5.4 Scenery System

#### 5.4.1 Resources and Memory Layout

All three scenery bitmaps, the pause screen image, and one set of billboard sprites are packed into a **single PI1 file** (`signs2.pi1`, 32034 bytes). After loading into `signscr2` (32000 bytes of screen data), the buffer is partitioned as follows:

| Offset | Lines | Size | Content |
|--------|-------|------|---------|
| 0 | 0–64 | 10,400 bytes | Billboard sprites (Capital Software sign, used by `signtab[2]`) |
| 10,400 | 65–102 | 6,080 bytes | Pause screen image (copied to screen during Space-bar pause) |
| 16,480 | 103–104 | 320 bytes | Unused gap (2 scanlines) |
| 16,800 | 105–136 | 5,120 bytes | Scenery bitmap 0: "Rising Sun/City" skyline |
| 21,760 | 136–167 | 5,120 bytes | Scenery bitmap 2: see note below |
| 26,880 | 168–199 | 5,120 bytes | Scenery bitmap 1: see note below |

**Overlap finding:** Scenery 0 (offset 16800, 32 lines) ends at byte 21919, but scenery 2 starts at byte 21760 — an overlap of 160 bytes (1 scanline). This means the bottom line of scenery 0 and the top line of scenery 2 share the same pixel data. This is likely deliberate: the artist designed the sceneries with a shared horizon line to save 160 bytes and fit everything into one 32000-byte PI1 image.

The `scenaddr` table provides these offsets:
```
scenaddr[0] = signscr2 + 16800   (aktscene 0 → Rising Sun)
scenaddr[1] = signscr2 + 26880   (aktscene 1 → text says "High Noon", but bitmap is at position 3)
scenaddr[2] = signscr2 + 21760   (aktscene 2 → text says "Alps", but bitmap is at position 2)
```

#### 5.4.2 Palette and Bitmap Swap (Section 17.1)

The text labels (`scentxtp`) map aktscene 0→"Rising Sun", 1→"High Noon", 2→"Alps". But the palette table and scenery bitmap table have entries 1 and 2 **swapped**:

| aktscene | Menu Text | `paladdr` | `scenaddr` offset |
|----------|-----------|-----------|-------------------|
| 0 | Rising Sun/City | `scen1pal` (warm reds/oranges) | 16800 |
| 1 | High Noon/City | **`scen3pal`** (cool grays/blues) | **26880** |
| 2 | Alps/Village | **`scen2pal`** (bright blues/greens) | **21760** |

Both `paladdr` and `scenaddr` are swapped consistently, so the palette always matches its bitmap — but the *labels* don't match the visuals. See **Section 17.1** for discussion.

#### 5.4.3 Data Flow: Disk to Screen

The complete scenery data path during a game:

```
1. STARTUP:   signs2.pi1 → signscr2       (load entire PI1 into 32KB buffer)

2. PLAY INIT: signscr2 + scenaddr[aktscene]   (select 32-line bitmap for chosen scenery)
              → bitscene[0]                    (copy 5120 bytes: unshifted original)
              → bitscene[1..15]                (15 more copies, each ROXR-shifted 1px right)
              Total: 81920 bytes of pre-computed scrolled scenery

3. EACH FRAME (VBL interrupt):
   a. Set scenery palette from paladdr[aktscene]  → color0..color15
   b. Calculate scroll offset from steering input  → select bitscene[sub_pixel]
   c. Copy 32 lines with wraparound              → screen rows 39-70
   d. Wait for raster beam at row 71              → switch to game palette (playpal)
```

Each scenery palette is hardcoded in the DATA section (not loaded from disk):
- `scen1pal`: $000,$761,$750,$740... (warm sunset gradient)
- `scen2pal`: $000,$235,$245,$467... (bright daytime)
- `scen3pal`: $000,$136,$237,$320... (cool grayscale ramp)

#### 5.4.4 VBL Scrolling — Pseudocode

**Motivation.** The VBL handler is an interrupt routine that runs in kernel context with strict timing constraints. It must complete before the raster beam passes the sky-road boundary, or the palette split will glitch. The scrolling logic is particularly confusing in assembly because it handles positive and negative scroll separately (different base-offset calculations), and the wraparound requires splitting each scanline copy into two segments. The pseudocode reveals that it's conceptually simple: pick a pre-shifted bitmap, copy it with wraparound, then wait for the beam.

```pseudocode
function vbl_interrupt():
    // Phase 1: Immediately set the scenery palette
    // (this must happen while the beam is in the sky area)
    write scenery_palette[aktscene] to color0..color15

    // Phase 2: Calculate which pre-shifted bitmap to use and where to start
    raw_scroll = |scroll| mod 320             // normalize to 0-319 range
    sub_pixel  = raw_scroll & 0xF             // 0-15: selects 1 of 16 pre-shifted bitmaps
    coarse     = (raw_scroll & ~0xF) / 2      // byte offset within a scanline (0-152, step 8)

    // For negative scroll, the sub-pixel and coarse are computed slightly differently
    // (the bitmap selection is inverted: sub_pixel = 15 - bits)

    bitmap_base = bitoffs[sub_pixel]          // one of 16 pre-shifted 5120-byte bitmaps
    dest = _v_bas_ad + 39*160                 // screen row 39 (bottom of sky area)

    // Phase 3: Copy 32 lines of scenery with horizontal wraparound
    for line = 0 to 31:
        src_line = bitmap_base + line * 160
        // Split the copy at the coarse offset boundary:
        //   First:  copy from (coarse) to end of line
        //   Second: copy from start of line to (coarse)   [wraparound]
        bytes_before_wrap = 160 - coarse
        bytes_after_wrap  = coarse
        memcpy(dest, src_line + coarse, bytes_before_wrap)   // right portion
        memcpy(dest + bytes_before_wrap, src_line, bytes_after_wrap) // left portion (wrap)
        dest += 160

    // Phase 4: Raster split - palette swap
    // Pre-load the game palette into CPU registers (ready to write instantly)
    game_palette = playpal[1..15]             // 8 registers = 16 color words

    // Calculate the video memory address where row 71 begins
    target = (dbaseh << 16 | dbasel << 8) + 71*160
    timeout = waitcnt                         // 680 (PAL) or 790 (NTSC)

    // Busy-wait for the raster beam, reading vcountmid via movep
    while timeout > 0:
        timeout--
        current_pos = movep.w(vcountmid)      // reads mid+low bytes of video counter
        if current_pos >= target: break

    // Instant palette swap: movem.l writes 32 bytes in one instruction
    write game_palette to color0..color15

    return_from_exception()
```

**Findings and cross-reference notes.**

*Time-space tradeoff.* The 16 pre-shifted copies consume ~80KB of RAM (about 22% of the BSS). At runtime, the VBL only needs to select a bitmap and do a flat memory copy — no per-pixel shifting. This is critical because the VBL handler is racing the raster beam: any computation beyond simple copies would risk missing the palette-switch deadline at row 71.

*`MOVEP.W` for video counter reading.* Per the 68000 reference (`68000_Assembly_Language.txt`), `MOVEP.W d,x(An)` reads bytes at offsets x+0 and x+2 (skipping x+1) and packs them into a register word, with the byte at x+0 becoming the high byte. The source uses `movep.w 0(a0),d0` where `a0=$ff8201` (dbaseh), reading bytes at `$ff8201` (dbaseh) and `$ff8203` (dbasel) to reconstruct the 16-bit video base address. Later, `movep.w 0(a0),d1` with `a0=$ff8207` (vcountmid) reads `vcountmid` and `vcountlow` to get the current beam position. This instruction was designed by Motorola specifically for byte-wide peripheral buses — a perfect match for the Atari ST's Shifter chip, whose registers are byte-accessible at odd addresses.

*Raster split timing.* The palette swap uses `movem.l d3-d7/a2-a4,(a6)` — 8 registers × 4 bytes = 32 bytes written in a single instruction, covering all 16 color registers in one atomic blast. This is critical: a multi-instruction palette write could produce visible color tearing if the beam crosses the boundary mid-write.

*PAL vs NTSC timeout.* The `waitcnt` value (680 for 50Hz PAL, 790 for 60Hz NTSC) is calibrated as a busy-loop iteration count, not a scanline count. It's detected at startup by reading `syncmode` ($ff820a) bit 1. The different values account for the different vertical blank durations: PAL has a longer blanking period (more time before the beam reaches row 71) but the VBL handler has more scenery data to copy, so the net timing budget is similar.

#### 5.4.5 Scenery Pre-Shifting (`prep1`–`prep4`) — Pseudocode

**Motivation.** This is the most hardware-specific algorithm in the game and the one that benefits most from pseudocode. The goal is straightforward — create 16 copies of a 32-line scenery bitmap, each shifted 1 pixel further right — but the implementation requires understanding the Atari ST's interleaved bitplane format at the word level.

The key challenge: a "1-pixel shift right" of an entire 320-pixel-wide image cannot be done with a single shift instruction. Each bitplane of each scanline is stored as 20 separate 16-bit words, spaced 8 bytes apart (due to the 4-way interleaving). To shift one plane by one pixel, you must chain `ROXR` (Rotate Right through eXtend) across all 20 words in sequence. The extend/carry flag propagates the bit that "falls off" the right edge of one word into the left edge of the next word. The bit that falls off the final (rightmost) word must wrap around to bit 15 of the first (leftmost) word to create seamless horizontal tiling.

This entire process must be repeated for all 4 bitplanes of each scanline, for all 32 scanlines, for all 15 shifted copies. The result is 81,920 bytes of pre-computed data — a significant memory cost (about 22% of the BSS), but it makes runtime scrolling trivially fast.

```pseudocode
function prepare_shifted_sceneries():
    // Step 1: Copy original scenery into bitscene[0]
    source = scenaddr[aktscene]          // 32 lines × 160 bytes in signscr2
    memcpy(source, bitscene[0], 5120)    // bitscene[0] = unshifted original

    // Step 2: Create 15 shifted copies (bitscene[1] through bitscene[15])
    for shift = 1 to 15:
        // Start from the previous copy
        memcpy(bitscene[shift-1], bitscene[shift], 5120)

        // Now shift the new copy right by exactly 1 pixel
        ptr = bitscene[shift]
        for scanline = 0 to 31:
            for plane = 0 to 3:
                // ROXR chain across all 20 words of this plane in this scanline
                // The words are at offsets +0, +8, +16, ..., +152 from the plane's
                // starting position (spaced by 8 because 4 planes are interleaved)
                carry = 0
                for word_idx = 0 to 19:
                    word_addr = ptr + word_idx * 8
                    old_carry = carry
                    carry = word[word_addr] & 1       // bit that will fall off right edge
                    word[word_addr] >>= 1             // shift right by 1
                    if old_carry:
                        word[word_addr] |= 0x8000     // insert previous carry at left edge

                // Wrap: the final carry (from word 19) goes into bit 15 of word 0
                if carry:
                    word[ptr] |= 0x8000               // set leftmost bit of first word
                else:
                    word[ptr] &= 0x7FFF               // clear it (explicit, since ROXR
                                                      // doesn't clear automatically)
                ptr += 2                              // next bitplane (+2 bytes)
            ptr += 160 - 8                            // next scanline (skip past 4 planes)
```

**Findings and cross-reference notes.**

*`ROXR.W` flag behavior.* Per the 68000 reference (`68000_Assembly_Language.txt`), `ROXR.W` rotates a 16-bit word right by 1 through the X (Extend) flag: bit 0 goes into X, old X goes into bit 15, and the C (Carry) flag is set equal to X. When you chain 20 `ROXR.W` instructions in sequence (as the source does at offsets 0, 8, 16, ..., 152), the carry ripples naturally from word to word via the X flag — no explicit carry variable is needed.

*X flag initialization concern.* The source does **not** explicitly clear the X flag before the first `ROXR` in each chain. The preceding instruction is `move.l a2,a0` (address register operation, which does not affect X) or `addq.l #2,a0` (which *does* set X based on the result). In practice, `addq.l #2,a0` applied to a large pointer will never generate a carry, so X will be 0 — but this is a latent fragility, not a guaranteed invariant. A defensive implementation would insert `andi #$ffef,ccr` (clear X) before the chain. That said, even if X were set on entry, it would only introduce a single spurious pixel in bit 15 of the first word, which would be overwritten by the wrap-around logic immediately after the chain.

*`BCC` after `ROXR`.* The `BCC prep3a` tests the C flag, not X. However, after `ROXR`, C is always equal to X (both receive the bit that rotated out). So testing C is equivalent to testing X here. The code then either sets bit 15 of word 0 (`or.w #$8000,(a0)`) or clears it (`and.w #$7fff,(a0)`), implementing the pixel wraparound from right edge to left edge. This explicit set/clear is necessary because the *next* `ROXR` chain (for the next bitplane) will read this bit as its starting content, and it must reflect the wrapped pixel, not the previous plane's carry.

*Why not `ROR` instead of `ROXR`?* The `ROR` instruction rotates through the register only (bit 0 → bit 15, no external carry). It cannot chain across multiple words because there's no way to pass the outgoing bit to the next word. `ROXR` was specifically designed by Motorola for this exact use case: multi-word shift operations where carry must propagate across word boundaries.

**Performance note.** Each shifted copy requires 20 `ROXR` × 4 planes × 32 lines = 2,560 `ROXR` instructions, each taking 12 cycles (memory operand, word size). The full pre-shifting: 15 copies × 2,560 = 38,400 `ROXR` instructions = ~460,800 cycles, plus 15 memory copies of 5,120 bytes each. Total: roughly 0.7 million cycles — about 90ms at 7.83 MHz (Atari ST clock). This is done once per game start and is imperceptible to the player.

### 5.5 Sprite Rendering

**set16spr** (lines 82-174): Renders a 16-pixel-wide sprite to BOTH screen buffers.
- Parameters: x (word), y (word), height (word), sprite_data (long)
- Calculates screen offset: y*160 + (x & ~15)/2 + 16
- Determines sub-pixel shift amount from x & 15
- For each scanline: reads 4 bitplanes, shifts left by sub-pixel amount, masks and ORs onto both screens
- Uses `bittab2` for the overlap mask

**Motivation.** Sprite rendering is the most performance-critical routine after the road drawing loop. The key challenge is sub-pixel positioning: a 16-pixel-wide sprite placed at an X coordinate that isn't a multiple of 16 must be "straddled" across two 16-pixel word groups, with each bitplane shifted appropriately. The assembly uses a clever pattern: shift all data into 32-bit registers (creating a high word and low word), then write them to two screen positions using pre-decrement addressing. This is hard to follow in raw assembly because the pointer arithmetic is implicit.

Additionally, this routine writes to *both* screen buffers simultaneously. This is necessary because dashboard elements (score, speed, gear, steering wheel) must appear on whichever buffer is currently displayed — since the buffers swap every frame, both must be kept consistent.

```pseudocode
function set16spr(x, y, height, sprite_data):
    // Calculate destination address in screen memory
    // The Atari ST low-res screen: 160 bytes/line, 4 interleaved bitplanes,
    // 16 pixels = 8 bytes (4 planes × 2 bytes/plane)
    y_offset  = y * 160                     // fast: ((y*2 + y*8) << 4)
    x_aligned = x & ~15                     // round down to 16-pixel boundary
    x_byte    = x_aligned / 2               // byte offset (8 bytes per 16px group)
    sub_pixel = x & 15                      // 0-15: how many bits to shift
    shift_left = 16 - sub_pixel             // shift amount for 32-bit operation

    // The +16 accounts for pre-decrement addressing: the write loop
    // uses -(a3) which decrements *before* writing, so we start
    // pointing one word-group (8 bytes) past where we want to begin.
    offset = y_offset + x_byte + 16
    scr1 = screen  + offset                 // pointer into primary buffer
    scr2 = screen2 + offset                 // pointer into secondary buffer

    // Masks determine which bits in each word-group belong to this sprite
    right_mask = bittab2[sub_pixel]         // e.g., sub_pixel=4 -> $F000
    left_mask  = NOT right_mask             // e.g., $0FFF

    for line = 0 to height:
        // Read one scanline of sprite data (4 bitplanes, interleaved)
        p0 = sprite_data[0]                 // plane 0: 16-bit word
        p1 = sprite_data[2]                 // plane 1
        p2 = sprite_data[4]                 // plane 2
        p3 = sprite_data[6]                 // plane 3
        sprite_data += 160                  // next source line (160 byte stride)

        // Shift each plane into a 32-bit value:
        //   High word = main portion (left word-group on screen)
        //   Low word  = overflow (right word-group)
        p0_32 = p0 << shift_left            // 32-bit shift
        p1_32 = p1 << shift_left
        p2_32 = p2 << shift_left
        p3_32 = p3 << shift_left

        // Write to BOTH screen buffers using mask-and-OR
        for scr in [scr1, scr2]:
            // Right word-group (overflow): use left_mask to preserve background
            scr[-2] = (scr[-2] & left_mask) | low_word(p3_32)   // plane 3
            scr[-4] = (scr[-4] & left_mask) | low_word(p2_32)   // plane 2
            scr[-6] = (scr[-6] & left_mask) | low_word(p1_32)   // plane 1
            scr[-8] = (scr[-8] & left_mask) | low_word(p0_32)   // plane 0

            // Left word-group (main): use right_mask to preserve background
            scr[-10] = (scr[-10] & right_mask) | high_word(p3_32)
            scr[-12] = (scr[-12] & right_mask) | high_word(p2_32)
            scr[-14] = (scr[-14] & right_mask) | high_word(p1_32)
            scr[-16] = (scr[-16] & right_mask) | high_word(p0_32)

        scr1 += 176                         // next line: 160 + 16 pre-decrement offset
        scr2 += 176
```

**Findings and cross-reference notes.**

*`SWAP` instruction.* Per the 68000 reference, `SWAP Dn` exchanges the upper and lower 16-bit words of a data register in a single instruction (4 cycles). It clears V and C, sets N and Z based on the 32-bit result, and leaves X unchanged. After the 32-bit `LSL.L d5,d0`, the high word contains the main sprite portion (aligned to the left word-group) and the low word contains the overflow (the part that spills into the right word-group). `SWAP` lets the code alternate between these halves without needing extra registers — the source performs `and.w d4,-(a3); or.w d3,(a3)` for the low word, then `swap d3` to access the high word, all on the same data register.

*Pre-decrement addressing trick.* The source uses `-(a3)` (auto-decrement before access) to walk backward through the 8-byte word-group. Starting at offset +16 from the desired position, it writes planes 3, 2, 1, 0 in reverse order. This is faster than maintaining a separate index register: each `-(a3)` both decrements the pointer and accesses memory in a single instruction (saving the `add` or `sub` that would otherwise be needed).

*Dual-buffer writes.* Drawing to both `screen` and `screen2` means dashboard elements are always consistent regardless of which buffer is currently displayed. Per the source, the steering wheel (64×43 pixels, 4 columns) is the largest dashboard sprite — requiring 4 calls to `set16spr`, each processing 43 scanlines with writes to both buffers. Even so, at ~50 cycles per scanline per buffer, the total is roughly 50×43×4×2 = 17,200 cycles (~2ms) — well within the frame budget.

*Sprite data format.* The source reads sprite data with a stride of 160 bytes (`add.l #160-8,a1`), meaning sprites are stored in standard Atari ST screen format rather than a compact packed format. This allows them to be loaded directly from PI1 image files (dashbord.pi1 → datascr1, signs.pi1 → signscr1) without any format conversion. The trade-off is wasted memory: each 16-pixel-wide sprite occupies 8 useful bytes per line but is spaced 160 bytes apart. However, since the sprite data shares its buffer with the full 32000-byte screen image, this layout is simply "free" — the sprites live in their natural positions within the screen buffer.

**setsign** (lines 222-360): Renders signs to current screen only, OR-mode.
- Same parameters as set16spr but single-buffer
- Clips at screen edges using `lrand`/`rrand` mask tables
- Clips vertically: minimum y=71 (horizon), maximum y=140 (dashboard)
- Generates mask from combined bitplane data (transparent pixels)

**Motivation for pseudocode.** `setsign` is the most complex sprite routine because it combines three kinds of clipping (left edge, right edge, vertical) with auto-generated transparency — all in a single pass. The clipping masks are pre-computed in `lrand`/`rrand` tables and applied *before* shifting, which is a non-obvious optimization. The transparency mask is generated on-the-fly by ORing all 4 bitplanes together: any pixel where all planes are 0 (color 0) is transparent. This is fundamentally different from `set16spr` which uses a fixed mask from `bittab2`.

```pseudocode
function setsign(x, y, height, sprite_data):
    screen = _v_bas_ad                       // current logical screen (not both buffers!)
    clip_mask = $FFFF                        // default: no horizontal clipping

    // --- Horizontal clipping ---
    if x < 0:
        overshoot = |x|
        if overshoot > 16: return            // fully off-screen left
        x = 15 - (overshoot - 1)             // clamp to visible portion
        screen -= 8                          // back up one word-group (will be compensated)
        clip_mask = lrand[overshoot - 1]     // mask out left off-screen pixels
    elif x > 305:                            // 320 - 15 = 305
        overshoot = x - 305
        if overshoot > 15: return            // fully off-screen right
        clip_mask = rrand[overshoot]         // mask out right off-screen pixels

    // --- Vertical clipping boundaries ---
    bottom_limit = screen + 140 * 160        // row 140: below this, signs are behind dashboard
    top_limit    = screen + 71 * 160         // row 71: above this is sky/horizon

    // --- Calculate destination (same Y*160 + X offset math as set16spr) ---
    dest = screen + y*160 + (x & ~15)/2 + 16
    shift_left = 16 - (x & 15)

    // --- Render each scanline with clipping ---
    for line = 0 to height:
        if dest > bottom_limit: return       // below visible area: done
        if dest < top_limit:                 // above horizon: skip this line
            sprite_data += 160; dest += 160
            continue

        // Read 4 bitplanes and apply horizontal clip mask BEFORE shifting
        p0 = sprite_data[0] & clip_mask
        p1 = sprite_data[2] & clip_mask
        p2 = sprite_data[4] & clip_mask
        p3 = sprite_data[6] & clip_mask
        sprite_data += 160                   // next source line

        // Shift for sub-pixel alignment (same as set16spr)
        p0_32 = p0 << shift_left;  p1_32 = p1 << shift_left
        p2_32 = p2 << shift_left;  p3_32 = p3 << shift_left

        // --- Auto-generate transparency mask ---
        // OR all 4 shifted planes together: 1 where ANY plane has data
        // Invert: 1 = transparent (keep background), 0 = draw sprite
        mask_32 = NOT (p0_32 | p1_32 | p2_32 | p3_32)

        // Write to screen using mask-and-OR (same layout as set16spr)
        // Only writes to ONE screen buffer (the currently displayed one)
        for each word-group [right_overflow, left_main]:
            for each plane in [3, 2, 1, 0]:
                screen_word = (screen_word & mask) | sprite_plane

        dest += 176                          // next scanline
```

**Findings.** The vertical clipping uses raw address comparison (`cmp.l a4,a3`) rather than row arithmetic. This is faster than maintaining a row counter — a single 32-bit compare per scanline vs. a multiply + compare. The top-limit check at `cmp.l a5,a3` with `bge itsok` means the comparison is *unsigned*: since screen addresses are always positive on the Atari ST, this works correctly, but it would fail if the screen were in the top 2GB of the 68000's theoretical address space.

The clip mask is applied to the raw sprite data *before* the shift operation. This means clipped pixels never enter the shift pipeline and can never "leak" into the visible area — a subtle but important correctness property. If clipping were applied after shifting, pixels near the clip boundary could bleed across the 16-pixel word boundary.

### 5.6 Horizontal Line Drawing (`hline`, lines 387-497)

Draws a single scanline at y1 from x1 to x2 in color `col`.
- Clamps coordinates to 0-319
- Uses `coltab` (line 4985) to get 4-bitplane patterns for each of 16 colors
- Handles partial first word, full middle words, and partial last word
- Uses `bittab` masks for partial words

**Motivation for pseudocode.** `hline` is called 3 times per scanline during road rendering (left edge, road surface, right edge) × 70 scanlines = 210 calls per frame. Its performance directly determines the frame rate. The bit-manipulation logic — building masks for partial words at the start and end of a line, with solid fills in between — is the core of Atari ST graphics programming but is notoriously hard to follow in bitplane-interleaved format.

```pseudocode
function hline():
    // Inputs: x1, x2 (start/end X), y1 (Y row), col (color 0-15)
    x1 = clamp(x1, 0, 319)
    x2 = clamp(x2, 0, 319)

    screen = _v_bas_ad + y1 * 160           // scanline base address
    start_group = x1 / 16                   // which 16-pixel word-group x1 falls in
    end_group   = x2 / 16                   // which word-group x2 falls in
    screen += (x1 & ~15) / 2               // byte offset to starting word-group

    // Build start mask: bits set from (x1 mod 16) through bit 15
    start_mask = bittab[x1 & 15]            // e.g., x1=5 -> $07FF (bits 5-15 set)

    if start_group == end_group:
        // Single-word case: line fits within one 16-pixel group
        end_mask = bittab[x2 & 15]          // bits from (x2 mod 16) to 15
        start_mask &= NOT end_mask          // keep only bits between x1 and x2

    // Duplicate mask into both halves of a longword (for 2-word plane writes)
    mask_32 = start_mask | (start_mask << 16)
    inv_mask = NOT mask_32                  // bits to preserve from background

    // Look up 8-byte color pattern from coltab
    color_planes01 = coltab[col * 8 + 0]   // longword: plane0_word + plane1_word
    color_planes23 = coltab[col * 8 + 4]   // longword: plane2_word + plane3_word

    // --- Write first word-group (partial, masked) ---
    screen[0:3] = (screen[0:3] & inv_mask) | (color_planes01 & mask_32)  // planes 0+1
    screen[4:7] = (screen[4:7] & inv_mask) | (color_planes23 & mask_32)  // planes 2+3
    screen += 8

    if start_group == end_group: return     // single-word line: done

    // --- Write middle word-groups (full, no masking) ---
    for group = start_group + 1 to end_group - 1:
        screen[0:3] = color_planes01        // solid color, no read-modify-write needed
        screen[4:7] = color_planes23
        screen += 8

    // --- Write last word-group (partial, masked from the other side) ---
    end_mask = bittab[x2 & 15]             // bits FROM x2_bit TO 15
    end_mask_32 = NOT (end_mask | (end_mask << 16))  // invert: bits FROM 0 TO x2_bit
    end_inv = NOT end_mask_32
    screen[0:3] = (screen[0:3] & end_mask_32) | (color_planes01 & end_inv)
    screen[4:7] = (screen[4:7] & end_mask_32) | (color_planes23 & end_inv)
```

**Findings.** The `coltab` lookup is elegant: each of the 16 colors has a pre-computed 8-byte entry where all 4 bitplane words are either `$0000` or `$FFFF` depending on whether that plane's bit is set in the color index. For example, color 5 (binary 0101) has planes 0 and 2 set to `$FFFF` and planes 1 and 3 set to `$0000`. This allows the color to be applied to any region simply by ANDing with a position mask — no per-pixel color computation needed.

The middle-word loop (`hline0`) is the fast path: it writes 8 bytes per iteration with no read-modify-write (just `move.l d5,(a0)+; move.l d6,(a0)+`). For a full-width road line spanning ~200 pixels, this loop executes about 10 times, dominating the routine's cycle count. The partial first and last words are the slow path with their read-modify-write mask operations.

The `SWAP` trick (duplicating a word into both halves of a longword) appears here too: `move.w d0,d3; swap d0; move.w d3,d0` creates a longword with the same mask in both words. This is necessary because the Atari ST's 4-plane interleaved format stores planes 0+1 as one longword and planes 2+3 as the next — both need the same pixel mask applied.

## 6. Physics Model

The physics model governs how the car accelerates, steers, and interacts with curves. There is no real inertia simulation — instead, the system uses a set of interlocking counters (`getfak`, `speedfak`, `speed`, `rounds`, `gang`) that create the *feel* of acceleration and gear shifting. The curve system is the most interesting part: track data encodes curve direction and severity, and the physics engine converts this into lateral drift that pushes the car off the road if the player doesn't counter-steer.

### 6.1 Speed System

Four variables cooperate to control speed:

| Variable | Range | Meaning |
|----------|-------|---------|
| `getfak` | 0 (fastest) to `randtab2` (stopped) | Inverse speed factor — lower = faster |
| `speedfak` | 0 (stopped) to `randtab2-1` (fastest) | Direct speed — controls track advancement rate |
| `speed` | 0 to `getfak` | Animation counter — counts down each frame |
| `randtab2` | typically 15 | Maximum value, read from `randtab[0]` at init |

**Track advancement** works as a frame divider: each frame, `speed` decrements by 1. When it reaches 0, the track pointer (`a0`) advances by 1 byte in `aktseq`, and `speed` resets to `getfak`. This means:
- At `getfak=0`: track advances *every frame* (maximum speed)
- At `getfak=15`: track advances every 16th frame (near standstill)
- At `getfak=randtab2`: `speed == randtab2` and the comparison at `nocrash` immediately loops back without advancing (full stop)

```pseudocode
// Track advancement (called at end of each frame, source: nocrash/pl5)
function advance_track():
    if getfak == randtab2: return          // standstill: no movement
    speed -= 1
    if speed > 0: return                   // still counting down
    speed = getfak                         // reset counter
    track_pointer += 1                     // advance by 1 aktseq byte
```

**Initialization** (at `reinit`): `getfak = speed = randtab2` (= 15, standstill). The car starts stationary and must accelerate from zero.

### 6.2 Gears and RPM

The gear system provides 16 speed levels (4 gears × 4 RPM levels):

| Variable | Range | Meaning |
|----------|-------|---------|
| `gang` | 0-3 | Current gear (0 = lowest, 3 = highest) |
| `rounds` | 0-3 | Current RPM within the gear (0 = low, 3 = high) |

**Acceleration** (joystick up, no fire button): increments `rounds` and decrements `getfak` — each RPM step makes the car faster. When `rounds` reaches 3 (max RPM), further joystick-up has no effect until the player shifts up.

**Gear shifting** requires the fire button:
- **Shift up** (fire + up): only works when `rounds == 3` (max RPM). Sets `gang += 1`, `rounds = 0`. This means you lose speed temporarily — the RPM drops to 0 in the new gear, and `getfak` stays where it was. You must accelerate again to reach max RPM in the higher gear.
- **Shift down** (fire + down): only works when `rounds == 0` (min RPM). Sets `gang -= 1`, `rounds = 3`.

**Braking** (`decspeed` routine): decrements `rounds`, increments `getfak` (slower), and decrements `speedfak` (less track advancement). Each call does one step.

```pseudocode
function decspeed():
    if rounds > 0 AND getfak < randtab2:
        rounds -= 1                        // decrease RPM
        getfak += 1                        // slower (inverse speed)
        speed = getfak                     // reset frame counter
        update_engine_sound()
        update_speedometer()
    if speedfak > 0:
        speedfak -= 1                      // less track advancement
```

**Engine sound**: each gear has a frequency table (`gang0`–`gang3`). Within each gear, the 4 RPM levels select different tone periods. Channel A and B are set to slightly different frequencies (detuned by 40), creating a richer engine sound.

### 6.3 Steering and Lateral Position

Steering affects two things: the visual steering wheel position (`joydir`) and the car's lateral offset on the road (`xadd`).

| Variable | Range | Meaning |
|----------|-------|---------|
| `joydir` | -16 to +16 | Steering wheel angle (÷4 = display position -4..+4) |
| `xadd` | -300 to +300 | Lateral offset from road center (beyond ±300 = crash) |
| `scroll` | unbounded | Background scenery scroll position |
| `xadd2` | per-frame | This frame's lateral input (0 = no steering) |
| `scroll1` | per-frame | This frame's scroll delta |

**Per-frame steering input** (joystick left/right):

```pseudocode
function process_steering():
    xadd2 = 0; scroll1 = 0                // reset per-frame deltas

    if joy_left:
        joydir += 4                        // turn wheel left
        scroll += 1; scroll1 = -1          // scroll scenery
        steering_force = randtab2 - getfak + 4   // speed-dependent (min 4)
        xadd += steering_force             // push car left (positive = left)
        xadd2 = -4                         // record that we steered left

    if joy_right:
        joydir -= 4                        // turn wheel right
        scroll -= 1; scroll1 = +1
        steering_force = randtab2 - getfak + 4
        xadd -= steering_force             // push car right (negative = right)
        xadd2 = +4

    // Auto-center: steering wheel returns toward zero when released
    if joydir > 0: joydir -= 2            // decay toward center
    if joydir < 0: joydir += 2
```

The steering force formula `randtab2 - getfak + 4` means:
- At maximum speed (`getfak=0`): force = 15 + 4 = 19 pixels/frame
- At standstill (`getfak=15`): force = 0 + 4 = 4 pixels/frame
- Faster cars steer harder — this makes high-speed driving more sensitive and more dangerous.

### 6.4 Curve Physics (Lines 2377-2430)

This is the core of the driving model. Each track segment in `aktseq` has a curve value encoded in its lower nibble:

| Curve Value | Meaning | Example Components |
|-------------|---------|-------------------|
| 0 | Straight road | bau7, bau8, bau9, bau16, bau17, bau18 |
| +1 | Gentle right curve | bau4, bau12, bau13, bau14, bau15 |
| +2 | Sharp right curve | bau2, bau10, bau11 |
| -1 | Gentle left curve | bau3, bau5, bau6 |
| -2 | Sharp left curve | bau1 |

These values are the *raw* bytes in each `bauN` definition (e.g., bau1's sequence `0,-2,-2,0` means: enter straight, sharp left, sharp left, exit straight).

**The curve physics engine** runs once per frame and computes a lateral drift value that is added to `xadd`. The key variables:

- `d0` = curve value from current track segment (sign-extended 4-bit nibble)
- `d7` = speed-dependent index = `getfak + 1` (range 1-16)
- `xadd2` = whether the player steered this frame (from §6.3)

```pseudocode
function compute_curve_drift() -> drift:
    curve = sign_extend_4bit(current_segment & $0F)    // -8..+7
    speed_index = getfak + 1                            // 1 (fast) to 16 (stopped)

    if curve == 0:
        // STRAIGHT ROAD: car drifts back toward center
        // The further off-center (larger |xadd|), the stronger the pull-back
        drift = (xadd / 8) / speed_index
        // At high speed: small divisor -> stronger centering
        // At low speed: large divisor -> weaker centering (easier to stay off-center)
        return drift

    // CURVE: car drifts toward the outside of the curve
    if xadd2 != 0:
        // Player is actively steering this frame: use TIGHT response table
        factor = faktab[speed_index - 1]    // values 7,8,9,11,...,86
    else:
        // Player is NOT steering: use WIDE drift table (car slides more)
        factor = faktab2[speed_index - 1]   // values 14,16,18,22,...,172

    // Normalize: make curve positive, adjust factor sign to preserve direction
    if curve < 0:
        curve = -curve; factor = -factor

    // Select base constant by curve severity
    if curve == 1:
        base = 220                          // gentle curve
    else:
        base = 300                          // sharp curve (severity 2+)

    drift = base / factor                   // signed division
    return drift

// After computing drift:
if car_is_stationary:
    // Don't apply curve drift — only direct steering input
    xadd += xadd2                          // from joystick
else:
    xadd += drift                          // from curve physics
```

**Worked example** — Sharp right curve at maximum speed, player NOT steering:

1. `curve = +2` (sharp right), `speed_index = 1` (fastest)
2. Player not steering → use `faktab2`: `faktab2[0] = 14`
3. `curve >= 2` → `base = 300`
4. `drift = 300 / 14 = 21` (integer division)
5. `xadd += 21` each frame → car drifts left at 21 pixels/frame
6. After 15 frames: `xadd ≈ 315` → **crash!** (threshold is 300)

**Same curve, player actively counter-steering right:**

1. `curve = +2`, `speed_index = 1`
2. Player steering → use `faktab`: `faktab[0] = 7`
3. `drift = 300 / 7 = 42` — wait, this is *larger*?

Actually this reveals an important subtlety: when `factor` is positive (curve positive, player steering), the drift is positive (pushing left = into the curve). But the player is also adding a negative `xadd` via the joystick steering (from §6.3). So the net effect is:
- Curve drift: `xadd += 42` (pushing left, into curve)
- Steering force: `xadd -= 19` (pushing right, countering)
- Net: `xadd += 23` per frame — still drifting, but more slowly

The `faktab` values being smaller (= stronger drift) when steering seems counterintuitive. The key is that `faktab` is selected when the player IS steering, meaning the game applies a **stronger curve force** that the player must overcome with their steering input. This creates a more engaging driving feel — you feel the curve pulling you, and you actively fight it. With `faktab2` (not steering), the drift is weaker but you have no steering input to counter it, so you slide off more gradually.

**The faktab lookup tables** (16 entries each, indexed by speed 0-15):

```
faktab:  [  7,  8,  9, 11, 13, 18, 24, 30, 36, 43, 50, 57, 64, 71, 78, 86 ]
faktab2: [ 14, 16, 18, 22, 26, 36, 48, 60, 72, 86,100,114,128,142,156,172 ]
             ^                                                            ^
           fast (getfak=0)                                     slow (getfak=15)
```

At low speed, the large divisor produces tiny drift — curves barely affect you. At high speed, the small divisor produces large drift — curves are dangerous. `faktab2` values are approximately 2× `faktab` values, so passive drift is about half as strong as active-steering drift.

**Cross-reference notes.** The straight-road formula `(xadd / 8) / speed_factor` uses two chained `DIVS` with `ext.l` between them. The first `ext.l` sign-extends the 16-bit quotient to 32 bits for the second division — necessary because `DIVS` places the remainder in the high word, which would corrupt the second division without clearing it. The curve value sign-extension uses `or.w #$fff8,d0` for negative nibbles (bit 3 set), which sets bits 3-15 to 1, effectively sign-extending from 4 bits to 16 bits.

### 6.5 Crash Detection and Sequence (Lines 2755-2925)

Two crash triggers:
1. **Off-road**: `|xadd| >= 300` (too far from center)
2. **Sign collision**: `signrow > 64` AND sign exists AND `|xadd| > 140` (on sign side)

Edge friction: at `|xadd| >= 130`, plays edge scraping sound (`randsnd`) and gradually decelerates (every 10 frames via `slowfak` counter).

**Motivation.** The crash routine is the most dramatic event in the game and involves several complex hardware interactions: replacing the VBL handler, directly programming the video base address, running a palette rotation synchronized to the raster beam, and driving the explosion sound via Timer A — all while the normal game state is suspended. The pseudocode clarifies the temporal sequence.

```pseudocode
function crash():
    // Phase 1: Disable game rendering
    install leervbl as VBL handler      // leervbl = bare RTE (does nothing)

    // Phase 2: Show explosion image
    set dbaseh/dbasel = screen          // point video hardware at primary buffer
    memcpy(film, screen, 32000)         // copy pre-loaded explosion frame

    // Phase 3: Start explosion sound (runs independently via Timer A)
    settimer()                          // configures MFP Timer A with playexpl handler

    // Phase 4: Fire palette cycling animation (60 iterations)
    save current palette to stack
    load filmpal -> color0..color15     // explosion colors (reds, oranges)
    for i = 0 to 59:
        // Synchronize to raster position using movep on vcountmid
        wait until movep.w(vcountmid) matches target position

        // Rotate palette entries 1-8 left by 1 position
        // This creates a cycling fire effect: colors "flow" through the registers
        temp = color1
        color1 = color2;  color2 = color3;  ...  color8 = color9
        color9 = temp

        busy_wait(290 iterations)       // ~0.04ms delay between rotations
    restore filmpal                     // clean palette state
    long_delay($10000 iterations)       // ~0.5s to let player absorb the explosion

    // Phase 5: Restore normal state
    resettim()                          // stop explosion sound, restore MFP state
    memcpy(screen2, screen, 32000)      // restore cockpit from backup buffer
    restore saved palette from stack

    // Phase 6: Score penalty (BCD arithmetic)
    score = SBCD(score, $0030)          // subtract 30 decimal points
    if borrow: score = $0000            // clamp to zero

    // Phase 7: Reset car and resume
    xadd = 0; gang = 0; rounds = 0
    setsound(initmtr); setmotor()
    install vbl as VBL handler          // re-enable game rendering
    goto reinit                         // reset speed/steering, resume game loop
```

**Findings and cross-reference notes.**

*Palette rotation mechanics.* The rotation is synchronized to the raster beam via `movep.w 0(a3),d1` reading `vcountmid`+`vcountlow`, preventing mid-scanline color tearing. The actual rotation uses `movem.l $4(a2),d0-d3` which reads 4 longwords = 8 color registers (colors 2–9 as 4 longword pairs), then `movem.l d0-d3,2(a2)` writes them shifted down by one word position (to colors 1–8). The saved color 1 is placed at color 9 (`$12(a2)` = 18 bytes from color0 = color 9). This is a 9-entry circular buffer rotation, not 8 — confirmed by the source offsets.

*BCD score penalty.* The source uses `SBCD d0,d1` followed by `SBCD d3,d2` to subtract $0030 from the 2-byte packed BCD score. Per the 68000 reference, `SBCD` computes `destination - source - X_flag` in decimal. The X flag propagates the borrow between the two byte subtractions — this is why the subtraction works as a single 4-digit BCD operation split across two instructions. The initial `moveq.l #0,d3` ensures no spurious borrow is injected into the high byte subtraction (since `moveq` doesn't affect X). The `BCC` (Branch if Carry Clear) after the second `SBCD` checks whether the result underflowed below $0000; if so, both bytes are clamped to zero.

*Concurrent explosion sound.* The `settimer` routine saves the MFP 68901 state (registers `iera`, `ipra`, `isra`, `imra`, `tacr`, `vr` — all at odd byte offsets from the MFP base as per `atari.s`) and installs `playexpl` as the Timer A handler at vector $134. Timer A is configured with prescaler /4 and data $38 (56), giving an interrupt rate of 2.4576MHz / 4 / 56 ≈ 10,971 Hz — a sample rate suitable for the low-quality explosion sound effect. The `SEI` (Software End of Interrupt) mode is enabled via bit 3 of the `vr` register, requiring the handler to manually clear the in-service bit (`bclr #5,$fffa0f`) before returning — this prevents re-entrant interrupts.

*MFP register distinction.* The source saves and restores both `iera` (Interrupt Enable, at mfp+$7) and `imra` (Interrupt Mask, at mfp+$13). Per `atari.s`, these serve different roles in the MFP's interrupt pipeline: `iera` globally enables/disables each interrupt source, while `imra` masks which enabled interrupts actually reach the 68000 CPU. Both must be saved and restored because `settimer`/`prepdigi` modify both during sound setup.

## 7. Sound System

### 7.1 PSG Sound (YM2149)

The Atari ST's YM2149 Programmable Sound Generator is accessed via `$ff8800` (register select) and `$ff8802` (data write).

**setsound** (line 3114): Generic PSG writer. Takes pointer to register/value pairs terminated by -1. Special handling for register 7 (mixer): preserves bits 6-7 (I/O port direction) and only sets tone/noise enable bits.

**setmotor** (line 3148): Engine sound simulation.
- Uses `gangsnd` table to select frequency data based on current gear
- Within each gear, RPM (rounds 0-3) selects from 4 frequency pairs
- Sets channels 0 and 2 with slightly different frequencies for detuned engine sound

**randsnd** (line 5207): Edge/crash sound - sets channel C to noise-like tones

### 7.2 Digital Music Playback (Lines 3740-3850)

Uses MFP Timer A ($fffa00 region) for interrupt-driven playback:

**prepdigi** (line 3740):
1. Initialize all PSG volumes to max
2. Enter supervisor mode
3. Save MFP register state (interrupt enable, mask, timer control, vector)
4. Configure Timer A: prescaler=4, data=$48
5. Install `playmus` as Timer A interrupt ($134)
6. Clear playback state

**playmus** (line 3776): Timer interrupt handler
- Reads byte from current takt (segment) of `digisnd`
- Uses `loudtab` (60 entries) to convert sample byte to 3-channel PSG register writes
- `loudtab` entries are 12 bytes each: 3 longwords written directly to `$ff8800` (movem.l d1-d3,$ff8800)

**nxttakt2** (line 3827): Advances to next music segment using `taktabl2` offset table. Loops when reaching end marker (-1).

**Motivation for pseudocode.** The `playmus2` routine is called at up to ~8,500 Hz from a Timer A interrupt. Its job is to convert one byte from the raw music data into PSG register writes for 3 sound channels. The byte-to-register mapping via `loudtab` involves a non-obvious index calculation: `(byte & $FC) * 3`, which provides 64 entries of 12 bytes each — pre-computed PSG register/value pairs that are blasted to the hardware via `movem.l`. This is essentially a 64-level waveform lookup table that maps a single sample byte to a 3-channel volume/frequency configuration.

```pseudocode
function playmus2():
    // Advance through music data, loading next segment if needed
    if takt2 >= taktend2:                    // reached end of current segment?
        nxttakt2()                           // load next segment from taktabl2

    sample = *takt2++                        // read one byte from digisnd buffer

    // --- Convert sample to loudtab index ---
    // The sample byte's upper 6 bits select one of 64 loudtab entries.
    // Each entry is 12 bytes (3 longwords): pre-packed PSG register/value pairs.
    //
    // Index math: (sample & $FC) then multiply by 3
    //   - AND $FC clears bits 0-1 (aligns to 4-byte boundary): gives 0,4,8,...,252
    //   - Multiply by 3: index = value + value*2 = 12-byte stride
    //   This maps 64 possible values (0..252 step 4) to offsets 0..756 in loudtab
    index = sample & $FC                     // 0, 4, 8, ..., 252 (64 values)
    offset = index + index * 2               // × 3 = 0, 12, 24, ..., 756

    // Load 3 longwords from loudtab (pre-computed PSG register/value pairs)
    // Each longword is: [register_number << 24 | 0 | 0 | value]
    //   d1 = channel A (giaamp, register 8)
    //   d2 = channel B (gibamp, register 9)
    //   d3 = channel C (gicamp, register 10)
    d1, d2, d3 = loudtab[offset : offset+12]

    // Boost volume by adding $300 to each channel's low word
    // This increases the volume field without affecting the register number
    d1.low += $300
    d2.low += $300
    d3.low += $300

    // Write all 3 channels to PSG in one atomic instruction
    // movem.l d1-d3,$ff8800 writes 12 consecutive bytes to the PSG:
    //   Byte 0 -> giselect (register number)
    //   Byte 2 -> giwrite (value)
    //   ...repeated for all 3 registers
    movem.l d1-d3 -> giselect               // 3 register/value writes in one shot
```

**Segment management** (`nxttakt2`):

```pseudocode
function nxttakt2():
    entry_index = t2[takptr2]               // read from sequence array
    if entry_index == -1:                    // end of sequence?
        takptr2 = 0; retry                   // loop back to start

    // Each taktabl2 entry is 2 longwords: [start_offset, end_offset]
    // Offsets are relative to digisnd buffer base
    takt2    = digisnd + taktabl2[entry_index * 4]      // segment start
    taktend2 = digisnd + taktabl2[entry_index * 4 + 4]  // segment end
    takptr2++
```

**Findings.** The `movem.l d1-d3,$ff8800` instruction is the most creative hardware trick in the sound system. The YM2149 PSG has two I/O ports at `$ff8800` (register select) and `$ff8802` (data write). When `movem.l` writes 12 bytes to `$ff8800`, the bytes land at addresses `$ff8800`, `$ff8801`, `$ff8802`, `$ff8803`, `$ff8804`, etc. Due to the YM2149's address decoding, only even addresses matter: byte at `$ff8800` selects the register, byte at `$ff8802` writes the value. Bytes at `$ff8801` and `$ff8803` hit unconnected address lines and are ignored. So each longword write effectively performs one "select register, write value" operation. Three longwords = three PSG registers set in a single `movem.l` — roughly 32 cycles instead of the ~60 cycles needed for three separate register-select-then-write sequences.

The `loudtab` itself is a 64-entry waveform table. The entries range from silence (entry 0: all volumes 0) through increasing loudness combinations across 3 channels, up to maximum volume (entry 63: all channels at max). The `+$300` volume boost at playback time adjusts the baseline — suggesting the `loudtab` was authored for a quieter overall level and the game applies a runtime gain stage.

### 7.3 Explosion Sound (Lines 3580-3710)

Same mechanism as digital music but uses Timer A with `playexpl` handler:
- Reads from `explsnd` buffer
- Uses `taktable` for segment offsets
- Each byte's upper nibble = duration, lower nibble = volume
- Sets all 3 PSG volume registers to the same value

## 8. Display and HUD

### 8.1 Dashboard Elements

All HUD sprites are stored in `datascr1` (loaded from dashbord.pi1, but sprite area only):

| Element | Position | Source Offset | Size |
|---------|----------|---------------|------|
| Score digits | (89, 161) + (105, 161) | datascr1+0 | 10 digits, 8x10 each |
| Lap number | (108, 177) | datascr1+80 | Digits 0-9, 8x10 each |
| Total laps | (108, 188) | datascr1+80 | Same digit sprites |
| Speed gauge | (201, 158) + (217, 158) | datascr1+1600 | 2x(16x15) per position, 13+13 positions |
| Gear indicator | (207, 186) | datascr1+20160 | 4 gears, 16x8 each |
| Steering wheel | (132, 154) | datascr1+6400 | 9 positions, 4x(16x43) each |

### 8.2 Score System (`setscore`, lines 3244-3290)

- Score starts at 9998 (BCD: $9998)
- Every 3 frames, score decreases by 2 (BCD subtraction)
- Crash penalty: -30 points
- Score is displayed as 4 BCD digits using sprite composition

**dezspr** (lines 3303-3335): Extracts tens and units nibbles from BCD byte, looks up 8-pixel-wide digit sprites from datascr1, composites them into `sprwork1` buffer.

**Motivation for pseudocode.** `dezspr` is a compact routine (30 lines) that packs two conceptually separate operations — digit lookup and horizontal compositing — into a single pass. The key trick is the `LSR.L #8` which shifts the units digit right by exactly 8 pixels (one byte in bitplane terms), causing it to merge seamlessly with the tens digit when OR'd together. Understanding this requires knowing that in the Atari ST's bitplane format, an 8-pixel horizontal shift corresponds to a 1-byte shift within a longword of interleaved plane data.

```pseudocode
function dezspr(bcd_byte):
    // Input: d0 = packed BCD byte (e.g., $93 = digits 9 and 3)
    // Output: sprwork1 filled with 10 lines of composite 16px-wide sprite

    tens_nibble  = (bcd_byte & $F0) >> 1    // $90 >> 1 = $48 = byte offset for digit 9
    units_nibble = (bcd_byte & $0F) << 3    // $03 << 3 = $18 = byte offset for digit 3

    tens_ptr  = datascr1 + tens_nibble      // 8px-wide digit sprite, 160-byte stride
    units_ptr = datascr1 + units_nibble
    output    = sprwork1                    // 160-byte stride output buffer

    // Pass 1: Copy tens digit into output (left 8 pixels)
    for line = 0 to 9:
        output[0:3] = tens_ptr[0:3]         // planes 0+1 (4 bytes)
        output[4:7] = tens_ptr[4:7]         // planes 2+3 (4 bytes)
        tens_ptr += 160; output += 160

    // Pass 2: Overlay units digit (right 8 pixels, shifted right by 8)
    output = sprwork1                       // reset to start
    for line = 0 to 9:
        planes01 = units_ptr[0:3]           // read as longword
        planes01 >>= 8                      // shift right 8 pixels = 1 byte
        output[0:3] |= planes01             // OR onto tens digit (merge)

        planes23 = units_ptr[4:7]
        planes23 >>= 8
        output[4:7] |= planes23

        units_ptr += 160; output += 160
```

**Findings.** The offset calculations exploit the Atari ST screen format. Digit sprites are stored at the start of `datascr1` in standard screen layout: each digit is 8 pixels wide (= 1 word per plane = 2 bytes per plane × 4 planes = 8 bytes per line). For the tens digit, `($F0 >> 1)` works because `$F0 / 16 * 8 = nibble_value * 8`, and since the high nibble is already shifted left by 4, dividing by 2 gives `nibble_value * 8`. For the units digit, `(nibble & $0F) << 3` is simply `nibble_value * 8`. Both produce byte offsets into the same digit sprite strip.

The `LSR.L #8` (shift longword right by 8 bits) is the critical compositing step. In the Atari ST's interleaved format, a longword at a word-group boundary contains two consecutive bitplane words. Shifting right by 8 moves the pixel data exactly 8 pixel positions to the right within that longword — because each bitplane word represents 16 pixels, and 8 bits = 8 pixels in a single-plane context. The OR merge then combines the shifted units digit with the already-placed tens digit, producing a clean 16-pixel-wide composite without any overlap artifacts (since digit sprites have transparent right halves).

### 8.3 Raster Split

The VBL handler creates a mid-screen palette split: scenery colors for rows 0–70 (sky), game colors for rows 71–199 (road + dashboard). The switch is timed by busy-waiting on `vcountmid` via `MOVEP.W`, then blasting all 16 colors via `movem.l` in a single instruction. This gives the visual effect of two independent 16-color palettes on a single screen — effectively 32 colors total. See **Section 5.4.4** for the full VBL pseudocode and timing analysis.

### 8.4 Text Rendering System (`palprint` / `hiprint`)

**Motivation for pseudocode.** `palprint` is the most unusual routine in the game — a custom text renderer that produces gradient-colored text using the Line-A text blit (`$A008`). Instead of rendering each character in a single color, it cycles through 4 descending color indices per "word" (4-character group), creating a shimmering gradient effect. Special marker characters (`"` and `!`) switch between two color palettes. The routine also handles page overflow (waiting for a keypress and clearing the screen when text fills the display). This is used for the game-over screen, lap/player selection prompts, and high score entry.

`hiprint` is a simpler variant that uses a fixed color (12) and skips the palette setup — used for displaying high scores over the `hiscore.pi1` background.

```pseudocode
function palprint(text_ptr):
    // Set custom text palette (prpal: 16 colors for gradient text)
    write prpal colors 2-15 to color2..color15
    write prpal color 1 to color1

    x = 0; y = 0                             // pixel position
    color_mode = 4                           // start: colors 4,3,2,1

    while true:
        char_in_word = 3                     // 4 chars per "word" (0-based counter)
        current_color = color_mode           // reset color at word start

        ch = *text_ptr++
        if ch == 0: return                   // null terminator
        if ch == $0D: goto new_line          // carriage return
        if ch == '"':                        // quote = bright mode marker
            color_mode = 4; continue         // colors 4,3,2,1
        if ch == '!':                        // exclamation = dim mode marker
            color_mode = 12; continue        // colors 12,11,10,9

        // --- Render SAME character 4 times with descending colors ---
        // This creates a 4-shade gradient per character (e.g., 4→3→2→1)
        while char_in_word >= 0 AND ch >= $20:  // printable characters only
            prprint(ch, x, y, current_color) // Line-A $A008 text blit
            x += 1; y += 1                   // advance position (sub-pixel shift)
            current_color -= 1               // gradient: color decreases per copy
            char_in_word -= 1
            // NOTE: ch is NOT re-read — the same character is printed 4 times
            // each time slightly offset and in a darker color, creating a
            // shadow/gradient effect per character

        // Inter-word gap
        x += 5; y -= 4                      // add gap, undo Y sub-pixel shifts
        if x >= 320: goto new_line
        continue                             // next word

    new_line:
        x = 0
        color_mode = 12                      // new lines start in dim mode
        y += 12                              // line height = 12 pixels
        if y >= 188:                         // screen full?
            wait_for_keypress()              // GEMDOS Crawcin
            clear_screen()
            x = 0; y = 0                    // restart from top
```

**Findings.** The text rendering does *not* print different characters per gradient step — it prints the **same character 4 times**, each time offset by 1 pixel in X and Y and in a progressively darker color. This creates a diagonal shadow/gradient effect per character: the brightest copy is at the original position, and 3 darker copies trail below-right. The result is a beveled or embossed text appearance — a popular visual style in 1980s demo scene and game UI.

The X/Y sub-pixel advancement (+1 per copy) combined with the Y retreat (-4 at word boundary) means the net per-character advance is: X += 1 (from the shadow copies) + 5 (inter-word gap) / 4 copies ≈ 2.25 pixels per character on average. The effective character pitch is determined by the Line-A 8×8 font width plus these sub-pixel shifts. The Y-advances per copy (+1 each) are undone at the word boundary (-4), so the net Y advance is 0 within a word — only the explicit `+12` at `cr` advances to the next line.

The page-overflow handling saves all registers including SP into a fixed buffer (`movem.l d0-a7,saver`) rather than using the stack. This is necessary because `GEMDOS Crawcin` is a blocking system call that may modify the stack. Saving to a fixed buffer guarantees the complete register state survives across the trap.

## 9. File Formats

### 9.1 Track Files (.SEQ extension equivalent)

Actually have no fixed extension - the user types the full filename. Internally treated as raw binary:
- 162 bytes: `playdat` grid data (18 columns x 9 rows)
- 2 bytes: `aktscene` value (selected scenery 0-2) at offset 162
- Total: 164 bytes

### 9.2 High Score Files (.TOP extension)

ASCII text with embedded control characters:
- 7 CR characters (line spacing)
- 6 entries, each formatted as: `    Nth...Name.............Score\r\n`
- Each entry: rank label (4 chars), "...", name (padded with dots to position 18), "..", 4-digit score
- Total: ~206 bytes
- Offset table `hitab`: byte offsets within hiscore string for each rank's name start

### 9.3 PI1 Image Files

Standard Atari ST Degas format:
- 2 bytes: resolution (0 = low)
- 32 bytes: palette (16 colors, 3 bits per RGB component, word-sized)
- 32,000 bytes: screen data (4 interleaved bitplanes)
- Total: 32,034 bytes

The game loads these at (buffer - $22) to capture the palette, then uses the palette and screen data separately.

## 10. TOS System Calls Used

### 10.1 GEMDOS (Trap #1)

| Function | Number | Usage |
|----------|--------|-------|
| Pterm0 | $00 | Exit program |
| Cconws | $09 | Print string (`print` routine) |
| Cconin | $07 | Read character (blocking) |
| Fsetdta | $1a | Set DTA for file search |
| Fcreate | $3c | Create file (`save`) |
| Fopen | $3d | Open file (`load`) |
| Fclose | $3e | Close file |
| Fread | $3f | Read from file |
| Fwrite | $40 | Write to file |
| Fsfirst | $4e | Search first file (file browser) |
| Fsnext | $4f | Search next file |
| Mshrink | $4a | Release unused memory |
| Super | $20 | Enter/leave supervisor mode |

### 10.2 XBIOS (Trap #14)

| Function | Number | Usage |
|----------|--------|-------|
| Physbase | $02 | Get physical screen address |
| Logbase | $03 | Get logical screen address |
| Getrez | $04 | Get current resolution |
| Setscreen | $05 | Set screen addresses/resolution |
| Setpalette | $06 | Set 16-color palette |
| Random | $11 | Generate random number (sign placement) |
| Ikbdws | $19 | Set IKBD command string (mouse/joystick mode) |
| Kbdvbase | $22 | Get keyboard vector table (for joystick port 1 IRQ) |
| Vsync | $25 | (indirectly, via VBL) |

### 10.3 AES/VDI (Trap #2)

| Function | Purpose |
|----------|---------|
| appl_init (AES 10) | Initialize application |
| v_opnvwk (VDI 100) | Open virtual workstation |
| v_clsvwk (VDI 101) | Close workstation |
| v_clrwk (VDI 3) | Clear workstation |
| vq_mouse (VDI 124) | Query mouse position/button |
| graf_handle (AES 77) | Get graphics handle |
| graf_mouse (AES 78) | Set mouse form |

### 10.4 Line-A

| Opcode | Purpose |
|--------|---------|
| $A000 | Line-A init (get variable/font pointers) |
| $A005 | Filled rectangle (fill_rec for XOR feedback) |
| $A008 | Text blit (prprint for character rendering) |

### 10.5 Direct Hardware Access

The following table uses official Atari ST SDK symbol names (from `atari.s`) alongside the raw addresses:

| Address | Symbol | Purpose |
|---------|--------|---------|
| `$ffff8201` | `dbaseh` | Video RAM base address high byte |
| `$ffff8203` | `dbasel` | Video RAM base address low byte |
| `$ffff8205` | `vcounthi` | Video display counter high byte |
| `$ffff8207` | `vcountmid` | Video display counter mid byte |
| `$ffff820a` | `syncmode` | Video sync mode (bit 1: 0=60Hz NTSC, 1=50Hz PAL) |
| `$ffff8240` | `color0` | Color palette register 0 (background) |
| `$ffff8242`..`$ffff825e` | `color1`..`color15` | Color palette registers 1-15 |
| `$ffff8800` | `giselect` / `giread` | PSG (YM2149) register select (W) / read data (R) |
| `$ffff8802` | `giwrite` | PSG write data |
| `$fffffa07` | `iera` | MFP Interrupt Enable Register A |
| `$fffffa09` | `ierb` | MFP Interrupt Enable Register B |
| `$fffffa0b` | `ipra` | MFP Interrupt Pending Register A |
| `$fffffa0f` | `isra` | MFP Interrupt In-Service Register A |
| `$fffffa13` | `imra` | MFP Interrupt Mask Register A |
| `$fffffa17` | `vr` | MFP Vector Register (SEI mode bit) |
| `$fffffa19` | `tacr` | MFP Timer A Control Register |
| `$fffffa1f` | `tadr` | MFP Timer A Data Register |
| `$fffffc02` | `keybd` | Keyboard ACIA data register (raw scancodes) |
| `$44e` | `_v_bas_ad` | TOS variable: logical screen base address |
| `$484` | `conterm` | TOS variable: console terminal control (keyboard click) |
| `$70` | — | 68000 exception vector: VBL (level 4 autovector) |
| `$134` | — | MFP Timer A interrupt vector |

**PSG Register Names** (from `atari.s`):

| Register | Symbol | Purpose |
|----------|--------|---------|
| 0 | `gitoneaf` | Channel A fine tune |
| 1 | `gitoneac` | Channel A coarse tune |
| 2 | `gitonebf` | Channel B fine tune |
| 3 | `gitonebc` | Channel B coarse tune |
| 4 | `gitonecf` | Channel C fine tune |
| 5 | `gitonecc` | Channel C coarse tune |
| 6 | `ginoise` | Noise generator period |
| 7 | `gimixer` | Mixer/I/O control |
| 8 | `giaamp` | Channel A amplitude |
| 9 | `gibamp` | Channel B amplitude |
| 10 | `gicamp` | Channel C amplitude |
| 11-12 | `gifienvlp`/`gicrnvlp` | Envelope period |

## 11. High Score System (Detail)

### 11.1 Score Sorting (`calc_hi`)

The `calc_hi` routine processes all players' scores in descending order using a bitfield (`sortfl`) to track which players have been handled:

```pseudocode
function calc_hi():
    start_digital_music()
    sortfl = 0  // bitmask: bit N set = player N already processed
    
    for pass = 0 to 3:
        best_score = 0
        best_player = none
        
        for player = 1 to 4:
            if sortfl bit (player-1) is set: skip  // already processed
            if plscore[player] >= best_score:
                best_score = plscore[player]
                best_player = player
        
        sortfl |= (1 << (best_player - 1))  // mark as processed
        tstscore(best_score, best_player)     // check against leaderboard
```

### 11.2 Score Ranking (`tstscore`)

Only checks high scores for 1-lap races (`nrlaps == 1`). Compares the BCD score against all 6 existing entries:

```pseudocode
function tstscore(score_bcd, player_char):
    if nrplayer < player_char: return  // only check active players
    if nrlaps != 1: return             // only 1-lap games record scores
    
    for rank = 0 to 5:
        existing = read_4_ascii_digits(hiscore, hitab[rank] + 18)
        if score_bcd > existing:
            getscore(rank, score_bcd, player_char)
            return
```

### 11.3 High Score Entry (`getscore`)

When a player's score qualifies, this routine:
1. Displays "Player X, please enter your name for the Nth rank"
2. Prompts for name via `getname` (up to 16 characters)
3. Shifts all lower-ranked entries down by one position (23 bytes each)
4. Inserts the new name and converts BCD score to 4 ASCII digits
5. Saves the updated `.TOP` file to disk immediately
6. If rank is #1: loads and displays `champion.pi1` with a long delay

```pseudocode
function getscore(rank, score, player_char):
    clear_screen()
    install_color_cycling_vbl()  // lapvbl for pulsing effect
    display("Player {player_char}, enter name for {rank+1}. rank")
    name = getname()  // up to 16 chars, Return to confirm
    
    // Shift lower ranks down
    for i = 4 downto rank+1:
        copy 23 bytes from hitab[i] to hitab[i+1] in hiscore
    
    // Insert new entry
    write name at hitab[rank] in hiscore, pad with spaces to dots
    write 4 ASCII digits of score at hitab[rank]+18
    save hiscore to disk as .TOP file
    
    if rank == 0:  // new champion!
        load and display champion.pi1
        long_delay($100000 iterations)
```

### 11.4 Score in File Format

High scores are stored as ASCII text. Each entry is exactly 23 characters:
```
"    1st...Name_here.....XXXX\r"
     ^     ^              ^
     |     hitab[0]+0     hitab[0]+18 = 4 ASCII score digits
     7 leading CRs
```

The 4 score digits are converted from packed BCD by extracting each nibble via `LSR.W` and masking with `AND.L #$f`, then OR'ing with `$30` (ASCII `'0'`). The source does this with four extraction sequences (lines ~4465–4483): `lsr.w #6,d1; lsr.w #6,d1` (effectively shift right by 12 for the thousands digit), then `lsr.w #8`, `lsr.w #4`, and the raw low nibble for hundreds, tens, and units respectively.

**Cross-reference note on `SBCD` chaining.** The score subtraction in `setscore` uses `SBCD d0,d1; SBCD d3,d2` where `d3=0`. Per the 68000 reference, `SBCD` computes `dest - src - X`, so the borrow from the first subtraction (stored in X) propagates to the second. The `moveq.l #2,d0` that loads the subtraction value does *not* affect the X flag (verified: `MOVEQ` modifies N, Z, V, C but **not X**), ensuring no spurious borrow is introduced. This is a subtle but critical detail — using `move.w #2,d0` instead would also be safe (it doesn't affect X either), but `moveq` is preferred because it's 2 bytes and 4 cycles vs 4 bytes and 8 cycles.

## 12. Multiplayer System

The game supports 1-4 players in hot-seat mode:
1. After PLAY is selected, `askplay` prompts for player count (joystick left/right to select 1-4)
2. Players take turns racing the same track
3. After each player's race ends (all laps complete), their score is stored in `plscore` array
4. `nrplay1` tracks the current player index
5. After all players finish, `calc_hi` processes scores in descending order to check for high score rankings

## 13. Pause and Abort

### 13.1 Pause (Space bar, scancode $39)

Detected by directly reading the keyboard ACIA data register (`keybd` = `$fffc02`).

```pseudocode
function handle_pause():
    save all registers
    setsound(initdat)           // max volume for pause music
    disable_interrupts()
    
    // Get physical screen address from hardware
    phys_screen = (dbaseh << 16) | (dbasel << 8)
    clear road area (2840 longwords from phys_screen)
    copy pause image: signscr2+10400 -> phys_screen+2400 (38 lines)
    
    // Start pause music via Timer A
    tacr = 1 (prescale /4), tadr = $48 (count 72)
    enable Timer A interrupt
    
    wait for Space release
    loop:
        playmus2()                  // process one music sample
        wait for Timer A interrupt (poll isra bit 5)
        clear isra bit 5
        if Space pressed: break
    wait for Space release
    
    // Resume
    setsky()                    // redraw scenery
    setsound(initsnd)           // silence
    setsound(initmtr)           // restart engine sound
    enable_interrupts()
    restore all registers
```

**Cross-reference note.** The pause music loop is unusual: instead of running `playmus` via Timer A interrupts (as during the title screen), it calls `playmus2` from the main loop and uses Timer A only as a timing source. The loop polls `btst #5,$fffa0b` (bit 5 of `ipra` = Timer A interrupt pending), waits for it to become set, clears it manually with `move.b #$df,$fffa0b`, then calls `playmus2` to process one sample. This polling approach avoids the complexity of saving/restoring the game's interrupt state (which would conflict with the VBL handler). The Timer A prescaler is set to /4 with data $48 (72), giving an interrupt rate of 2.4576MHz / 4 / 72 ≈ 8,533 Hz — slightly lower than the explosion sound rate, producing a more mellow music playback.

### 13.2 Abort (Undo key, scancode $61)

The Undo key on the Atari ST has scancode `$61` (often mapped as ESC in games). When pressed:
1. Restores original VBL vector from stack
2. Restores MFP Timer A/B control registers (`reg79`)
3. Silences PSG
4. Resets video to primary screen (`_v_bas_ad`, `dbaseh`, `dbasel`)
5. Jumps to `abort` which returns to user mode and restores editor palette

## 14. Key Data Tables Summary

| Table | Location | Entries | Purpose |
|-------|----------|---------|---------|
| `fakttab` | Line 4938 | 70 words | Line repetition counts for perspective |
| `randtab` | Line 4950 | 100+ bytes | Edge color band duration by distance |
| `faktab` | Line 5330 | 16 bytes | Curve response when steering (tighter) |
| `faktab2` | Line 5336 | 16 bytes | Curve drift when not steering (wider) |
| `rowtab` | Line 5180 | 70 words | Road width variation per row |
| `coltab` | Line 4985 | 16x4 words | Bitplane patterns for each color |
| `bittab` | Line 5006 | 16 words | Left-edge masks for pixel operations |
| `bittab2` | Line 5052 | 16 words | Right-edge masks for sprite overlap |
| `steertab` | Line 5073 | 9 longs | Steering wheel sprite offsets |
| `signrtab` | Line 5094 | 100+ bytes | Sign size index by distance |
| `signlen` | Line 5091 | 9 words | Sign widths in pixels (16/32/64) |
| `signoffs` | Line 5089 | 9 longs | Sign sprite data offsets |
| `loudtab` | Line 5244 | 60x12 bytes | Digital sound PSG register patterns |
| `playtab` | Line 4841 | 18 longs | Pointers to component definitions |
| `offs` | Line 4851 | 9 words | Grid offset for each direction |

## 15. File Dependencies

| File | Loaded At | Destination | Purpose |
|------|-----------|-------------|---------|
| heavy.seq | Startup | digisnd | Title/pause music (78KB) |
| title.pi1 | Startup | screen | Title screen |
| dashbord.pi1 | Startup | screen2, then datascr1 | Dashboard + sprite data |
| signs.pi1 | Startup | signscr1 | Billboard sprites set 1 |
| signs2.pi1 | Startup | signscr2 | Billboard sprites set 2 + scenery |
| film.pi1 | Startup | film | Crash/explosion animation |
| expl.snd | Startup | explsnd | Explosion sound effect |
| trcs.pi1 | Startup | pic | Track editor background |
| hiscore.pi1 | End of game | screen | High score display background |
| champion.pi1 | New #1 score | screen | Champion celebration screen |
| default | Startup | playdat | Default track layout |
| default.top | Startup | hiscore | Default high scores |
| user files | On demand | playdat/hiscore | User-saved tracks and scores |

## 16. Notable 68000 Programming Techniques

A summary of hardware-specific tricks used throughout the game. Each is explained in detail in the referenced pseudocode section.

| Technique | Where Used | Detail In |
|-----------|-----------|-----------|
| **Y×160 via shifts** | `set16spr`, `setsign`, `hline` | `((Y<<1 + Y<<3)<<4)` avoids slow `MULU` — §5.5 |
| **BCD arithmetic (SBCD)** | Score system | Packed BCD with X-flag borrow propagation — §6.5, §11.4 |
| **Movem.l block fill** | Grass rendering | 44 bytes/instruction, 4 instructions per 160-byte line — §3.3 |
| **ROXR carry chains** | Scenery pre-shifting | 20-word chains with X-flag propagation and wraparound — §5.4.5 |
| **Raster split** | VBL handler | `movem.l` palette blast timed to `vcountmid` via `MOVEP.W` — §5.4.4 |
| **MOVEP.W** | VBL, crash, buffer swap | Reads byte-wide peripheral registers into word — §5.4.4, §5.1 |
| **32-bit sprite shift** | `set16spr`, `setsign` | `LSL.L` + `SWAP` for sub-pixel positioning — §5.5, §5.5 |
| **Stack-based parameters** | All sprite routines | Read via `4(sp)`, `6(sp)` etc., avoiding register conventions |
| **Pre-decrement write** | `set16spr`, `setsign` | `-(a3)` walks backward through bitplanes — §5.5 |
| **Division by subtraction** | `build` | Faster than `DIVU` for small values (max 9 iterations) — §3.1 |
| **Movem.l to PSG** | `playmus2` | 3 register/value pairs via 12-byte write to `giselect` — §7.2 |
| **In-place string patching** | `opndsk`, `palprint` | VT52 cursor strings modified before `print` — §3.1, §8.4 |

## 17. Surprise Findings

### 17.1 Scenery Palette Mismatch (Likely Bug)

The scenery selection menu (`scentxtp`) maps:
- aktscene 0 → `scen1txt` (highlights **"Rising Sun/City"**)
- aktscene 1 → `scen2txt` (highlights **"High Noon/City"**)
- aktscene 2 → `scen3txt` (highlights **"Alps/Village"**)

But the palette table (`paladdr`) maps:
- aktscene 0 → `scen1pal` (Rising Sun palette) ✓
- aktscene 1 → **`scen3pal`** (Alps palette!) ✗
- aktscene 2 → **`scen2pal`** (High Noon palette!) ✗

This means selecting "High Noon/City" in the menu actually uses the Alps/Village color palette, and vice versa. The scenery bitmap source (`scenaddr`) has the same swapped order. This is likely a bug where entries 1 and 2 were accidentally transposed in `paladdr` and `scenaddr`, but it's consistent across both tables so the game works — just with swapped visuals for sceneries 2 and 3.

### 17.2 Kbdvbase Stack Bug

In the `main` routine, after calling XBIOS Kbdvbase ($22):
```asm
    move.w  #34,-(sp)       ; XBIOS Kbdvbase
    trap    #$e
    addq.l  #2,-(sp)        ; BUG: should be addq.l #2,sp
```
The `-(sp)` pre-decrement pushes 2 more bytes onto the stack instead of cleaning up. This is a bug that happens to be harmless because the extra word on the stack doesn't affect subsequent operations (the stack eventually gets cleaned by the supervisor mode switch).

### 17.3 Component Palette Has 19 Slots But Only 18 Components

The click3 handler checks for 19 components (indices 0-18), but there are only 18 `bau` definitions (bau1-bau18). Component 0 is the "empty" cell (no track piece). This means the palette displays an empty slot at position 0, and actual components are 1-18.

## 18. Pseudocode Coverage Summary

All significant algorithms now have pseudocode documentation. The following table lists every pseudocode block and its location:

| Routine | Section | Key Insight |
|---------|---------|-------------|
| Main game loop (`pl2`) | [3.3](#33-main-game-loop-pl2--pseudocode) | Frame pipeline: input → physics → rendering → crash check |
| Track generation (`generate`) | [4.2](#42-track-generation-generate-lines-1464-1556) | Path-following with automatic reversal detection |
| VBL scenery scroll (`vbl`) | [5.4.4](#544-vbl-scrolling--pseudocode) | Pre-shifted bitmap selection + raster split palette swap |
| Sprite rendering (`set16spr`) | [5.5](#55-sprite-rendering) | Sub-pixel shifting via 32-bit LSL + dual-buffer writes |
| Crash sequence (`crash`) | [6.5](#65-crash-detection-and-sequence-lines-2755-2925) | Concurrent Timer A sound + palette rotation |
| Scenery pre-shifting (`prep1-4`) | [5.4.5](#545-scenery-pre-shifting-prep1prep4--pseudocode) | ROXR carry chain across 20 words with wraparound |
| Double buffer swap (`noabort`) | [5.1](#51-double-buffering) | Three-variable swap + vcounthi sync polling |
| Sign rendering (`setsign`) | [5.5](#55-sprite-rendering) | Three-way clipping + auto-generated transparency mask |
| Horizontal line (`hline`) | [5.6](#56-horizontal-line-drawing-hline-lines-387-497) | Partial/full word rendering with coltab bitplane patterns |
| File browser (`opndsk`) | [3.1](#31-track-editor-mode) | GEMDOS Fsfirst/Fsnext with VT52 two-column layout |
| Grid rebuild (`build`) | [3.1](#31-track-editor-mode) | Component palette lookup via repeated subtraction |
| Score digits (`dezspr`) | [8.2](#82-score-system-setscore-lines-3244-3290) | LSR.L #8 compositing of two 8px digits into 16px |
| Text renderer (`palprint`) | [8.4](#84-text-rendering-system-palprint--hiprint) | 4-char gradient words with in-band color mode markers |
| Music player (`playmus2`) | [7.2](#72-digital-music-playback-lines-3740-3850) | movem.l PSG blast from 64-entry loudtab waveform table |
| Score sorting (`calc_hi`) | [11.1](#111-score-sorting-calc_hi) | Bitfield-tracked descending-order player processing |
| Score ranking (`tstscore`) | [11.2](#112-score-ranking-tstscore) | BCD comparison against 6-entry ASCII leaderboard |
| Score entry (`getscore`) | [11.3](#113-high-score-entry-getscore) | Rank insertion with downward shift of 23-byte entries |
| Pause handler | [13.1](#131-pause-space-bar-scancode-39) | Polled Timer A music + Space key debouncing |

## 19. Potential Improvements

This section identifies areas where the original 1987 code could be improved, modernized, or extended — informed by the reverse-engineering analysis. These range from bug fixes to gameplay enhancements to architectural changes.

### 19.1 Bug Fixes

| Issue | Section | Fix |
|-------|---------|-----|
| **Scenery palette/bitmap swap** | §17.1 | Swap entries 1 and 2 in both `paladdr` and `scenaddr` so menu labels match visuals |
| **Kbdvbase stack leak** | §17.2 | Change `addq.l #2,-(sp)` to `addq.l #2,sp` (one character fix) |
| **X flag not cleared before ROXR** | §5.4.5 | Insert `andi #$ffef,ccr` before each ROXR chain to guarantee X=0. Currently harmless in practice but fragile |

### 19.2 Physics and Algorithm Improvements

**Smoother curve model.** The current curve system uses only 5 discrete values (-2, -1, 0, +1, +2) per track segment. This produces abrupt transitions between straight and curved sections — the curve "snaps on" rather than building gradually. A smoother approach: interpolate between consecutive segment values using a simple linear ramp (e.g., over 3-4 scanlines) instead of switching instantly. This would require a small look-ahead buffer but no changes to the track data format, since the interpolation happens at render time.

**Speed-dependent curve entry.** Currently, entering a curve at any speed applies the same base drift (220 or 300), scaled only by `faktab[speed]`. In real racing, entering a sharp curve at high speed is dramatically worse than at low speed. A more realistic model would multiply the base by a speed factor: `base * (1 + (max_speed - getfak) / max_speed)`, making high-speed curve entry roughly twice as punishing as low-speed entry. The current `faktab` table already provides speed scaling, but it's a single dimension — this would add a second dimension.

**Inertia / momentum.** The car has no momentum — releasing the accelerator causes instant deceleration via the `speed` counter mechanism. Adding a momentum variable that decays gradually (e.g., `speedfak -= 1` every N frames when not accelerating, instead of stopping `speedfak` advancement immediately) would create a more realistic coasting feel. The `decspeed` routine (§6.2) would be the right place: instead of immediately decrementing `rounds` and `getfak`, decay them on a timer.

**Lateral inertia (drift).** When the player releases the steering, `joydir` decays by 2 per frame toward zero — but `xadd` has no inertia at all. On straight road, `xadd` decays via `(xadd / 8) / speed_factor`, which is purely position-based, not velocity-based. Adding a `xvel` (lateral velocity) variable that decays independently would create a drifting effect: the car continues sliding sideways after releasing the stick, especially at high speed. This is the single change that would most improve the driving feel.

**Non-linear perspective.** The road perspective uses `curve_accum / (2*row + 1)` — a linear relationship between row number and perspective divisor. Real perspective is non-linear (1/z). Replacing the divisor with a lookup table of pre-computed 1/z values (70 entries, one per row) would produce more convincing depth. The `fakttab` already handles the scanline repetition for vertical foreshortening, but the horizontal curve perspective would benefit from a proper depth curve.

**Road width variation.** The `rowtab` table applies a constant 2-3 pixel widening per row. Making this vary per track segment (narrower roads for difficult sections, wider for straights) would add visual variety and gameplay depth. The `bauN` data structures would need one additional byte per component to specify a road width modifier.

**Gradient edge colors.** The edge stripes alternate between just two colors (12 and 13). Using a 4-color gradient (e.g., 11, 12, 13, 14) with the cycle controlled by `randtab` would create a richer visual effect. The `hline` routine already accepts any color 0-15, so this is purely a data change to the color-toggle logic at `rand1`/`rand2`.

**Better straight-road centering.** The formula `(xadd / 8) / speed_factor` has a problem: at high speed with small `xadd`, the double integer division often truncates to 0, meaning the car doesn't center at all for small offsets. A minimum centering force (e.g., `max(1, (xadd / 8) / speed_factor)` with sign preservation) would ensure the car always drifts back, preventing the annoying tendency to stay slightly off-center on straights.

### 19.3 Technical Improvements

**Eliminate the 80KB pre-shifted scenery buffer.** The 16-copy ROXR pre-shifting (§5.4.5) consumes 81,920 bytes — 22% of BSS. An alternative: shift one scanline on-the-fly during VBL using a single 160-byte temp buffer. This trades ~2,560 ROXR cycles per VBL (about 30µs) for 80KB of RAM. On a 1MB ST this matters less, but it would free enough BSS for additional features on a 512KB machine.

**Use DMA sound on STe.** The Atari STe (1989+) has hardware DMA sound capable of 8-bit PCM playback at up to 50 kHz. Replacing the Timer A interrupt-driven PSG music (`playmus2`, §7.2) with DMA playback would free the CPU for game logic and produce much higher audio quality. The `loudtab` waveform table approach was clever for 1987 but sounds rough compared to direct PCM.

**Double-buffer the sign rendering.** `setsign` writes to only the current physical screen (`$44e`), not both buffers. This means signs may flicker or appear on only one frame. Writing to both buffers (like `set16spr` does for dashboard elements) would eliminate this, at the cost of doubling sign rendering time.

**Replace busy-wait delays.** Several routines use busy loops (`wait`: 131,072 iterations; crash delay: 65,536 iterations; champion delay: 1,048,576 iterations). These are timing-sensitive to CPU speed and would run too fast on accelerated STs. Using VBL-counted delays (e.g., decrementing a counter in the VBL handler) would be timing-independent.

**Fix the `movem.l` grass pattern coverage.** The grass fill (§5.3) writes 44+44+44+20 = 152 bytes per scanline but a scanline is 160 bytes. The missing 8 bytes at the end of each line are overwritten by the road renderer's `hline` calls, so it works — but it's relying on the road always covering the rightmost 8 bytes. A clean fix would use a 5th `movem.l` for the remaining 8 bytes.

### 19.4 Build and Distribution

**Cross-assembler support.** The source uses `as68` assembler syntax (Atari ST Developer Kit). Adapting it for modern cross-assemblers like `vasm` (with Motorola syntax module) would enable building on modern systems. Key changes: `.dc.b`/`.dc.w`/`.dc.l` → `dc.b`/`dc.w`/`dc.l` (strip leading dots), `.ds.b` → `ds.b`, `.even` → `even`, and Line-A opcodes (`$a000`, `$a005`, `$a008`) need `dc.w` wrappers.

**Makefile.** A build script targeting `vasm` + `vlink` would allow reproducible builds. The single-file structure (`TURBOST.S`) makes this trivial — no link step needed beyond converting the output to Atari ST executable format (TOS header + TEXT + DATA + BSS).

**Emulator test suite.** An automated test using Hatari's `--run-vbls` and screenshot comparison could verify that builds produce identical output. The deterministic game loop (no random elements except sign placement, which uses XBIOS Random) makes frame-exact comparison feasible after seeding the RNG.
