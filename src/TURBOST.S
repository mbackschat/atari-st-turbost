;============================================================================
; TURBO ST - Atari ST Racing Game
; (c) 1987 Prism PLC / Capital Software Developments Ltd
; Programmer: Martin Backschat
;
; 68000 Assembly source for the as68 assembler (Atari ST Developer Kit)
;============================================================================

;----------------------------------------------------------------------------
; PROGRAM ENTRY POINT
; Standard Atari ST TPA (Transient Program Area) startup sequence.
; Shrinks the program's memory allocation to its actual size, then
; calls main. On return, exits via Pterm0.
;----------------------------------------------------------------------------
start:
	move.l	a7,a5		; save initial stack pointer (points to basepage)
	move.l	#usersp,a7	; set up our own user stack
	move.l	4(a5),a5	; a5 = basepage address (passed by TOS at sp+4)
	move.l	$c(a5),d0	; d0 = TEXT segment size (basepage offset $0c)
	add.l	$14(a5),d0	; + DATA segment size (basepage offset $14)
	add.l	$1c(a5),d0	; + BSS segment size (basepage offset $1c)
	add.l	#$100,d0	; + basepage size ($100 = 256 bytes)
	move.l	d0,-(sp)	; new_size: total program size
	move.l	a5,-(sp)	; block: basepage address
	clr.w	-(sp)		; dummy (reserved, must be 0)
	move.w	#$4a,-(sp)	; GEMDOS Mshrink ($4a) - release excess memory
	trap	#1		; call GEMDOS
	add.l	#12,sp		; clean up stack (12 bytes: 2+4+4+2)
	bsr	main		; run the game
	clr.w	-(sp)		; exit code 0
	trap	#1		; GEMDOS Pterm0 ($00) - terminate program

;----------------------------------------------------------------------------
; AES/VDI TRAP WRAPPERS
; These are low-level dispatchers for GEM calls via trap #2.
; The AES and VDI parameter blocks (aespb/vdipb) are set up by
; the calling routines before invoking these.
;----------------------------------------------------------------------------
aes:
	move.l	#aespb,d1	; d1 = pointer to AES parameter block
	move.w	#$c8,d0		; d0 = $c8 (200) = AES dispatcher opcode
	trap	#2		; GEM trap: dispatches to AES
	rts

vdi:
	move.l	#vdipb,d1	; d1 = pointer to VDI parameter block
	move.w	#$73,d0		; d0 = $73 (115) = VDI dispatcher opcode
	trap	#2		; GEM trap: dispatches to VDI
	rts


;----------------------------------------------------------------------------
; set16spr - Draw a 16-pixel-wide sprite to BOTH screen buffers
;
; This routine renders a sprite with arbitrary sub-pixel X positioning
; onto both double-buffer screens simultaneously. Used for dashboard
; elements (score digits, speed gauge, gear indicator, steering wheel,
; lap counters) that must appear on both buffers.
;
; Parameters (on stack, after return address):
;   4(sp)  = X position (word) - pixel X coordinate (0-319)
;   6(sp)  = Y position (word) - pixel Y coordinate (0-199)
;   8(sp)  = height (word) - sprite height in lines (0-based: 9 = 10 lines)
;   10(sp) = sprite data (long) - pointer to source sprite in Atari ST
;            bitplane interleaved format (4 planes, 160 bytes/line)
;
; Atari ST low-res screen format:
;   320x200 pixels, 4 bitplanes interleaved in 16-pixel words.
;   Each scanline = 160 bytes = 20 groups of 8 bytes (4 planes x 2 bytes).
;   Within each group: plane0, plane1, plane2, plane3 (each 1 word).
;
; Algorithm:
;   1. Calculate byte offset from Y*160 + (X & ~15)/2
;   2. Sub-pixel shift = X & 15 (how many pixels to shift right)
;   3. For each scanline: read 4 bitplanes from source, shift by sub-pixel
;      amount, then mask-and-OR onto both screen buffers
;   4. The sprite spans 2 screen words (32 pixels) when shifted
;
; Note: a3/a4 point to the RIGHT edge of the 8-byte group (pre-decrement
;       addressing is used to write planes in reverse order for efficiency).
;----------------------------------------------------------------------------
set16spr:
		movem.l	d0-a6,saver	; save all registers (not on stack - fixed buffer)
		move.w	4(sp),d3	; d3 = X position (pixels)
		move.w	6(sp),d4	; d4 = Y position (pixels)
		move.w	8(sp),d6	; d6 = sprite height (loop counter, 0-based)
		move.l	10(sp),a1	; a1 = pointer to sprite bitplane data
		move.l	screen,a3	; a3 = primary screen buffer base
		move.l	screen2,a4	; a4 = secondary screen buffer base
		;
		; Calculate Y offset: Y * 160 bytes/line
		; Trick: Y*160 = Y*128 + Y*32 = (Y*2+Y*8)*16 = ((Y<<1)+(Y<<3))<<4
		; But here: Y*160 = (Y*2 + Y*8) * 16 = (Y*10) * 16
		moveq.l	#0,d1
		move.w	d4,d1		; d1 = Y position
		asl.l	#1,d1		; d1 = Y*2
		move.l	d1,d2		; d2 = Y*2 (save)
		asl.l	#2,d1		; d1 = Y*8
		add.l	d2,d1		; d1 = Y*10
		asl.l	#4,d1		; d1 = Y*160 (byte offset for row Y)
		;
		; Calculate X offset within the scanline
		; Atari ST screen: 16-pixel groups, each 8 bytes (4 planes x 2 bytes)
		moveq.l	#0,d0
		move.w	d3,d0		; d0 = X position
		move.l	d0,d2		; d2 = X (copy for sub-pixel calc)
		moveq.l	#16,d5		; d5 = 16 (will become left-shift amount)
		and.l	#$f,d2		; d2 = X mod 16 = sub-pixel offset (0-15)
		sub.l	d2,d5		; d5 = 16 - sub_pixel = LEFT shift amount
		and.l	#$fffffff0,d0	; d0 = X rounded down to 16-pixel boundary
		lsr.l	#1,d0		; d0 = byte offset within line (X/16 * 8 = X_aligned/2)
		add.l	d1,d0		; d0 = total byte offset (Y*160 + X_byte)
		add.l	#16,d0		; +16 bytes: start from right side of 2-word group
					; (because we use pre-decrement addressing -(a3))
		add.l	d0,a3		; a3 = screen + offset (points to right edge)
		add.l	d0,a4		; a4 = screen2 + offset
		;
		; Set up overlap mask from bittab2
		; bittab2[sub_pixel] has bits set for the RIGHT portion of the sprite
		; (the part that spills into the next 16-pixel word)
		lea	bittab2,a2
		lsl.w	#1,d2		; d2 = sub_pixel * 2 (word index)
		move.w	0(a2,d2),d7	; d7 = right-word mask (1s where sprite data goes)
		move.w	d7,d4
		not.w	d4		; d4 = left-word mask (inverted: 1s where original screen stays)
		;
		; Main sprite rendering loop - one iteration per scanline
		; Each iteration reads 4 bitplanes, shifts them, and writes to both screens
nextline:	moveq.l	#0,d0		; clear all bitplane registers
		moveq.l	#0,d1
		moveq.l	#0,d2
		moveq.l	#0,d3
		move.w	(a1)+,d0	; d0 = source bitplane 0 (in low word)
		move.w	(a1)+,d1	; d1 = source bitplane 1
		move.w	(a1)+,d2	; d2 = source bitplane 2
		move.w	(a1)+,d3	; d3 = source bitplane 3
		add.l	#160-8,a1	; advance source to next scanline
					; (+160 for next line, -8 because we already read 8 bytes)
		;
		; Shift all 4 bitplanes LEFT by d5 bits (= 16 - sub_pixel)
		; After shift: low word = LEFT part, high word = RIGHT part (overflow)
		lsl.l	d5,d0		; shift plane 0 into 32-bit position
		lsl.l	d5,d1		; shift plane 1
		lsl.l	d5,d2		; shift plane 2
		lsl.l	d5,d3		; shift plane 3
		;
		; Write RIGHT word of sprite (overflow portion) to screen
		; Uses pre-decrement: -(a3) moves pointer back by 2 bytes per plane
		; d4 = inverse mask: clears sprite area, preserves background
		; Order: plane3, plane2, plane1, plane0 (reversed due to pre-decrement)
		and.w	d4,-(a3)	; clear sprite bits in screen plane 3 (right word)
		or.w	d3,(a3)		; OR in sprite plane 3 data
		and.w	d4,-(a4)	; same for screen2
		or.w	d3,(a4)
		swap	d3		; swap to access LEFT word (high word -> low word)
		and.w	d4,-(a3)	; screen plane 2 (right word)
		or.w	d2,(a3)
		and.w	d4,-(a4)
		or.w	d2,(a4)
		swap	d2
		and.w	d4,-(a3)	; screen plane 1 (right word)
		or.w	d1,(a3)
		and.w	d4,-(a4)
		or.w	d1,(a4)
		swap	d1
		and.w	d4,-(a3)	; screen plane 0 (right word)
		or.w	d0,(a3)
		and.w	d4,-(a4)
		or.w	d0,(a4)
		swap	d0
		; Now write LEFT word of sprite (main portion) to screen
		; d7 = mask for left word, d0-d3 now contain LEFT part (after swap)
		and.w	d7,-(a3)	; clear sprite bits in screen plane 3 (left word)
		or.w	d3,(a3)		; OR in sprite data
		and.w	d7,-(a3)	; plane 2
		or.w	d2,(a3)
		and.w	d7,-(a3)	; plane 1
		or.w	d1,(a3)
		and.w	d7,-(a3)	; plane 0
		or.w	d0,(a3)
		and.w	d7,-(a4)	; same for screen2: plane 3
		or.w	d3,(a4)
		and.w	d7,-(a4)	; plane 2
		or.w	d2,(a4)
		and.w	d7,-(a4)	; plane 1
		or.w	d1,(a4)
		and.w	d7,-(a4)	; plane 0
		or.w	d0,(a4)
		;
		; Advance to next scanline
		; a3/a4 were decremented 8 times (16 bytes back from start of group)
		; Need to go forward 160+16 = 176 bytes to reach same position on next line
		lea.l	176(a3),a3	; next scanline, same X position
		lea.l	176(a4),a4
		dbf.w	d6,nextline	; loop for all scanlines (d6 counts down)
;
; Sprite rendering complete - restore registers and return
;
		movem.l	saver,d0-a6	; restore all registers from save area
		rts


;----------------------------------------------------------------------------
; setsign - Draw a 16-pixel-wide sign/billboard sprite (OR mode, single buffer)
;
; Similar to set16spr but with key differences:
;   - Only draws to the CURRENT physical screen ($44e), not both buffers
;   - Uses OR mode with transparency (auto-generates mask from non-zero pixels)
;   - Clips at screen edges (left/right) using lrand/rrand mask tables
;   - Clips vertically: skips lines above row 71 (horizon) and below row 140
;
; Parameters (on stack, after return address):
;   4(sp)  = X position (word) - can be negative (partially off-screen left)
;   6(sp)  = Y position (word)
;   8(sp)  = height (word) - sprite height in lines (0-based)
;   10(sp) = sprite data (long) - pointer to sign graphics
;
; Transparency: The mask is computed from the sprite data itself - any pixel
; that is color 0 (all bitplanes = 0) is transparent. This is done by ORing
; all 4 bitplanes together and inverting to get the background preservation mask.
;----------------------------------------------------------------------------
setsign:
		movem.l	d0-a6,saver	; save all registers
		move.w	4(sp),d3	; d3 = X position (may be negative)
		move.w	6(sp),d4	; d4 = Y position
		move.w	8(sp),d6	; d6 = height (loop counter)
		move.l	10(sp),a1	; a1 = pointer to sign sprite data
		move.l	$44e,a3		; a3 = _v_bas_ad (TOS: logical screen base address)
		;
		; --- Horizontal clipping ---
		; Prevent drawing beyond left/right screen edges
		moveq.l	#-1,d7		; d7 = clipping mask (default: all bits = no clipping)
		move.w	d3,d0		; d0 = X position
		bpl	sok1		; if X >= 0, check right edge
		; X is negative: sprite partially off left edge
		neg.w	d0		; d0 = |X| = number of pixels off-screen
		cmp.w	#16,d0		; if more than 16 pixels off-screen...
		bhi	sexit		; ...sprite is fully invisible, exit
		subq.w	#1,d0
		move.w	#15,d3		; clamp X to 15 (effectively X=0 with offset)
		sub.w	d0,d3		; adjust X coordinate
		subq.l	#8,a3		; back up screen pointer by one 16-pixel group
		lea	lrand,a0	; lrand = left-edge clipping mask table
		lsl.w	#1,d0		; word index into table
		move.w	0(a0,d0),d7	; d7 = left clipping mask (masks out off-screen pixels)
		bra	sok2
sok1:
		; Check right edge clipping
		cmp.w	#320-15,d3	; is sprite near right edge?
		ble	sok2		; no, fits on screen
		sub.w	#320-15,d0	; d0 = pixels past right edge
		cmp.w	#15,d0		; fully off-screen?
		bhi	sexit		; yes, exit
		lea	rrand,a0	; rrand = right-edge clipping mask table
		lsl.w	#1,d0		; word index
		move.w	0(a0,d0),d7	; d7 = right clipping mask
sok2:
		;
		; --- Set up vertical clipping boundaries ---
		move.l	a3,a4		; a4 = screen base (will be bottom limit)
		move.l	a3,a5		; a5 = screen base (will be top limit)
		add.l	#160*140,a4	; a4 = lowest visible row for signs (row 140)
		add.l	#160*71,a5	; a5 = highest visible row for signs (row 71 = horizon)
		;
		; --- Calculate screen byte offset (same math as set16spr) ---
		moveq.l	#0,d1
		move.w	d4,d1		; d1 = Y position
		asl.l	#1,d1		; Y*2
		move.l	d1,d2
		asl.l	#2,d1		; Y*8
		add.l	d2,d1		; Y*10
		asl.l	#4,d1		; Y*160 = byte offset for row Y
		;
		moveq.l	#0,d0
		move.w	d3,d0		; d0 = X position
		move.l	d0,d2
		moveq.l	#16,d5
		and.l	#$f,d2		; d2 = X mod 16 (sub-pixel shift)
		sub.l	d2,d5		; d5 = 16 - sub_pixel (left shift amount)
		and.l	#$fffffff0,d0	; align X to 16-pixel boundary
		lsr.l	#1,d0		; byte offset within scanline
		add.l	d1,d0		; total offset
		add.l	#16,d0		; offset for pre-decrement addressing
		add.l	d0,a3		; a3 = destination screen address
		;
		; --- Scanline rendering loop with vertical clipping ---
nextlin1:
		cmp.l	a4,a3		; is current line below bottom limit (row 140)?
		bhi	sexit		; yes, we're done (sign below visible area)
		cmp.l	a5,a3		; is current line above top limit (row 71)?
		bge	itsok		; no, line is in visible range -> draw it
		; Line is above horizon: skip it (advance source and dest, don't draw)
		add.l	#160,a1		; skip one source scanline
		add.l	#160,a3		; advance to next screen line
		dbf	d6,nextlin1	; try next line
		bra	sexit		; all lines were above horizon
itsok:
		; --- Read and clip sprite data for this scanline ---
		moveq.l	#0,d0
		moveq.l	#0,d1
		moveq.l	#0,d2
		moveq.l	#0,d3
		move.w	(a1)+,d0	; plane 0
		and.w	d7,d0		; apply horizontal clipping mask
		move.w	(a1)+,d1	; plane 1
		and.w	d7,d1
		move.w	(a1)+,d2	; plane 2
		and.w	d7,d2
		move.w	(a1)+,d3	; plane 3
		and.w	d7,d3
		add.l	#160-8,a1	; advance to next source scanline
		;
		; Shift all planes for sub-pixel alignment
		lsl.l	d5,d0
		lsl.l	d5,d1
		lsl.l	d5,d2
		lsl.l	d5,d3
		;
		; --- Generate transparency mask ---
		; OR all bitplanes together: any non-zero pixel is opaque
		; Invert: 1 = transparent (keep background), 0 = draw sprite
		move.l	d0,d4		; start with plane 0
		or.l	d1,d4		; combine plane 1
		or.l	d2,d4		; combine plane 2
		or.l	d3,d4		; combine plane 3
		not.l	d4		; invert: d4 = transparency mask (32-bit for both words)
		;
		; --- Write to screen (right word first, then left word) ---
		; Right word (overflow from shift): low word of d0-d3
		and.w	d4,-(a3)	; mask screen plane 3
		or.w	d3,(a3)		; OR in sign data
		swap	d3
		and.w	d4,-(a3)	; plane 2
		or.w	d2,(a3)
		swap	d2
		and.w	d4,-(a3)	; plane 1
		or.w	d1,(a3)
		swap	d1
		and.w	d4,-(a3)	; plane 0
		or.w	d0,(a3)
		swap	d0
		swap	d4		; switch to left-word mask (high word)
		; Left word (main portion): high word of d0-d3 (after swap)
		and.w	d4,-(a3)	; plane 3
		or.w	d3,(a3)
		and.w	d4,-(a3)	; plane 2
		or.w	d2,(a3)
		and.w	d4,-(a3)	; plane 1
		or.w	d1,(a3)
		and.w	d4,-(a3)	; plane 0
		or.w	d0,(a3)
		;
		lea.l	176(a3),a3	; advance to next scanline (160 + 16 pre-decrement compensation)
		dbf.w	d6,nextlin1	; loop for remaining scanlines
;
; Exit: restore registers and return
;
sexit:
		movem.l	saver,d0-a6	; restore all registers
		rts



;----------------------------------------------------------------------------
; hline - Draw a horizontal line in the specified color
;
; Draws a single horizontal line on the current logical screen ($44e).
; Used extensively by the road renderer to draw road surface and edges.
;
; Parameters (global variables):
;   x1  = start X coordinate (word, clamped to 0-319)
;   x2  = end X coordinate (word, clamped to 0-319)
;   y1  = Y coordinate (word)
;   col = color index (word, 0-15)
;
; Atari ST low-res bitplane layout:
;   Each 16-pixel group = 8 bytes: [plane0_w][plane1_w][plane2_w][plane3_w]
;   coltab[color] = 8 bytes with the 4 bitplane patterns for that color
;
; Algorithm:
;   1. Clamp x1,x2 to 0-319
;   2. Calculate first and last 16-pixel word groups
;   3. Generate start mask (bittab) and end mask for partial words
;   4. Write first word (masked), full middle words, last word (masked)
;   5. Each "word" write is 8 bytes (4 planes * 2 bytes)
;----------------------------------------------------------------------------
hline:
	movem.l	d0-d7/a0-a6,saver
	move.w	x2,d1		; d1 = end X
	move.w	x1,d0		; d0 = start X
	bpl	hl1		; if start X >= 0, keep it
	clr.w	d0		; clamp negative start X to 0
hl1:
	cmp.w	#320,d0		; start X >= 320?
	blt	hl1a
	move.w	#319,d0		; clamp both to 319 (degenerate line)
	move.w	#319,d1
hl1a:
	cmp.w	#320,d1		; end X >= 320?
	blt	hl2
	move.w	#319,d1		; clamp end X to 319
hl2:
	tst.w	d1		; end X negative?
	bpl	hl2a
	clr.w	d1		; clamp to 0
hl2a:
	; Calculate screen address for row y1
	move.l	$44e,a0		; a0 = _v_bas_ad (logical screen base)
	move.w	y1,d2
	mulu	#160,d2		; d2 = y1 * 160 bytes/line
	add.l	d2,a0		; a0 = start of scanline y1
	; Calculate starting word group index
	move.w	d0,d2		; d2 = start X
	move.w	d0,d7
	lsr.w	#4,d2		; d2 = start X / 16 = start word group index
	and.l	#$fff0,d7	; align X to 16-pixel boundary
	lsr.l	#1,d7		; d7 = byte offset within scanline
	add.l	d7,a0		; a0 = screen address of starting word group
	move.w	d1,d7
	lsr.w	#4,d7		; d7 = end X / 16 = end word group index
	; Build start mask from bittab: bits set from startbit to bit 15
	and.w	#%1111,d0	; d0 = start bit position (0-15)
	lea	bittab,a2	; bittab: masks with bits set from position N to 15
	lsl.w	#1,d0		; word index
	move.w	0(a2,d0),d0	; d0 = start mask (bits from startbit..15 are set)
	cmp.w	d2,d7		; do start and end fall in the same word group?
	bne	hline2		; no, handle multi-word case
	; Single-word case: combine start and end masks
	and.w	#%1111,d1	; end bit position
	lsl.w	#1,d1
	move.w	0(a2,d1),d1	; d1 = end mask
	not.w	d1		; invert: clear bits from endbit..15, keep 0..endbit-1
	and.w	d1,d0		; combine: only bits between start and end are set
hline2:
	; Duplicate mask into both words of d0 (for 2-longword bitplane writes)
	move.w	d0,d3
	swap	d0
	move.w	d3,d0		; d0 = mask in both high and low words
	move.l	d0,d4
	not.l	d4		; d4 = inverse mask (preserve background)
	; Look up color bitplane pattern from coltab (8 bytes per color)
	clr.l	d3
	move.w	col,d3		; d3 = color index (0-15)
	lsl.w	#3,d3		; d3 = color * 8 (byte offset into coltab)
	lea	coltab,a1
	add.l	d3,a1		; a1 = pointer to 8-byte color pattern
	move.l	(a1),d5		; d5 = planes 0+1 pattern for this color
	move.l	4(a1),d6	; d6 = planes 2+3 pattern for this color
	; Apply mask to color: only paint within the masked region
	and.l	d0,d5		; mask color pattern (planes 0+1)
	and.l	d0,d6		; mask color pattern (planes 2+3)
	; Write first word group: read-modify-write with mask
	move.l	(a0),d3		; read current screen data (planes 0+1)
	and.l	d4,d3		; clear bits where we'll draw
	or.l	d5,d3		; OR in masked color
	move.l	d3,(a0)+	; write back planes 0+1
	move.l	(a0),d3		; read planes 2+3
	and.l	d4,d3		; clear
	or.l	d6,d3		; OR in color
	move.l	d3,(a0)+	; write back planes 2+3
	cmp.w	d2,d7		; was it a single-word line?
	beq	hline3		; yes, we're done
	; Multi-word case: fill middle words with solid color
	move.l	(a1),d5		; reload full (unmasked) color patterns
	move.l	4(a1),d6
hline0:
	addq.w	#1,d2		; advance word group index
	cmp.w	d7,d2		; reached the last word group?
	bge	hline1		; yes, handle last word
	move.l	d5,(a0)+	; write solid color (planes 0+1) - no masking needed
	move.l	d6,(a0)+	; write solid color (planes 2+3)
	bra	hline0		; loop for middle words
hline1:
	; Last word group: mask from bit 0 to end bit position
	and.w	#%1111,d1	; end bit position within last word
	lsl.w	#1,d1
	move.w	0(a2,d1),d1	; d1 = mask (bits from endbit..15)
	move.w	d1,d2
	swap	d1
	move.w	d2,d1		; duplicate into both halves
	move.l	d1,d4
	not.l	d4		; d4 = inverse (bits TO KEEP from background)
	move.l	(a1),d5		; color planes 0+1
	move.l	4(a1),d6	; color planes 2+3
	and.l	d4,d5		; mask color to only the end region
	and.l	d4,d6
	move.l	(a0),d3		; read screen
	and.l	d1,d3		; preserve bits outside our region
	or.l	d5,d3		; OR in color
	move.l	d3,(a0)+
	move.l	(a0),d3		; same for planes 2+3
	and.l	d1,d3
	or.l	d6,d3
	move.l	d3,(a0)+
hline3:
	movem.l	saver,d0-d7/a0-a6
	rts

;----------------------------------------------------------------------------
; fill_rec - Fill a rectangle using Line-A filled rectangle call ($A005)
;
; Draws a filled rectangle in XOR mode (write mode 2). Used for visual
; feedback when selecting components or buttons (flash effect: call twice
; to XOR on then XOR off, restoring original appearance).
;
; Parameters (global variables):
;   x1, y1 = top-left corner
;   x2, y2 = bottom-right corner
;
; Line-A variable offsets (from base pointer in linetab):
;   24-30: color planes 0-3 (all 0 = XOR with existing)
;   36:    write mode (2 = XOR)
;   38-44: clipping rectangle (x1,y1,x2,y2)
;   46:    pattern pointer
;   50:    pattern index
;   54:    clipping flag (0 = no clipping)
;----------------------------------------------------------------------------
fill_rec:
	movem.l	d0-a6,saver
	bsr	mouseoff		; hide mouse cursor during drawing
	move.l	linetab,a0		; a0 = Line-A variable base pointer
	move.w	x1,38(a0)		; X1(38): rectangle min X
	move.w	y1,40(a0)		; Y1(40): rectangle min Y
	move.w	x2,42(a0)		; X2(42): rectangle max X
	move.w	y2,44(a0)		; Y2(44): rectangle max Y
	move.w	#0,24(a0)		; COLBIT0(24): color plane 0 = 0
	move.w	#0,26(a0)		; COLBIT1(26): color plane 1 = 0
	move.w	#0,28(a0)		; COLBIT2(28): color plane 2 = 0
	move.w	#0,30(a0)		; COLBIT3(30): color plane 3 = 0
	move.w	#2,36(a0)		; WMODE(36): write mode = 2 (XOR)
	move.l	#patptr,46(a0)		; PATPTR(46): fill pattern (solid $ffff)
	clr.w	50(a0)			; PATMSK(50): pattern mask index = 0
	clr.w	54(a0)			; CLIP(54): clipping = 0 (disabled)
	.dc.w	$a005			; A_rectfill: Line-A filled rectangle
	bsr	mouseon			; show mouse cursor again
	movem.l	saver,d0-a6
	rts

;----------------------------------------------------------------------------
; AES/VDI HIGH-LEVEL WRAPPERS
; These routines set up the control arrays (contrl/intin/intout etc.)
; and then call the aes or vdi dispatcher.
;
; The AES/VDI parameter block layout:
;   contrl: opcode, sintin, sintout, saddrin, saddrout, + 6 reserved words
;   The actual data goes into intin[], ptsin[], intout[], ptsout[],
;   addrin[], addrout[] arrays.
;----------------------------------------------------------------------------

; app_init - AES appl_init (opcode 10)
; Initializes the AES application. Must be called before any other AES calls.
; Returns application ID in intout[0].
app_init:
	move.w	#10,opcode		; AES function 10 = appl_init
	clr.w	sintin			; 0 integer inputs
	move.w	#1,sintout		; 1 integer output (app ID)
	clr.w	saddrin			; 0 address inputs
	clr.w	saddrout		; 0 address outputs
	bra	aes			; tail-call to AES dispatcher

; op_vwork - VDI v_opnvwk (opcode 100) - Open virtual workstation
; Opens a VDI workstation with 10 input parameters (9x device type 1, + 2=raster).
; The handle is stored in contrl[6] (offset 12) on return.
op_vwork:
	move.w	#100,opcode		; VDI function 100 = v_opnvwk
	clr.w	sintin			; (not used for v_opnvwk)
	move.w	#11,saddrin		; 11 input parameters
	move.w	handle,contrl+12	; workstation handle in contrl[6]
	lea	intin,a0		; fill intin[] with device parameters
	move.w	#9,d0			; 10 entries of value 1 (device type)
opv1:	move.w	#1,(a0)+		; intin[0..9] = 1 (default values for all 10 parameters)
	dbf	d0,opv1
	move.w	#2,(a0)+		; intin[10] = 2 (raster coordinates)
	bsr	vdi			; call VDI
	move.w	contrl+12,handle	; save returned workstation handle
	rts

; v_clswrk - VDI v_clsvwk (opcode 101) - Close virtual workstation
v_clswrk:
	move.w	#101,opcode		; VDI function 101 = v_clsvwk
	clr.w	sintin
	clr.w	sintout
	clr.w	saddrin
	clr.w	saddrout
	move.w	handle,contrl+12	; workstation handle
	bra	vdi			; tail-call to VDI

; clr_work - VDI v_clrwk (opcode 3) - Clear workstation
clr_work:
	move.w	#3,opcode		; VDI function 3 = v_clrwk
	clr.w	sintin
	clr.w	saddrin
	bra	vdi

; vq_mouse - VDI vq_mouse (opcode 124) - Query mouse position and button state
; Parameters (on stack):
;   4(sp)  = pointer to X position (word output)
;   8(sp)  = pointer to Y position (word output)
;   12(sp) = pointer to button status (word output)
vq_mouse:
	move.w	handle,contrl+12
	move.w	#124,opcode		; VDI function 124 = vq_mouse
	clr.w	sintin
	move.w	#1,sintout		; 1 integer output (button state)
	clr.w	saddrin
	move.w	#1,saddrout		; 1 point output (x,y)
	bsr	vdi
	move.l	12(sp),a0		; pointer to button status
	move.w	intout,(a0)		; store button state
	move.l	4(sp),a0		; pointer to X
	move.w	ptsout,(a0)		; store mouse X
	move.l	8(sp),a0		; pointer to Y
	move.w	ptsout+2,(a0)		; store mouse Y
	rts

; gr_hand - AES graf_handle (opcode 77) - Get graphics handle
; Returns the physical workstation handle needed for VDI calls.
gr_hand:
	move.w	#77,opcode		; AES function 77 = graf_handle
	clr.w	sintin
	move.w	#5,sintout		; 5 integer outputs
	clr.w	saddrin
	clr.w	saddrout
	bsr	aes
	move.w	intout,handle		; intout[0] = workstation handle
	rts

;----------------------------------------------------------------------------
; Mouse cursor control
;----------------------------------------------------------------------------

; mouseoff - Hide the mouse cursor (AES graf_mouse #256 = M_OFF)
mouseoff:
	pea	mouseblk		; mouse form block (unused for hide)
	move.w	#256,-(sp)		; form = 256 = M_OFF (hide cursor)
	bsr	gr_mouse
	addq.l	#6,sp
	rts

; mouseon - Show the mouse cursor (AES graf_mouse #257 = M_ON)
mouseon:
	pea	mouseblk		; mouse form block
	move.w	#257,-(sp)		; form = 257 = M_ON (show cursor)
	bsr	gr_mouse
	addq.l	#6,sp
	rts

; gr_mouse - AES graf_mouse (opcode 78) - Set mouse cursor appearance
; Parameters (on stack):
;   4(sp) = mouse form number (word): 0-7=standard, 256=hide, 257=show
;   6(sp) = pointer to mouse form block (long)
gr_mouse:
	move.w	4(sp),intin		; intin[0] = mouse form number
	move.l	6(sp),addrin		; addrin[0] = pointer to form block
	move.w	#78,opcode		; AES function 78 = graf_mouse
	move.w	#1,d0
	move.w	d0,sintin		; 1 integer input
	move.w	d0,sintout		; 1 integer output
	move.w	d0,saddrin		; 1 address input
	clr.w	saddrout
	bsr	aes
	move.w	intout,d0		; return value (not used)
	rts

;----------------------------------------------------------------------------
; FILE I/O ROUTINES
; These use GEMDOS trap #1 calls for file operations.
; Register convention for load/save:
;   a5 = filename (null-terminated C string)
;   a4 = byte count (long) - number of bytes to read/write
;   a6 = buffer address (long) - destination for read / source for write
;----------------------------------------------------------------------------

; load - Load a file from disk into memory
; Parameters: a5=filename, a4=byte_count, a6=buffer
; Uses GEMDOS: Fopen($3d), Fread($3f), Fclose($3e)
load:
	clr.w	-(sp)		; mode = 0 (read only)
	move.l	a5,-(sp)	; pointer to filename string
	move.w	#$3d,-(sp)	; GEMDOS Fopen ($3d)
	trap	#1
	add.l	#8,sp		; clean stack (2+4+2 = 8 bytes)
	tst.w	d0		; d0 = file handle (or negative error)
	bmi	dskerr		; if negative, show error and return
	move.w	d0,-(sp)	; save file handle on stack for Fclose
	move.l	a6,-(sp)	; buffer address (destination)
	move.l	a4,-(sp)	; count (bytes to read)
	move.w	d0,-(sp)	; file handle
	move.w	#$3f,-(sp)	; GEMDOS Fread ($3f)
	trap	#1
	add.l	#12,sp		; clean stack (2+2+4+4 = 12 bytes)
	; d0 = bytes actually read (or error)
	move.w	#$3e,-(sp)	; GEMDOS Fclose ($3e) - handle still on stack
	trap	#1
	addq.l	#4,sp		; clean stack (2+2 = 4 bytes)
	rts

; save - Save memory to a file on disk
; Parameters: a5=filename, a4=byte_count, a6=buffer
; Uses GEMDOS: Fcreate($3c), Fwrite($40), Fclose($3e)
save:
	clr.w	-(sp)		; file attributes = 0 (normal file)
	move.l	a5,-(sp)	; pointer to filename string
	move.w	#$3c,-(sp)	; GEMDOS Fcreate ($3c) - creates or truncates
	trap	#1
	add.l	#8,sp
	tst.w	d0		; d0 = file handle (or negative error)
	bmi	dskerr		; show error on failure
	move.w	d0,-(sp)	; save handle for Fclose
	move.l	a6,-(sp)	; buffer address (source data)
	move.l	a4,-(sp)	; count (bytes to write)
	move.w	d0,-(sp)	; file handle
	move.w	#$40,-(sp)	; GEMDOS Fwrite ($40)
	trap	#1
	add.l	#12,sp
	move.w	#$3e,-(sp)	; GEMDOS Fclose ($3e)
	trap	#1
	addq.l	#4,sp
	rts

; dskerr - Disk error handler
; Displays "Disk Error! Press Key!" and waits for a keypress.
dskerr:
	bsr	mouseoff
	lea	clr_txt,a0	; clear message area (spaces)
	bsr	print
	lea	err_txt,a0	; "Disk Error! Press Key!"
	bsr	print
	move.w	#7,-(sp)	; GEMDOS Crawcin ($07) - wait for raw keypress
	trap	#1
	addq.l	#2,sp
	bra	mouseon		; show mouse and return (tail-call)

;----------------------------------------------------------------------------
; print - Print a null-terminated string to the console
; Parameter: a0 = pointer to string
; Uses GEMDOS Cconws ($09)
;----------------------------------------------------------------------------
print:
	move.l	a0,-(sp)	; pointer to string
	move.w	#9,-(sp)	; GEMDOS Cconws ($09) - write string to console
	trap	#1
	addq.l	#6,sp		; clean stack (2+4 = 6)
	rts

;----------------------------------------------------------------------------
; SCREEN BUFFER MANAGEMENT
;
; The game maintains a "working picture" buffer (pic) that stores the
; editor background. save_pic/show_pic swap between this buffer and the
; visible screen, allowing temporary screen changes (file browser, play
; mode) with easy restoration.
;
; PI1 format: 2 bytes resolution + 32 bytes palette + 32000 bytes screen
; The +$22 offset (34 bytes) skips the resolution and palette header.
;----------------------------------------------------------------------------

; clr_pic - Clear the primary screen to black
; Zeroes all 32000 bytes (8000 longwords) of screen memory.
clr_pic:
	bsr	mouseoff
	move.l	screen,a0	; a0 = primary screen address
	move.w	#7999,d0	; 8000 longwords = 32000 bytes
clp0:	clr.l	(a0)+		; clear 4 bytes
	dbf	d0,clp0		; loop 8000 times
	bra	mouseon		; tail-call: show mouse and return

; save_pic - Copy current screen to the pic buffer (for later restoration)
save_pic:
	bsr	mouseoff
	move.l	screen,a0	; source = current screen
	lea	pic+$22,a1	; destination = pic buffer (skip PI1 header)
	bra	sp0		; share copy loop with show_pic

; show_pic - Copy pic buffer back to the screen (restore editor background)
show_pic:
	bsr	mouseoff
	lea	pic+$22,a0	; source = pic buffer (skip header)
	move.l	screen,a1	; destination = current screen
sp0:	move.w	#7999,d0	; 8000 longwords = 32000 bytes
sp1:	move.l	(a0)+,(a1)+	; copy 4 bytes
	dbf	d0,sp1		; loop 8000 times
	bra	mouseon		; tail-call: show mouse and return

;----------------------------------------------------------------------------
; dez_str - Convert a number (0-999) to a 3-digit ASCII decimal string
;
; Parameters (on stack):
;   4(sp) = value (word, 0-999)
;   6(sp) = pointer to output string buffer (at least 3 bytes)
;
; Algorithm: repeated division by 100, then 10, then remainder
;   hundreds = value / 100, tens = remainder / 10, units = remainder
;----------------------------------------------------------------------------
dez_str:
	clr.l	d0
	clr.l	d1
	clr.l	d2
	move.w	4(sp),d0	; d0 = value to convert
	move.l	6(sp),a0	; a0 = output string pointer
	move.w	d0,d1		; d1 = working copy
	move.w	#100,d2		; divisor = 100 (for hundreds digit)
	bsr	ds1		; extract hundreds digit
	move.w	#10,d2		; divisor = 10 (for tens digit)
	bsr	ds1		; extract tens digit
	move.b	d0,(a0)		; units digit (remainder)
	add.b	#'0',(a0)+	; convert to ASCII and store
	rts
; ds1 - Helper: extract one digit by division
; d1/d2 -> quotient (digit), d0 updated to remainder
ds1:
	divu	d2,d1		; d1.w = quotient (digit), d1 high word = remainder
	move.b	d1,(a0)		; store digit value
	add.b	#'0',(a0)+	; convert to ASCII character
	mulu	d2,d1		; d1 = digit * divisor (to subtract from original)
	sub.w	d1,d0		; d0 = remainder
	move.w	d0,d1		; d1 = remainder for next iteration
	rts

;----------------------------------------------------------------------------
; wait - Simple busy-wait delay loop
; Counts down from $20000 (131072) to 0. At ~8MHz, this is roughly
; 0.1 seconds. Used for brief visual feedback (e.g., button flash).
;----------------------------------------------------------------------------
wait:
	move.l	#$20000,d0	; loop count = 131072
wait1:	subq.l	#1,d0		; decrement counter
	bne.s	wait1		; loop until zero
	rts


;============================================================================
; TRACK EDITOR - MOUSE INPUT HANDLING
;============================================================================

;----------------------------------------------------------------------------
; infield - Handle mouse click within the playfield grid
;
; Called when the user clicks inside the 18x9 playfield (x=16..303, y=16..159).
; Places the currently selected track component at the clicked grid cell.
;
; The playfield is an 18-column x 9-row grid of 16x16 pixel cells.
; Grid cell (0,0) starts at screen pixel (16,16).
;
; Steps:
;   1. Convert mouse pixel coords to grid indices (divide by 16)
;   2. Calculate linear index into playdat array: (row-1)*18 + (col-1)
;   3. Store current component number (aktbaut) into playdat
;   4. Copy the 16x16 pixel block from the component palette area
;      to the appropriate grid position on screen
;----------------------------------------------------------------------------
infield:
	bsr	mouseoff
	clr.l	d6
	clr.l	d7
	clr.l	d0
	clr.l	d1
	clr.l	d2
	move.w	mausx,d6	; d6 = mouse X (pixels)
	move.w	mausy,d7	; d7 = mouse Y (pixels)
	move.w	x1,d0		; d0 = source component X (from selection)
	move.w	y1,d1		; d1 = source component Y
	divu	#16,d6		; d6 = mouse X / 16 = column index (1-18)
	divu	#16,d7		; d7 = mouse Y / 16 = row index (1-9)
	; Calculate linear array index: (row-1)*18 + (col-1)
	move.w	d7,d2
	sub.w	#1,d2		; d2 = row - 1 (0-based)
	mulu	#18,d2		; d2 = (row-1) * 18
	move.w	d6,d3
	sub.w	#1,d3		; d3 = col - 1 (0-based)
	add.w	d3,d2		; d2 = linear index into playdat
	lea	playdat,a0
	move.b	aktbaut+1,0(a0,d2.w)	; store component number (low byte of word)

	; Calculate source address (selected component in palette area)
	mulu	#8,d6		; d6 = column * 8 bytes (byte offset in screen row)
	divu	#16,d0		; d0 = source X / 16 (word group)
	mulu	#8,d0		; d0 = byte offset of source
	move.l	screen,a0	; a0 = source: component palette area on screen
	mulu	#160,d1		; d1 = source Y * 160 bytes/line
	add.l	d1,a0		; a0 = source row start
	add.l	d0,a0		; a0 = source address of component graphic
	; Calculate destination address (grid cell on screen)
	move.l	screen,a1	; a1 = destination base
	mulu	#2560,d7	; d7 = grid_row * 2560 (16 lines * 160 bytes/line)
	add.l	d7,a1		; a1 = destination row start
	add.l	d6,a1		; a1 = destination address

	; Copy 16x16 pixel block (16 lines, 8 bytes per line = 2 longwords)
	move.w	#15,d0		; 16 lines (0-based counter)
inf1:
	move.l	(a0),(a1)	; copy first 4 bytes (planes 0+1)
	move.l	4(a0),4(a1)	; copy next 4 bytes (planes 2+3)
	add.l	#160,a0		; next source line
	add.l	#160,a1		; next destination line
	dbf	d0,inf1		; repeat for all 16 lines
	bra	mouseon		; show mouse and return

;----------------------------------------------------------------------------
; click - Main mouse click dispatcher for the track editor
;
; Called when left mouse button is pressed in the editor loop.
; Determines what the user clicked on:
;   1. Playfield grid (x=16..303, y=16..159) -> place component (infield)
;   2. Command buttons (top bar) -> dispatch via koordtab
;   3. Component palette (bottom) -> select component (click3)
;
; The koordtab structure: repeating entries of:
;   min_x(w), min_y(w), max_x(w), max_y(w), handler_address(l)
; Terminated by min_x = -1.
;----------------------------------------------------------------------------
click:
	move.w	mausx,d6	; d6 = mouse X
	move.w	mausy,d7	; d7 = mouse Y
	; Test if click is within the playfield grid
	cmp.w	#16,d6		; playfield starts at X=16
	blt	click1		; too far left -> try buttons
	cmp.w	#304,d6		; playfield ends at X=304 (18*16+16)
	bge	click1		; too far right -> try buttons
	cmp.w	#16,d7		; playfield starts at Y=16
	blt	click1		; above playfield -> try buttons
	cmp.w	#160,d7		; playfield ends at Y=160 (9*16+16)
	bge	click1		; below playfield -> try buttons
	cmp.w	#-1,aktbaut	; is a component selected?
	beq	click1		; no component selected -> try buttons
	bra	infield		; place component on grid

; Test click against command button coordinate table
click1:
	lea	koordtab,a0	; a0 = button coordinate table
click2:
	move.w	(a0)+,d0	; d0 = min X of button
	cmp.w	#-1,d0		; end of table marker?
	beq	click3		; yes, check component palette instead
	move.w	(a0)+,d1	; d1 = min Y
	move.w	(a0)+,d2	; d2 = max X
	move.w	(a0)+,d3	; d3 = max Y
	move.l	(a0)+,a1	; a1 = command handler address
	; Hit-test: is mouse within this button's bounds?
	cmp.w	d0,d6		; mouse X < min X?
	blt	click2		; miss -> try next button
	cmp.w	d2,d6		; mouse X >= max X?
	bge	click2		; miss
	cmp.w	d1,d7		; mouse Y < min Y?
	blt	click2		; miss
	cmp.w	d3,d7		; mouse Y >= max Y?
	bge	click2		; miss
	; Button hit! Set up coordinates for visual feedback and dispatch
	move.w	d0,x1		; store button bounds for fill_rec flash
	move.w	d1,y1
	move.w	d2,x2
	move.w	d3,y2
	move.w	#-1,aktbaut	; deselect current component
	jsr	(a1)		; call the command handler
waitmaus:
	; Wait for mouse button release before returning to editor loop
	pea	mausstat	; pointer to button status output
	pea	mausy		; pointer to Y output
	pea	mausx		; pointer to X output
	bsr	vq_mouse	; query mouse state
	add.l	#12,sp		; clean stack (3 * 4 bytes)
	tst.w	mausstat	; button still pressed?
	bne	waitmaus	; yes, keep waiting
	rts

;----------------------------------------------------------------------------
; click3 - Test click against the component palette (bottom of screen)
;
; The component palette has 19 components (index 0-18) arranged as:
;   Row 1 (y=163..178): up to 10 components, spaced 32 pixels apart (x=0,32,64...)
;   Row 2 (y=183..198): remaining components
;
; When a component is clicked, it's selected (aktbaut = index) and
; visually flashed using two fill_rec calls (XOR on, wait, XOR off).
;----------------------------------------------------------------------------
click3:
	clr.w	d5		; d5 = component counter (0-18)
	move.w	#0,d0		; d0 = current min X
	move.w	#163,d1		; d1 = current min Y (first row of components)
	move.w	#16,d2		; d2 = current max X (16 pixels wide)
	move.w	#163+16,d3	; d3 = current max Y
click5:
	; Hit-test against current component bounds
	cmp.w	d0,d6		; mouse X < min X?
	blt	click4		; miss -> next component
	cmp.w	d2,d6		; mouse X >= max X?
	bge	click4
	cmp.w	d1,d7		; mouse Y < min Y?
	blt	click4
	cmp.w	d3,d7		; mouse Y >= max Y?
	bge	click4
	; Component hit! Flash it and select it
	move.w	d0,x1		; set bounds for flash
	move.w	d1,y1
	move.w	d2,x2
	move.w	d3,y2
	move.w	d5,aktbaut	; select this component
	bsr	fill_rec	; XOR flash on
	bsr	wait		; brief delay
	bra	fill_rec	; XOR flash off (restores original) and return

; Advance to next component in the palette
click4:
	addq.w	#1,d5		; increment component counter
	cmp.w	#19,d5		; all 19 components checked?
	bge	click6		; yes, nothing was clicked
	add.w	#32,d0		; advance X by 32 pixels (16px component + 16px gap)
	add.w	#32,d2
	cmp.w	#310,d2		; past right edge of screen?
	blt	click5		; no, check this position
	; Wrap to second row
	move.w	#32,d0		; reset X to start of row 2 (offset by 32)
	move.w	#48,d2
	add.w	#20,d1		; advance Y by 20 pixels (16px + 4px gap)
	add.w	#20,d3
	bra	click5		; check this position
click6:
	rts			; no component was clicked



;============================================================================
; EDITOR COMMAND HANDLERS
; Each is called from click2 when its coordinate region is hit.
;============================================================================

;----------------------------------------------------------------------------
; com_load - LOAD command: Load a track and its high scores from disk
;
; Flow:
;   1. Show file browser (opndsk) -> sets a5=filename, a4=164, a6=playdat
;   2. Load track data (164 bytes) into playdat
;   3. Read scenery setting from offset 162 in the loaded data
;   4. Change filename extension to .TOP and load high scores
;   5. Restore editor background and rebuild the grid display
;----------------------------------------------------------------------------
com_load:
	bsr	opndsk		; show file browser, get filename (sets a5,a4,a6)
	bsr	load		; load track: 164 bytes -> playdat (a6)
	move.w	162(a6),aktscene ; restore saved scenery selection from track file
	bsr	chng_ext	; change file extension from user's to .TOP
	lea	hiend,a4	; a4 = size of hiscore data
	sub.l	#hiscr,a4	; (hiend - hiscr = length of hiscore text)
	lea	input,a5	; a5 = filename (now with .TOP extension)
	lea	hiscore,a6	; a6 = destination buffer for hiscores
	bsr	load		; load high scores
	bsr	show_pic	; restore editor background from pic buffer
	bra	build		; rebuild grid display from playdat and return

;----------------------------------------------------------------------------
; com_save - SAVE command: Save current track and high scores to disk
;
; Saves two files:
;   1. Track data: 164 bytes (162 bytes playdat + 2 bytes aktscene)
;   2. High scores: filename.TOP (the default hiscore text)
;----------------------------------------------------------------------------
com_save:
	bsr	opndsk		; show file browser, get filename
	move.w	aktscene,162(a6) ; store current scenery selection in track data
	bsr	save		; save track: 164 bytes from playdat
	bsr	chng_ext	; change extension to .TOP
	lea	hiend,a4	; a4 = hiscore data length
	sub.l	#hiscr,a4
	lea	input,a5	; a5 = filename with .TOP extension
	lea	hiscr,a6	; a6 = source: default hiscore template
	bsr	save		; save hiscore file
	bra	show_pic	; restore editor background and return

;----------------------------------------------------------------------------
; chng_ext - Change filename extension to ".TOP"
;
; Scans the input buffer for a '.' or null terminator, then replaces
; the extension with ".TOP\0".
; Used to derive the hiscore filename from the track filename.
;----------------------------------------------------------------------------
chng_ext:
	lea	input,a0	; a0 = start of filename buffer
com_s2:
	move.b	(a0),d0		; read current character
	tst.b	d0		; null terminator?
	beq	com_s1		; yes, append extension here
	cmp.b	#'.',d0		; period (existing extension)?
	beq	com_s1		; yes, replace from here
	addq.l	#1,a0		; advance to next character
	bra	com_s2
com_s1:
	move.b	#'.',(a0)+	; write ".TOP" extension
	move.b	#'T',(a0)+
	move.b	#'O',(a0)+
	move.b	#'P',(a0)+
	clr.b	(a0)		; null-terminate
	rts

;----------------------------------------------------------------------------
; opndsk - File browser dialog
;
; Displays a directory listing on screen and prompts for a filename.
; Shows up to 23 files per column (two columns: col 4 and col 24).
;
; Uses GEMDOS:
;   Fsetdta ($1a) - set Disk Transfer Address for Fsfirst/Fsnext
;   Fsfirst ($4e) - search for first matching file
;   Fsnext ($4f)  - search for next matching file
;
; DTA structure: 30 bytes of reserved data, then filename at offset 30.
;
; Returns:
;   a4 = 164 (file size: 162 bytes playdat + 2 bytes aktscene)
;   a5 = pointer to input buffer (filename entered by user)
;   a6 = pointer to playdat buffer
;----------------------------------------------------------------------------
opndsk:
	bsr	save_pic	; save current editor screen
	bsr	clr_pic		; clear screen for file listing
	; Set up file listing: start at column 4
	move.b	#$20+4,postxt+3	; VT52 cursor column = 4 (space+4 encoding)
	clr.w	d7		; d7 = file counter (0-22)
	; Set DTA (Disk Transfer Address) for Fsfirst/Fsnext
	pea	dta		; pointer to DTA buffer (50 bytes)
	move.w	#$1a,-(sp)	; GEMDOS Fsetdta ($1a)
	trap	#1
	addq.l	#6,sp
	; Search for first file matching "*.*"
	move.w	#0,-(sp)	; attributes = 0 (normal files only)
	pea	filemask	; filename mask: "*.*"
	move.w	#$4e,-(sp)	; GEMDOS Fsfirst ($4e)
	trap	#1
	addq.l	#8,sp
opndsk2:
	tst.w	d0		; d0 = 0 if file found, negative if no more
	bne	opndsk1		; no more files -> done listing
	; Position cursor and print filename
	move.b	d7,postxt+2	; set VT52 cursor row (encoded as space+row)
	add.b	#$20,postxt+2
	lea	postxt,a0	; postxt = VT52 escape sequence for cursor positioning
	bsr	print		; move cursor
	lea	dta+30,a0	; dta+30 = filename within DTA structure
	bsr	print		; print filename
	addq.w	#1,d7		; increment file counter
	cmp.w	#23,d7		; filled one column (23 files)?
	bne.s	opndsk3		; no, continue
	; Switch to second column
	cmp.b	#$20+24,postxt+3 ; already in second column?
	beq.s	opndsk1		; yes, done (max 46 files displayed)
	clr.w	d7		; reset row counter for second column
	move.b	#$20+24,postxt+3 ; switch to column 24
opndsk3:
	; Search for next file
	move.w	#$4f,-(sp)	; GEMDOS Fsnext ($4f)
	trap	#1
	addq.l	#2,sp
	bra	opndsk2		; process result
opndsk1:
	; File listing complete - prompt for input
	lea	endpost,a0	; reset text color to white (color 15)
	bsr	print
	lea	disk_txt,a0	; "Enter name: " prompt
	bsr	print
	bsr	getinput	; get filename from keyboard -> input buffer
	; Set up load/save parameters
	move.l	#164,a4		; a4 = file size (162 + 2 for aktscene)
	lea	input,a5	; a5 = filename string
	lea	playdat,a6	; a6 = data buffer
	rts

;----------------------------------------------------------------------------
; com_clr - CLEAR command: Erase the entire playfield
; Flashes the button (XOR on), clears playdat, rebuilds display, flashes off.
;----------------------------------------------------------------------------
com_clr:
	bsr	fill_rec	; XOR flash on (button feedback)
	bsr	clrfield	; clear grid data and rebuild display
	bra	fill_rec	; XOR flash off and return

; clrfield - Zero out the playdat array and rebuild the grid display
clrfield:
	lea	playdat,a0	; a0 = track grid data array
	move.w	#161,d0		; 162 bytes to clear (0-based counter)
clr1:	clr.b	(a0)+		; zero one byte (component 0 = empty)
	dbf	d0,clr1		; loop for all 162 bytes
	bra	build		; rebuild display from (now empty) playdat

;----------------------------------------------------------------------------
; com_quit - QUIT command: Exit to GEM desktop
; Pops the click handler return address from the stack and jumps to quit.
;----------------------------------------------------------------------------
com_quit:
	bsr	fill_rec	; flash button
	addq.l	#4,sp		; discard return address (skip back to main loop)
	bra	quit		; jump to cleanup and exit routine

;----------------------------------------------------------------------------
; com_play - PLAY command: Start a race on the current track
;
; Flow:
;   1. Save editor screen
;   2. Generate track sequence from playdat
;   3. Switch IKBD to joystick mode (disable mouse)
;   4. Run the racing game (play)
;   5. Switch back to mouse mode
;   6. Restore editor screen
;
; XBIOS Ikbdws ($19): sends command bytes to the Intelligent Keyboard Controller
;   joyon  = $12,$14 (disable mouse, enable joystick reporting)
;   joyoff = $15,$08 (disable joystick, resume mouse)
;----------------------------------------------------------------------------
com_play:
	bsr	save_pic	; save editor background
	bsr	fill_rec	; flash button
	bsr	generate	; convert playdat grid -> playseq racing sequence
	; Switch to joystick mode: send IKBD commands
	pea	joyon		; joyon = $12 (disable mouse), $14 (enable joystick)
	move.w	#1,-(sp)	; length = 1 (number of command bytes - 1)
	move.w	#25,-(sp)	; XBIOS Ikbdws ($19)
	trap	#$e
	addq.l	#8,sp
	;
	bsr	play		; >>> RUN THE RACING GAME <<<
	;
	; Switch back to mouse mode after game ends
	pea	joyoff		; joyoff = $15 (disable joystick), $08 (enable mouse)
	move.w	#1,-(sp)	; length = 1
	move.w	#25,-(sp)	; XBIOS Ikbdws ($19)
	trap	#$e
	addq.l	#8,sp
	;
	bra	show_pic	; restore editor background and return

;----------------------------------------------------------------------------
; com_scen - SCENERY command: Select one of 3 visual themes
;
; Displays a menu with 3 scenery options. The current selection is
; highlighted with inverse video (VT52 escape codes $1b,"p" and $1b,"q").
; User navigates with cursor up/down and confirms with Return.
;
; Sceneries:
;   0 = Rising Sun/City
;   1 = High Noon/City
;   2 = Alps/Village
;
; XBIOS Ikbdws ($19) with mauscurs = $0a,25,25 puts IKBD in cursor key
; emulation mode (mouse movements generate cursor key scancodes).
;----------------------------------------------------------------------------
com_scen:
	bsr	save_pic	; save editor background
	bsr	fill_rec	; flash button
	; Switch mouse to cursor key emulation mode
	pea	mauscurs	; IKBD command: mouse -> cursor keys
	move.w	#2,-(sp)	; length = 2 (3 bytes - 1)
	move.w	#25,-(sp)	; XBIOS Ikbdws ($19)
	trap	#$e
	addq.l	#8,sp
	; Display scenery selection header
	lea	scentxt,a0	; "Select Scenery:" header text
	bsr	print
com_snxt:
	; Display current selection (with inverse video on selected item)
	move.w	aktscene,d0	; d0 = current scenery (0-2)
	lsl.w	#2,d0		; d0 * 4 = longword index into pointer table
	lea	scentxtp,a0	; scentxtp = array of 3 string pointers
	move.l	0(a0,d0),a0	; a0 = pointer to scenery text with highlighting
	bsr	print		; display the three options
	; Wait for keypress
	move.w	#7,-(sp)	; GEMDOS Crawcin ($07) - blocking key read
	trap	#1
	addq.l	#2,sp		; d0.l = scancode(high word) + ASCII(low byte)
	cmp.b	#13,d0		; Return key?
	beq	com_send	; confirm selection
	lsr.l	#8,d0		; shift to get scancode
	lsr.l	#8,d0		; d0.b = scancode
	cmp.b	#$48,d0		; cursor up? (scancode $48)
	bne	com_sen1
	tst.w	aktscene	; already at first scenery?
	beq	com_snxt	; yes, don't go below 0
	subq.w	#1,aktscene	; select previous scenery
	bra	com_snxt	; redisplay
com_sen1:
	cmp.b	#$50,d0		; cursor down? (scancode $50)
	bne	com_snxt	; other key, ignore
	cmp.w	#2,aktscene	; already at last scenery?
	beq	com_snxt	; yes, don't go above 2
	addq.w	#1,aktscene	; select next scenery
	bra	com_snxt	; redisplay
com_send:
	; Restore normal mouse mode
	pea	mauson		; IKBD command $08: enable relative mouse mode
	clr.w	-(sp)		; length = 0 (1 byte - 1)
	move.w	#25,-(sp)	; XBIOS Ikbdws ($19)
	trap	#$e
	addq.l	#8,sp
	bra	show_pic	; restore editor background and return


;----------------------------------------------------------------------------
; build - Rebuild the entire playfield display from playdat array
;
; Iterates through all 162 cells of the playdat array and copies the
; corresponding 16x16 component graphic from the component palette area
; to each grid cell position on screen.
;
; The component palette is drawn on-screen below the playfield (y=163+).
; Each component is a 16x16 pixel tile, arranged in 2 rows with 32-pixel
; spacing. build1 maps component index -> palette source coordinates.
;----------------------------------------------------------------------------
build:
	bsr	mouseoff
	lea	playdat,a6	; a6 = base of track grid data
	clr.l	d6		; d6 = index into playdat (0-161)
build2:
	clr.l	d0
	move.b	0(a6,d6.w),d0	; d0 = component number at this cell
	movem.l	d0-a6,-(sp)	; save all registers (build1 clobbers them)
	bsr	build1		; draw this component on the grid
	movem.l	(sp)+,d0-a6	; restore registers
	addq.w	#1,d6		; next cell
	cmp.w	#162,d6		; processed all 162 cells? (18 cols x 9 rows)
	bne	build2		; no, continue
	bra	mouseon		; show mouse and return

; build1 - Draw a single grid cell
; Input: d6 = cell index (0-161), d0 = component number (0-18)
build1:
	; Calculate destination grid position from linear index d6
	; row = d6 / 18, col = d6 % 18 (but we count rows from 1)
	move.w	#1,d1		; d1 = row counter (starts at 1, first grid row)
build1a:
	cmp.w	#18,d6		; is d6 still >= 18?
	blt	build1b		; no, d6 is now the column index
	addq.l	#1,d1		; increment row
	sub.w	#18,d6		; subtract one row width
	bra	build1a
build1b:
	; d6 = column (0-17), d1 = row (1-9)
	; Calculate destination screen address
	move.l	screen,a1	; a1 = destination base
	addq.l	#1,d6		; +1 because grid starts at pixel X=16 (word group 1)
	mulu	#8,d6		; d6 = byte offset within scanline (column * 8)
	add.l	d6,a1
	mulu	#2560,d1	; d1 = row * 16 lines * 160 bytes = row * 2560
	add.l	d1,a1		; a1 = destination address for this cell

	; Calculate source address from component number d0
	; Components are arranged in the palette area starting at y=163:
	;   Row 1: components at x=0,2,4,...,18 (word group spacing)
	;   Row 2: components at x=2,4,...,18 (y=163+20=183)
	move.l	#0,d1		; d1 = source X (word group index, stepping by 2)
	move.l	#163,d2		; d2 = source Y (first palette row)
build1c:
	tst.w	d0		; have we found the right component?
	beq	build1d		; yes (counted down to 0)
	subq.w	#1,d0		; decrement component counter
	addq.w	#2,d1		; advance X by 2 word groups (32 pixels)
	cmp.w	#19,d1		; past right edge of row?
	blt	build1c		; no, continue
	moveq.l	#2,d1		; wrap to start of next row (X=2)
	add.w	#20,d2		; advance Y by 20 pixels (next palette row)
	bra	build1c
build1d:
	; d1 = source word group index, d2 = source Y line
	move.l	screen,a0	; a0 = source base
	mulu	#8,d1		; d1 = byte offset within scanline
	add.l	d1,a0
	mulu	#160,d2		; d2 = Y * 160 bytes/line
	add.l	d2,a0		; a0 = source address of component graphic
	; Copy 16x16 pixel block (16 lines, 8 bytes = 2 longwords per line)
	move.w	#15,d0		; 16 lines (0-based)
build1e:
	move.l	(a0),(a1)	; copy planes 0+1
	move.l	4(a0),4(a1)	; copy planes 2+3
	add.l	#160,a0		; next source line
	add.l	#160,a1		; next destination line
	dbf	d0,build1e
	rts

;----------------------------------------------------------------------------
; getinput - Read a filename from keyboard (up to 12 characters)
;
; Displays a blinking cursor and reads keypresses:
;   - Return: confirms input
;   - Backspace: deletes last character
;   - Printable chars (space to 'z'): appended to buffer
;
; Result: filename stored in 'input' buffer, null-terminated.
; Uses VT52 escape codes: curson ($1b,"e") to show cursor,
; cursoff ($1b,"f") to hide it, crsleft ($1b,"D") to move left.
;----------------------------------------------------------------------------
getinput:
	bsr	mouseoff
	lea	curson,a0	; VT52: show cursor ($1b,"e")
	bsr	print
	lea	input,a6	; a6 = current write position in input buffer
	clr.b	(a6)		; clear buffer
geti2:
	move.w	#7,-(sp)	; GEMDOS Crawcin ($07) - wait for keypress
	trap	#1
	addq.l	#2,sp		; d0 = ASCII character in low byte
	cmp.b	#13,d0		; Return pressed?
	beq	geti1		; yes, finish input
	cmp.b	#8,d0		; Backspace pressed?
	bne	geti3		; no, try adding character
	; Handle backspace
	cmp.l	#input,a6	; already at start of buffer?
	beq	geti2		; yes, ignore backspace
	subq.l	#1,a6		; move write pointer back
	clr.b	(a6)		; null-terminate at new position
	lea	crsleft,a0	; VT52: move cursor left + space + move left
	bsr	print		; erase the character on screen
	bra	geti2
geti3:
	; Handle normal character
	cmp.l	#input+12,a6	; buffer full? (max 12 characters)
	bge	geti2		; yes, ignore keystroke
	cmp.b	#' ',d0		; below space? (control character)
	blt	geti2		; ignore
	cmp.b	#'z',d0		; above 'z'?
	bhi	geti2		; ignore
	move.b	d0,(a6)+	; store character and advance pointer
	clr.b	(a6)		; null-terminate
	lea	-1(a6),a0	; a0 = pointer to the character we just stored
	bsr	print		; echo it to screen (print reads until null)
	bra	geti2		; continue reading
geti1:
	; Input complete
	lea	cursoff,a0	; VT52: hide cursor ($1b,"f")
	bsr	print
	bra	mouseon		; show mouse and return

;============================================================================
; TRACK SEQUENCE GENERATION
;============================================================================

;----------------------------------------------------------------------------
; generate - Convert the editor's playdat grid into a linear race sequence
;
; This is the core algorithm that transforms the 2D grid layout into
; a 1D sequence of curve values that the racing renderer consumes.
;
; Algorithm:
;   1. Scan playdat for a start piece (component #9 or #18)
;   2. From the start piece, look up its bauN definition to get:
;      - exit_dir1, entry_dir, exit_dir2 (direction codes 1-8)
;      - curve sequence data (bytes, terminated by $80)
;   3. Determine if the piece needs to be read forward or backward:
;      - Forward if: this is the start piece, OR entry_dir matches expected
;      - Backward if: entry_dir doesn't match (reversed piece)
;      - When reversed: read sequence bytes in reverse, negate each value
;   4. Copy curve values to playseq output buffer
;   5. Follow exit direction offset to the next grid cell
;   6. Repeat until the start piece is reached again
;   7. Process the start piece twice (the racer crosses it at start and end)
;   8. Terminate with $80 marker
;
; Direction compass:     5  1  6
;                         \ | /
;                      4-- *** --2
;                         / | \
;                        8  3  7
;
; offs[direction] gives the grid index offset to move in that direction.
; For an 18-column grid: up=-18, down=+18, left=-1, right=+1, etc.
;
; Returns: D0.l = length of generated sequence in bytes
;----------------------------------------------------------------------------
generate:
	lea	playdat,a0	; a0 = grid data pointer (current position)
	lea	playseq,a1	; a1 = output sequence buffer
	clr.l	d0
	moveq	#1,d1		; d1 = 1: process start piece twice (dbf counts 1,0)
	; --- Step 1: Find the start piece ---
gen0:
	move.b	(a0),d0		; d0 = component at current position
	move.w	d0,starter	; remember start component number
	cmp.b	#18,d0		; is it start piece #18?
	beq	gen1a		; yes, start generating
	cmp.b	#9,d0		; is it start piece #9?
	beq	gen1a		; yes, start generating
	addq.l	#1,a0		; advance to next grid cell
	bra	gen0		; keep searching
	;
	; --- Step 2: Process current component ---
gen1:
	clr.l	d0
	move.b	(a0),d0		; d0 = component number at current grid cell
gen1a:
	subq.w	#1,d0		; adjust: component 0 is empty, so #1 -> index 0
	lsl.w	#2,d0		; d0 * 4 = longword index into playtab
	lea	playtab,a2	; playtab = array of 18 pointers to bauN definitions
	move.l	0(a2,d0.w),a3	; a3 = pointer to this component's definition
	; Read component direction header: exit1, entry, exit2
	move.w	(a3)+,d4	; d4 = exit direction 1 (primary exit)
	move.w	(a3)+,d2	; d2 = entry direction
	move.w	(a3)+,d6	; d6 = exit direction 2 (alternate exit)
	; a3 now points to the curve sequence data bytes
	; Look up grid offsets for both exit directions
	lea	offs,a5		; offs = direction-to-grid-offset table (9 entries)
	move.w	d4,d5
	mulu	#2,d5		; d5 = exit1_dir * 2 (word index)
	move.w	0(a5,d5.w),d5	; d5 = grid offset for exit direction 1
	ext.l	d5		; sign-extend (offsets can be negative, e.g., -18)
	move.w	d6,d7
	mulu	#2,d7		; d7 = exit2_dir * 2
	move.w	0(a5,d7.w),d7	; d7 = grid offset for exit direction 2
	ext.l	d7
	;
	; --- Step 3: Determine forward or reverse reading ---
	; At the start piece, we always read forward.
	; For subsequent pieces, check if the expected entry direction matches.
	move.w	starter,d0	; d0 = start component number
	cmp.b	(a0),d0		; is current cell the start piece?
	beq	gen2		; yes -> read forward (first encounter)
	cmp.w	olddir,d2	; does entry_dir match the direction we came from?
	beq	gen2		; yes -> piece is oriented correctly, read forward
	;
	; Piece is reversed: swap exit directions and read sequence backward
	exg	d4,d6		; swap exit1 <-> exit2
	exg	d5,d7		; swap their grid offsets
	move.l	a3,a4		; a4 = start of sequence data
gen1d:
	cmp.b	#$80,(a4)	; find $80 terminator (end of sequence)
	beq	gen1c
	addq.l	#1,a4		; advance
	bra	gen1d
gen1c:
	; Read sequence bytes in reverse order, negating each value
	; (reversing the curve direction: left becomes right and vice versa)
	move.b	-(a4),d0	; read byte from end toward start
	neg.b	d0		; negate: -2 becomes +2, etc.
	move.b	d0,(a1)+	; write to output sequence
	cmp.l	a4,a3		; reached the start of sequence data?
	bne	gen1c		; no, continue reading backward
	bra	gen3		; done with this component
	;
	; --- Forward read: copy sequence bytes normally ---
gen2:
	move.b	(a3)+,(a1)+	; copy one curve byte to output
	cmp.b	#$80,(a3)	; reached terminator?
	bne	gen2		; no, copy next byte
	;
	; --- Step 4: Advance to next grid cell ---
gen3:
	move.w	d4,olddir	; remember our exit direction (for next piece's entry check)
	move.b	(a0),d0		; d0 = current component (check if back at start)
	cmp.w	starter,d0	; have we reached the start piece again?
	beq	genend		; yes, track loop is complete
gen4:
	add.l	d5,a0		; advance grid pointer by exit direction offset
	bra	gen1		; process next component
	;
genend:
	dbf	d1,gen4		; d1 counts down 1->0: process start piece twice
	; (first time: generate sequence for it; second time: we're done)
	move.b	#$80,(a1)+	; write end-of-track marker
	move.l	a1,d0		; d0 = current write position
	sub.l	#playseq,d0	; d0 = total bytes written (sequence length)
	rts


;============================================================================
; MAIN PROGRAM - INITIALIZATION AND EDITOR LOOP
;============================================================================

;----------------------------------------------------------------------------
; main - Main entry point (called from start after memory setup)
;
; Performs complete game initialization:
;   1. System setup (supervisor mode, palette save, resolution)
;   2. GEM initialization (AES, VDI, Line-A)
;   3. Resource loading (all PI1 images, sound data)
;   4. Title screen with music
;   5. Joystick IRQ installation
;   6. Default track loading
;   7. Enter editor loop
;----------------------------------------------------------------------------
main:
	; --- Enter supervisor mode to access hardware registers ---
	clr.l	-(sp)		; parameter = 0 (switch to supervisor, return old SSP)
	move.w	#$20,-(sp)	; GEMDOS Super ($20)
	trap	#1
	addq.l	#6,sp
	move.l	d0,-(sp)	; save old SSP on stack for later restoration
	;
	; --- Detect PAL (50Hz) vs NTSC (60Hz) for VBL timing ---
	move.b	$ff820a,d0	; read syncmode register (Shifter video sync mode)
	move.w	#680,waitcnt	; default: 680 raster lines for 50Hz PAL
	btst	#1,d0		; bit 1: 0=60Hz NTSC, 1=50Hz PAL
	bne	main1		; PAL -> keep 680
	move.w	#790,waitcnt	; NTSC: 790 raster lines (more lines to wait)
main1:
	; --- Save current palette and set screen to black ---
	movem.l	$ff8240,d0-d7	; read all 16 color registers (color0..color15)
	movem.l	d0-d7,savcolor	; save for restoration on exit
	movem.l	clrcolor,d0-d7	; clrcolor = 16 words of 0 (all black)
	movem.l	d0-d7,$ff8240	; write black palette to color0..color15
	;
	; --- Return to user mode ---
	move.w	#$20,-(sp)	; GEMDOS Super ($20) - switch back
	trap	#1		; (old SSP was saved on stack, this restores it)
	addq.l	#6,sp

	; --- Initialize GEM subsystems ---
	bsr	app_init	; AES appl_init: register as GEM application
	bsr	gr_hand		; AES graf_handle: get VDI workstation handle
	bsr	op_vwork	; VDI v_opnvwk: open virtual workstation
	bsr	clr_work	; VDI v_clrwk: clear workstation

	bsr	init_pr		; Line-A $A000 init: get font and variable pointers
	bsr	mouseoff	; hide mouse cursor during loading

	; --- Get screen addresses and set low resolution ---
	move.w	#3,-(sp)	; XBIOS Logbase ($03) - get logical screen address
	trap	#$e
	addq.l	#2,sp
	move.l	d0,screen	; save primary screen address

	move.w	#4,-(sp)	; XBIOS Getrez ($04) - get current resolution
	trap	#$e
	addq.l	#2,sp
	move.w	d0,rez		; save original resolution (for quit)

	; Set low resolution (320x200, 16 colors), keep current screen addresses
	clr.w	-(sp)		; rez = 0 (low resolution)
	pea	-1		; physbase = -1 (don't change)
	pea	-1		; logbase = -1 (don't change)
	move.w	#5,-(sp)	; XBIOS Setscreen ($05)
	trap	#$e
	add.l	#12,sp

	; --- Align secondary screen buffer to 256-byte boundary ---
	; The Atari ST video hardware requires the screen base address to be
	; aligned to a 256-byte boundary. We scan forward from scndscr until
	; we find an address where the low byte is 0.
	lea	scndscr,a0	; scndscr has 256 extra bytes for alignment padding
scrn2:
	move.l	a0,d0
	and.l	#$ff,d0		; check low byte
	beq	scrn1		; if zero, address is aligned
	addq.l	#2,a0		; try next word-aligned address
	bra	scrn2
scrn1:
	move.l	a0,screen2	; save aligned secondary screen address

	; === LOAD ALL GAME RESOURCES ===

	; Load title music (digital sound data, ~78KB)
	lea	digisnd,a6	; destination buffer
	lea	diginame,a5	; filename: "heavy.seq"
	lea	$fffff,a4	; byte count (large: reads entire file)
	bsr	load
	;
	; Load title screen picture (PI1 format: 2+32+32000 bytes)
	; Load at screen-$22 to capture the palette header
	move.l	screen,a6
	sub.l	#$22,a6		; back up 34 bytes for PI1 header
	lea	titlen,a5	; filename: "title.pi1"
	lea	$fffff,a4
	bsr	load		; load title picture (palette + screen data)
	addq.l	#2,a6		; skip resolution word -> a6 points to palette
	move.l	a6,-(sp)	; push palette address
	move.w	#6,-(sp)	; XBIOS Setpalette ($06)
	trap	#$e		; display the title picture's palette
	addq.l	#6,sp
	;
	; Play digital music on title screen (blocks until keypress)
	clr.l	-(sp)		; enter supervisor mode
	move.w	#$20,-(sp)	; GEMDOS Super ($20)
	trap	#1
	addq.l	#6,sp
	move.l	d0,-(sp)	; save old SSP
	bsr	playdigi	; play digital sound, wait for keypress
	;
	; Load cockpit/dashboard (PI1 format)
	; First: load just the palette (34 bytes) into playpal
	lea	playpal,a6	; destination: game palette buffer
	lea	cockpitn,a5	; filename: "dashbord.pi1"
	lea	$22,a4		; read only 34 bytes (resolution + palette)
	bsr	load
	; Then: load the full picture into screen2
	move.l	screen2,a6
	sub.l	#$22,a6		; offset for PI1 header
	lea	cockpitn,a5	; same file
	lea	$fffff,a4	; read entire file
	bsr	load
	;
	; Extract sprite data from cockpit image into datascr1
	; The lower portion of the cockpit image contains digit, speed, gear,
	; and steering wheel sprites. Copy them to datascr1 and clear from screen2.
	move.w	#5439,d0	; 5440 longwords = 21760 bytes (sprite area)
	move.l	screen2,a0	; source: beginning of screen2
	lea	datascr1,a1	; destination: sprite data buffer
da1:
	move.l	(a0),(a1)+	; copy to sprite buffer
	clr.l	(a0)+		; clear from screen2 (leaving clean cockpit)
	dbf	d0,da1

	; Load sign/billboard sprites (set 1)
	lea	signscr1-$22,a6	; load with PI1 header offset
	lea	signn1,a5	; filename: "signs.pi1"
	lea	$fffff,a4
	bsr	load

	; Load sign sprites (set 2) + scenery bitmap data
	lea	signscr2-$22,a6
	lea	signn2,a5	; filename: "signs2.pi1"
	lea	$fffff,a4
	bsr	load

	; Load crash/explosion animation frame
	lea	film-$22,a6	; filmpal is right before film buffer
	lea	filmname,a5	; filename: "film.pi1"
	lea	$fffff,a4
	bsr	load

	; Load explosion sound effect
	lea	explsnd,a6
	lea	explname,a5	; filename: "expl.snd"
	lea	$fffff,a4
	bsr	load

	; --- Install custom joystick interrupt handler ---
	; XBIOS Kbdvbase ($22) returns pointer to keyboard vector table.
	; Offset 24 in the table is the joystick packet handler vector.
	move.w	#34,-(sp)	; XBIOS Kbdvbase ($22)
	trap	#$e
	addq.l	#2,-(sp)	; BUG: should be addq.l #2,sp - but works because
				; the extra word is harmless on the stack
	move.l	d0,a0		; a0 = keyboard vector table base
	move.l	#joyirq,24(a0)	; install our joystick handler at offset 24

	; Load editor working picture (track construction screen)
	lea	picname,a5	; filename: "trcs.pi1"
	lea	pic,a6		; destination: pic buffer (includes PI1 header)
	move.l	#$fffff,a4
	bsr	load
	pea	pic+2		; pic+2 = palette (after resolution word)
	move.w	#6,-(sp)	; XBIOS Setpalette ($06)
	trap	#$e
	addq.l	#6,sp		; display editor palette

	bsr	resettim	; ensure MFP timers are reset (stop title music)
	;
	; Return to user mode
	move.w	#$20,-(sp)	; GEMDOS Super ($20)
	trap	#1
	addq.l	#6,sp

	; --- Show the editor screen ---
	bsr	mouseon
	bsr	show_pic	; copy pic buffer to screen (shows editor background)
	bsr	mouseoff

	; --- Load default track ---
	lea	164,a4		; file size: 164 bytes
	lea	input,a5	; filename: "default" (already in input buffer)
	lea	playdat,a6	; destination: grid data array
	bsr	load
	move.w	162(a6),aktscene ; load saved scenery selection
	bsr	chng_ext	; change extension to .TOP
	lea	hiend,a4	; hiscore data length
	sub.l	#hiscr,a4
	lea	input,a5	; filename: "default.top"
	lea	hiscore,a6
	bsr	load		; load default high scores

	; Set mouse cursor to pointing finger (form #3)
	pea	mouseblk	; mouse form definition block
	move.w	#3,-(sp)	; form #3 = pointing hand
	bsr	gr_mouse	; AES graf_mouse
	addq.l	#6,sp
	bsr	mouseon		; show cursor

	; Enable mouse via IKBD
	pea	mauson		; IKBD command $08: relative mouse mode
	clr.w	-(sp)		; length = 0 (1 byte)
	move.w	#25,-(sp)	; XBIOS Ikbdws ($19)
	trap	#$e
	addq.l	#8,sp

	; Build grid display from loaded track data
	bsr	build

;----------------------------------------------------------------------------
; EDITOR MAIN LOOP
; Continuously polls mouse position and dispatches clicks.
;----------------------------------------------------------------------------
loop1:
	pea	mausstat	; pointer to button status
	pea	mausy		; pointer to Y position
	pea	mausx		; pointer to X position
	bsr	vq_mouse	; VDI: query mouse state
	add.l	#12,sp		; clean stack (3 pointers)

	move.w	mausstat,d0	; d0 = button state
	btst	#0,d0		; bit 0 = left mouse button
	beq	loop1a		; not pressed -> loop
	bsr	click		; left button pressed: handle click
loop1a:
	bra	loop1		; infinite loop (exit via com_quit)

;----------------------------------------------------------------------------
; quit - Clean up and return to GEM desktop
;
; Restores original screen resolution, palette, and closes VDI workstation.
;----------------------------------------------------------------------------
quit:
	; Restore original screen resolution
	move.w	rez,-(sp)	; original resolution
	pea	-1		; keep current screen addresses
	pea	-1
	move.w	#5,-(sp)	; XBIOS Setscreen ($05)
	trap	#$e
	add.l	#12,sp

	; Restore original color palette
	pea	savcolor	; saved palette from startup
	move.w	#6,-(sp)	; XBIOS Setpalette ($06)
	trap	#$e
	addq.l	#6,sp

	bra	v_clswrk	; close VDI workstation and return

;============================================================================
; PLAY MODE - RACING GAME ENGINE
;============================================================================

;----------------------------------------------------------------------------
; play - Main entry point for the racing game
;
; Called from com_play after track sequence is generated.
; Handles the complete race session: setup, lap selection, player selection,
; rendering loop, scoring, game over, and high score processing.
;
; The racing engine uses:
;   - Double-buffered rendering (screen/screen2)
;   - Custom VBL interrupt for scenery scrolling + raster palette split
;   - MFP Timer A for digital sound playback
;   - Direct joystick reading via custom IKBD handler
;   - Pseudo-3D perspective road rendering
;----------------------------------------------------------------------------
play:
	bsr	mouseoff
	; Enter supervisor mode for the entire game session
	; (needed for direct hardware access: palette, interrupts, joystick)
	clr.l	-(sp)
	move.w	#$20,-(sp)	; GEMDOS Super ($20)
	trap	#1
	addq.l	#6,sp
	move.l	d0,-(sp)	; save old SSP (will be restored at abort/end)
	;
	bsr	prepdigi	; set up MFP Timer A for digital music playback
	bsr	asklaps		; prompt: select number of laps (1-9) via joystick
	bsr	askplay		; prompt: select number of players (1-4) via joystick
	bsr	resettim	; stop digital music
	pea	initsnd		; silence all PSG channels
	bsr	setsound	; write PSG init sequence
	addq.l	#4,sp
	;
	; Initialize player score array (4 players, BCD format)
	lea	plscore,a0
	move.w	#$0000,d0
	move.w	d0,0(a0)	; player 1 score = 0
	move.w	d0,2(a0)	; player 2 score = 0
	move.w	d0,4(a0)	; player 3 score = 0
	move.w	d0,6(a0)	; player 4 score = 0
	clr.w	nrplay1		; current player index = 0

;--- Per-player initialization (entry point for next player) ---
end2:
	; Copy cockpit/dashboard from screen2 to primary screen
	move.w	#7999,d0	; 8000 longwords = 32000 bytes
	move.l	screen2,a0	; source: clean cockpit (no sprites)
	move.l	screen,a1	; destination: primary screen
pl01:	move.l	(a0)+,(a1)+
	dbf	d0,pl01
	;
	; Set the game palette (loaded from dashbord.pi1 header)
	pea	playpal+2	; playpal+2 = palette data (skip resolution word)
	move.w	#6,-(sp)	; XBIOS Setpalette ($06)
	trap	#$e
	addq.l	#6,sp
	move.l	screen,aktscr	; set initial drawing target to screen
	;
	; Display total laps digit on dashboard
	clr.l	d0
	move.w	nrlaps,d0	; d0 = total number of laps
	lea	datascr1+80,a0	; digit sprites start at datascr1+80
	lsl.w	#3,d0		; d0 * 8 = byte offset for this digit's sprite
	add.l	d0,a0		; a0 = sprite data for this digit
	move.l	a0,-(sp)	; push sprite address
	move.w	#9,-(sp)	; sprite height = 10 lines
	move.w	#188,-(sp)	; Y position on dashboard
	move.w	#108,-(sp)	; X position on dashboard
	bsr	set16spr	; draw to both screen buffers
	add.l	#10,sp		; clean parameters (4+2+2+2 = 10)
	;
	; --- Decompress playseq into aktseq (expand each byte to 6 bytes) ---
	; Each sequence byte contains:
	;   Lower nibble: curve direction (-7 to +7, where 7 = end marker)
	;   Upper nibble: sign/billboard info (placed later)
	;
	; Expansion: each byte becomes 3 words (6 bytes) in aktseq.
	; The curve nibble is replicated into both nibbles of each word,
	; effectively giving 6 sub-segments per original track segment.
	lea	playseq,a0	; a0 = source: compressed track sequence
	lea	aktseq,a1	; a1 = destination: expanded sequence
pl0a:
	move.b	(a0)+,d0	; read one sequence byte
	cmp.b	#$80,d0		; end-of-track marker?
	beq	pl0c		; yes, finish expansion
	and.w	#$0f,d0		; d0 = lower nibble (curve value, sign-extended to 0-15)
	move.w	d0,d1		; copy to d1
	lsl.w	#8,d1		; d1 = curve << 8 (put in upper byte)
	or.w	d1,d0		; d0 = curve_curve (same nibble in both bytes)
	move.w	#2,d6		; write 3 copies (0-based counter)
pl0:
	move.w	d0,(a1)+	; write 2-byte expanded segment
	dbf	d6,pl0		; 3 times = 6 bytes total
	bra	pl0a		; next source byte
pl0c:
	; Append 4 empty words (padding) and write end marker
	move.w	#3,d6
pl0ca:
	clr.w	(a1)+		; zero padding
	dbf	d6,pl0ca
	move.b	#%0111,(a1)	; end marker: curve value 7 in low nibble

	; --- Randomly place billboards/signs along the track ---
	; Signs are encoded in the upper nibble of aktseq bytes.
	; Bits 0-2 of upper nibble: sign type (1-3, 0=none)
	; Bit 3 of upper nibble: side (0=left, 1=right)
	lea	aktseq,a6
	sub.l	a6,a1		; a1 = total length of aktseq in bytes
	move.l	a1,d7		; d7 = track length (for bounds checking)
	move.w	#35,d6		; first sign at position 35, then every 40
tryagain:
	move.w	#17,-(sp)	; XBIOS Random ($11) - generate random number
	trap	#$e
	addq.l	#2,sp		; d0 = random 24-bit value
	and.b	#%1111,d0	; keep lower 4 bits: ssst (s=side, t=type bits)
	move.b	d0,d1
	and.b	#%0111,d1	; d1 = sign type (0-7)
	cmp.b	#$3,d1		; only 3 sign types exist (1-3)
	bhi	tryagain	; type > 3: re-roll
	lsl.b	#4,d0		; shift to upper nibble
	or.b	d0,0(a6,d6)	; OR sign info into upper nibble of aktseq byte
	add.w	#40,d6		; next sign position (every 40 bytes = ~7 track segments)
	cmp.w	d7,d6		; past end of track?
	blt	tryagain	; no, place another sign

	; --- Pre-compute 16 pixel-shifted copies of scenery bitmap ---
	; The scenery (sky/mountains) scrolls horizontally. To avoid per-pixel
	; shifting at runtime, we pre-compute 16 versions of the 32-line scenery,
	; each shifted 1 pixel further right. These are stored in bitscene
	; (16 * 5120 bytes = 81920 bytes).
	;
	; Step 1: Copy the original scenery (32 lines * 160 bytes = 5120 bytes)
	move.w	aktscene,d0
	lsl.w	#2,d0		; d0 * 4 = index into scenaddr table
	lea	scenaddr,a0
	move.l	0(a0,d0),a0	; a0 = source scenery data (in signscr2)
	lea	bitscene,a1	; a1 = destination for shifted copies
	move.l	a1,a2		; a2 = keep track of current copy's start
	move.w	#1279,d0	; 1280 longwords = 5120 bytes (32 lines)
prep1:
	move.l	(a0)+,(a1)+	; copy original scenery
	dbf	d0,prep1
	;
	; Step 2: Create 15 more shifted copies (total 16 including original)
	; Each copy is the previous one shifted right by 1 pixel across all bitplanes.
	move.w	#14,d5		; 15 more copies to create (0-based counter)
prep4:
	; Copy previous version as base for next shift
	move.l	a2,a0		; a0 = previous copy
	move.l	a2,a1
	add.l	#5120,a1	; a1 = next copy (5120 bytes later)
	move.l	a1,a2		; remember new copy's start
	move.w	#1279,d0
prep2:
	move.l	(a0)+,(a1)+	; duplicate previous copy
	dbf	d0,prep2
	;
	; Shift the new copy right by 1 pixel using ROXR chains
	; In Atari ST bitplane format, shifting right means:
	;   - For each bitplane in each scanline, ROXR all 20 words
	;   - The carry from each ROXR feeds into the next word
	;   - The final carry wraps around to bit 15 of the first word
	move.l	a2,a0		; a0 = start of copy to shift
	move.w	#31,d7		; 32 scanlines
prep3d:
	move.w	#3,d6		; 4 bitplanes per scanline
prep3c:
	; ROXR chain: shift one bitplane across all 20 words of one scanline
	; Each word is at offset +8 from the previous (interleaved bitplanes)
	; 20 words * 8 bytes apart = 160 bytes per scanline
	roxr.w	0(a0)		; word 0 (leftmost 16 pixels of this plane)
	roxr.w	8(a0)		; word 1
	roxr.w	16(a0)		; word 2
	roxr.w	24(a0)		; word 3
	roxr.w	32(a0)		; word 4
	roxr.w	40(a0)		; word 5
	roxr.w	48(a0)		; word 6
	roxr.w	56(a0)		; word 7
	roxr.w	64(a0)		; word 8
	roxr.w	72(a0)		; word 9
	roxr.w	80(a0)		; word 10
	roxr.w	88(a0)		; word 11
	roxr.w	96(a0)		; word 12
	roxr.w	104(a0)		; word 13
	roxr.w	112(a0)		; word 14
	roxr.w	120(a0)		; word 15
	roxr.w	128(a0)		; word 16
	roxr.w	136(a0)		; word 17
	roxr.w	144(a0)		; word 18
	roxr.w	152(a0)		; word 19 (rightmost) - carry = bit that fell off right edge
	; Wrap carry bit: insert into bit 15 of word 0 (leftmost)
	bcc	prep3a		; carry clear? -> clear bit 15
	or.w	#$8000,(a0)	; carry set -> set bit 15 (pixel wraps from right to left)
	bra	prep3b
prep3a:
	and.w	#$7fff,(a0)	; clear bit 15
prep3b:
	addq.l	#2,a0		; advance to next bitplane (+2 bytes)
	dbf	d6,prep3c	; repeat for all 4 bitplanes
	add.l	#160-8,a0	; advance to next scanline (+160 - 8 planes already advanced)
	dbf	d7,prep3d	; repeat for all 32 scanlines
	dbf	d5,prep4	; repeat for all 15 remaining shifted copies

	; --- Initialize sky on both screen buffers ---
	bsr	setsky		; copy first (unshifted) scenery to top of both screens
	;
	; Initialize engine sound
	pea	initmtr		; motor sound init data (PSG register values)
	bsr	setsound	; write to YM2149
	addq.l	#4,sp

	; === GAME SESSION START ===
	;
	; Calculate lastdat: how many track segments fit on one screen frame.
	; Sum up fakttab entries until total lines >= 70 (visible road area).
	lea	fakttab,a2	; fakttab = line repetition counts per segment
	clr.l	d0		; d0 = segment counter
	clr.l	d1		; d1 = total scanline counter
pl0c1:
	addq.w	#1,d0		; count this segment
	move.w	(a2)+,d2	; d2 = repetition count for this segment
	addq.w	#1,d2		; +1 because fakttab values are 0-based
	add.w	d2,d1		; accumulate total scanlines
	cmp.w	#70,d1		; enough scanlines to fill road area?
	blt	pl0c1		; no, add more segments
	subq.w	#1,d0		; adjust (last segment partially fills)
	move.w	d0,lastdat	; lastdat = segments visible per frame
	;
	; Initialize score to 9998 (BCD format: $9998)
	move.w	#$9998,score
	;
	; Save MFP Timer A/B control registers for restoration later
	lea	$fffa07,a2	; MFP register base + 7
	movep.w	0(a2),d1	; read Timer A+B control via movep (bytes at +0 and +2)
	move.w	d1,reg79	; save for restoration
	;
	; Save current VBL vector and initialize lap counter
	move.l	$70,-(sp)	; save original VBL handler on stack
	move.w	nrlaps,nrlaps1	; nrlaps1 = remaining laps counter

;--- Per-lap initialization (entry point for next lap) ---
nextlap:
	; Display current lap number on dashboard
	clr.l	d0
	move.w	nrlaps,d0	; total laps
	sub.w	nrlaps1,d0	; subtract remaining
	addq.w	#1,d0		; d0 = current lap (1-based)
	lea	datascr1+80,a0	; digit sprite base
	lsl.w	#3,d0		; d0 * 8 = sprite offset
	add.l	d0,a0
	move.l	a0,-(sp)	; sprite address
	move.w	#9,-(sp)	; height = 10 lines
	move.w	#177,-(sp)	; Y position (current lap display)
	move.w	#108,-(sp)	; X position
	bsr	set16spr	; draw to both buffers
	add.l	#10,sp
	;
	; Set up track pointer and initial sign state
	lea	aktseq,a0	; a0 = pointer to current position in track sequence
	move.b	#%0100,signinfo	; initial sign = GO! sign (type 3+1=4, bit2 set)
	move.w	#40,signrow	; sign starts at distance 40
	clr.w	signcnt		; sign animation counter
	;
	; On first lap, skip re-initialization (go straight to rendering)
	; On subsequent laps, sign is already cleared
	move.w	nrlaps,d0
	cmp.w	nrlaps1,d0	; first lap?
	beq	reinit		; yes -> full initialization
	clr.w	signrow		; subsequent laps: no initial GO sign
	bra	pl2		; jump to main game loop

;--- Reinitialize game state (after crash or at race start) ---
reinit:
	clr.l	d0
	move.b	randtab,d0	; d0 = first randtab value (max speed, typically 15)
	move.w	d0,randtab2	; randtab2 = maximum speed value
	move.w	d0,randcnt	; initialize edge color counter
	move.w	#13,startcol	; starting edge color = 13
	clr.w	slowfak		; edge friction counter
	clr.w	xadd		; horizontal offset = 0 (centered on road)
	clr.w	speedfak	; actual speed = 0 (standstill)
	clr.w	joydir		; steering angle = 0 (centered)
	clr.w	scroll		; background scroll position = 0
	clr.w	gang		; gear = 0 (first gear)
	clr.w	rounds		; RPM = 0
	movem.l	d0-a6,-(sp)
	bsr	setgang		; display gear indicator sprite
	movem.l	(sp)+,d0-a6
	clr.w	scorecnt	; score decrement frame counter
	move.w	d0,speed	; speed animation counter = max (standstill)
	move.w	d0,getfak	; speed factor = max (standstill: slowest)
	bsr	speedo		; display speedometer at zero
	;
	; Install our VBL handler for scenery scrolling + raster palette split
	; Disable interrupts during vector modification to prevent races
	move.w	#$2700,SR	; disable all interrupts (IPL=7)
	lea	$fffa07,a2	; MFP Timer A control register
	clr.b	(a2)		; stop Timer A
	and.b	#%01000000,2(a2) ; stop Timer B (clear all but bit 6)
	move.l	#vbl,$70	; install our VBL interrupt handler
	move.w	#$2300,SR	; re-enable interrupts (IPL=3)
	;

;============================================================================
; MAIN GAME LOOP - FRAME RENDERING AND INPUT PROCESSING
;
; This is the heart of the racing engine. Each iteration:
;   1. Check for pause (Space) and abort (Undo/ESC)
;   2. Swap display buffers (double buffering)
;   3. Update score display
;   4. Process joystick input (steering, acceleration, braking, gear shifts)
;   5. Calculate curve physics and road perspective
;   6. Render 70 scanlines of road with edges
;   7. Draw roadside signs
;   8. Check for crashes
;   9. Advance track position based on speed
;   10. Loop back to step 1
;
; Register usage during main loop:
;   a0 = track sequence pointer (advances through aktseq)
;   a1 = alias for a0 (used in rendering section)
;   d1/d2 = road left/right edge X coordinates
;   d4 = curve accumulator
;   d7 = edge color duration counter (from randtab)
;   y1 = current Y scanline being drawn
;============================================================================

pl2:	; --- START OF FRAME ---
	; --- Check for PAUSE (Space bar, scancode $39) ---
	cmp.b	#$39,$fffc02	; read keybd (keyboard ACIA data register) directly
	bne	pl2key		; not Space -> skip pause
	; PAUSE MODE: save state, show pause screen, play music
	movem.l	d0-a6,-(sp)	; save all registers
	pea	initdat		; set PSG to maximum volume on all channels
	bsr	setsound
	addq.l	#4,sp
	move.w	#$2700,sr	; disable interrupts
	; Clear road area and show pause image from signscr2
	clr.l	d0
	; Get physical screen address from hardware registers
	; $ff8201 = high byte, $ff8203 = low byte of video base address
	move.b	$ff8201,d0	; high byte
	lsl.l	#8,d0
	move.b	$ff8203,d0	; low byte
	lsl.l	#8,d0		; d0 = physical screen address
	move.l	d0,a0		; a0 = screen to clear
	move.l	a0,a1		; a1 = screen (for pause image destination)
	; Clear road area (rows 0 to ~71: 2840 longwords = 11360 bytes)
	move.w	#2839,d0
pl0key:
	clr.l	(a0)+		; clear 4 bytes
	dbf	d0,pl0key
	; Copy pause image from signscr2+10400 to screen at row 15 (offset 2400)
	lea	signscr2+10400,a0 ; pause image source (38 lines, 160 bytes each)
	add.l	#2400,a1	; destination: 15 lines down from top
	move.w	#40*38,d0	; 40 longwords/line * 38 lines = 1520 longwords
pl0key1:
	move.l	(a0)+,(a1)+	; copy pause image
	dbf	d0,pl0key1
	;
	; Set up Timer A for pause music playback
	lea	$fffa00,a1	; MFP base
	move.b	#1,$19(a1)	; Timer A control: prescale = 4
	move.b	#$48,$1f(a1)	; Timer A data: count = $48 (72)
	clr.l	takt2		; reset music segment pointer
	clr.l	taktend2	; reset segment end
	clr.w	takptr2		; reset takt index
	or.b	#$20,7(a1)	; enable Timer A interrupt (bit 5 in MFP IERA)
	; Wait for Space bar to be released (debounce)
pl2key1:
	cmp.b	#$39,$fffc02	; Space still held?
	beq	pl2key1		; yes, wait
	; Play music during pause, wait for Timer A interrupts
pl2key2:
	bsr	playmus2	; play one music sample
pl2key1a:
	btst	#5,$fffa0b	; check Timer A interrupt pending (ISRB bit 5)
	beq	pl2key1a	; not yet -> wait
	move.b	#$df,$fffa0b	; clear Timer A interrupt in-service bit
	cmp.b	#$39,$fffc02	; Space pressed again? (unpause)
	bne	pl2key2		; no -> continue music
	; Wait for Space release again
pl2key3:
	cmp.b	#$39,$fffc02
	beq	pl2key3
	;
	; Resume game: restore sky, reinit sound
	bsr	setsky		; redraw scenery on both screen buffers
	pea	initsnd		; silence all PSG channels
	bsr	setsound
	addq.l	#4,sp
	pea	initmtr		; reinitialize motor sound
	bsr	setsound
	addq.l	#4,sp
	move.w	#$2300,sr	; re-enable interrupts
	clr.b	$fffa07		; stop Timer A
	movem.l	(sp)+,d0-a6	; restore all registers

; --- Check for ABORT (Undo key, scancode $61) ---
pl2key:
	cmp.b	#$61,$fffc02	; Undo key pressed? (keybd ACIA, scancode $61)
	bne	noabort		; no -> continue game
	; ABORT: restore system state and return to editor
	move.w	#$2700,SR	; disable interrupts
	move.l	(sp)+,$70	; restore original VBL handler
	lea	$fffa07,a2
	move.w	reg79,d1	; restore saved MFP timer control
	movep.w	d1,0(a2)	; write back Timer A+B control registers
	move.w	#$2300,SR	; re-enable interrupts
	;
	pea	initsnd		; silence PSG
	bsr	setsound
	addq.l	#4,sp
	; Restore normal screen addressing
	move.l	screen,$44e	; reset logical screen to primary
	move.b	screen+2,$ff8203 ; reset video base low byte
	move.b	screen+1,$ff8201 ; reset video base high byte
	bra	abort		; jump to cleanup (user mode, palette restore)

; --- Double buffer swap ---
noabort:
	; Swap which screen buffer is displayed vs. drawn to
	; aktscr holds the screen currently being drawn to
	lea	aktscr,a1
	move.l	screen,d1	; d1 = primary screen address
	cmp.l	(a1),d1		; are we currently drawing to primary screen?
	beq	setscr1		; yes -> switch to drawing on secondary
	; Currently drawing to screen2, switch to drawing on screen
	move.l	d1,(a1)		; next frame: draw to screen (primary)
	move.l	screen2,$44e	; display screen2 (set as logical screen)
	bra	setscr2
setscr1:
	; Currently drawing to screen, switch to drawing on screen2
	move.l	screen2,(a1)	; next frame: draw to screen2
	move.l	d1,$44e		; display screen (primary)
setscr2:
	; Write new display address to video hardware
	move.b	2(a1),$ff8203	; dbasel: video base low byte
	move.b	1(a1),$ff8201	; dbaseh: video base high byte
	move.b	1(a1),d0	; d0 = high byte for sync check
sync:
	; Wait for the Shifter to actually start reading from the new address
	; vcounthi ($ff8205) = current video counter high byte
	cmp.b	$ff8205,d0	; has hardware accepted the new address?
	bne	sync		; no -> keep waiting

	bsr	setscore	; update and display score (every 3 frames)

	; --- Initialize road rendering variables ---
	move.l	a0,a1		; a1 = track sequence pointer (alias)
	move.w	#0,d1		; d1 = road left edge X (starts at center)
	move.w	#319,d2		; d2 = road right edge X
	move.w	#70+70,y1	; y1 = bottom scanline (row 140 = 71 sky + 69 road)
	clr.l	d4		; d4 = curve accumulator (zeroed each frame)
	clr.w	scroll1		; scroll1 = per-frame scroll delta
	clr.w	xadd2		; xadd2 = per-frame horizontal delta

	; === JOYSTICK INPUT PROCESSING ===

	; --- Left steering ---
	btst	#2,joystat	; joystick bit 2 = left
	beq	pl2a		; not pressed -> skip
	addq.w	#1,scroll	; scroll background left
	subq.w	#1,scroll1	; record this frame's scroll delta
	addq.w	#4,joydir	; turn steering wheel left (+4 units)
	; Calculate steering force based on speed
	move.w	randtab2,d0	; max speed value
	sub.w	getfak,d0	; d0 = current speed (0=stopped, max=fastest)
	addq.w	#4,d0		; minimum steering effect of 4
	subq.w	#4,xadd2	; record lateral movement direction
	add.w	d0,xadd		; push car leftward (positive xadd = left of center)
pl2a:
	; --- Right steering ---
	btst	#3,joystat	; joystick bit 3 = right
	beq	pl2b		; not pressed
	subq.w	#1,scroll	; scroll background right
	addq.w	#1,scroll1
	subq.w	#4,joydir	; turn steering wheel right (-4 units)
	move.w	randtab2,d0
	sub.w	getfak,d0
	addq.w	#4,d0
	addq.w	#4,xadd2	; lateral movement right
	sub.w	d0,xadd		; push car rightward (negative xadd)

	; --- Acceleration (joystick up) ---
pl2b:
	btst	#0,joystat	; joystick bit 0 = up
	beq	pl2c		; not pressed -> check brake
	; Check for gear shift up (fire button + up)
	btst	#7,joystat	; bit 7 = fire button
	beq	pl2b2		; no fire -> just accelerate
	; SHIFT UP: fire + up when RPM is maxed out
	cmp.w	#3,gang		; already in highest gear (3)?
	beq	pl2c		; yes -> can't shift higher
	cmp.w	#3,rounds	; RPM at maximum (3)?
	bne	pl2c		; no -> can't shift yet
	addq.w	#1,gang		; shift to next gear
	clr.w	rounds		; reset RPM to 0
	bsr	setgang		; update gear indicator display
	subq.w	#1,rounds	; set to -1 (will become 0 on next acceleration)
pl2b2:
	; Normal acceleration: increase RPM
	cmp.w	#3,rounds	; RPM already at max?
	beq	pl2c		; yes -> skip
	tst.w	getfak		; already at maximum speed (getfak=0)?
	beq	pl2b1		; yes -> skip RPM change
	addq.w	#1,rounds	; increase RPM
	subq.w	#1,getfak	; decrease speed factor (lower = faster)
	move.w	getfak,speed	; reset speed counter
	bsr	setmotor	; update engine sound frequency
	bsr	speedo		; update speedometer display
pl2b1:
	; Increase actual movement speed
	move.w	randtab2,d0
	subq.w	#1,d0		; d0 = max speed - 1
	cmp.w	speedfak,d0	; already at max movement speed?
	beq	pl2d		; yes -> done with acceleration
	addq.w	#1,speedfak	; increase movement speed
	bra	pl2d

	; --- Braking (joystick down) ---
pl2c:
	btst	#1,joystat	; joystick bit 1 = down
	beq	pl2d		; not pressed -> skip
	; Check for gear shift down (fire button + down)
	btst	#7,joystat	; fire button?
	beq	pl2c2		; no -> just brake
	; SHIFT DOWN: fire + down when RPM is at minimum
	tst.w	gang		; already in lowest gear (0)?
	beq	pl2d		; yes -> can't shift lower
	tst.w	rounds		; RPM at minimum (0)?
	bne	pl2d		; no -> can't shift yet
	subq.w	#1,gang		; shift to lower gear
	move.w	#3,rounds	; set RPM to max for lower gear
	bsr	setgang		; update gear indicator
	addq.w	#1,rounds	; +1 so decspeed brings it back to 3
pl2c2:
	bsr	decspeed	; decrease speed (RPM and movement)

	; === END OF JOYSTICK PROCESSING ===
pl2d:
	; --- Auto-center steering wheel ---
	; When no left/right input, joydir decays toward 0 by 2 per frame
	tst.w	joydir		; steering centered?
	beq	joywork		; yes -> skip
	bmi	joyneg		; negative (right)
	subq.w	#2,joydir	; positive: decay toward center
	bra	joywork
joyneg:
	addq.w	#2,joydir	; negative: decay toward center
joywork:
	bsr	setsteer	; update steering wheel display

	; === CURVE PHYSICS CALCULATION ===
	; Determines how much the car drifts laterally based on:
	;   - Current curve value from track sequence
	;   - Current speed (getfak: 0=fast, max=stopped)
	;   - Whether the player is actively steering
	move.w	getfak,d7	; d7 = speed factor (0=fastest)
	addq.w	#1,d7		; d7 = 1..max+1 (avoid divide by zero)
	move.b	(a1),d0		; d0 = current track segment's curve value
	and.b	#%1111,d0	; lower nibble only (curve direction)
	; Sign-extend the 4-bit nibble to a full word
	btst	#3,d0		; bit 3 set = negative curve
	bne	negcurv1
	and.w	#%111,d0	; positive: mask to 0-7
	bra	setfak
negcurv1:
	or.w	#$fff8,d0	; negative: sign-extend ($fff8..$ffff = -8..-1)
setfak:
	tst.w	d0		; straight road (curve = 0)?
	beq	pl2d1		; yes -> different physics for straight
	;
	; CURVE PHYSICS: calculate lateral drift
	; If player is steering into the curve, use faktab (tighter response)
	; If not steering, use faktab2 (wider drift - car slides more)
	tst.w	xadd2		; is player actively steering this frame?
	beq	setfak2		; no steering -> use wider curve table
	lea	faktab,a3	; faktab: tight curve response (values 7-86)
	bra	setfak21
setfak2:
	lea	faktab2,a3	; faktab2: wide curve drift (values 14-172)
setfak21:
	; Look up drift factor based on speed (d7 = 1..16 index)
	move.b	-1(a3,d7),d7	; d7 = curve factor for current speed
	ext.w	d7		; sign-extend byte to word
	; Normalize: make curve value positive, adjust factor sign to match
	tst.w	d0
	bpl	setfak2a	; already positive
	neg.w	d0		; make positive
	neg.w	d7		; negate factor to maintain direction
setfak2a:
	; Drift = constant / factor, where constant depends on curve severity
	cmp.w	#1,d0		; gentle curve (severity 1)?
	beq.s	setfak2b
	move.l	#300,d0		; sharp curve (severity >= 2): base = 300
	bra.s	setfak2c
setfak2b:
	move.l	#220,d0		; gentle curve: base = 220
setfak2c:
	divs	d7,d0		; d0 = drift per frame (positive = push left)
	bra	pl3

	; STRAIGHT ROAD PHYSICS: car drifts back toward center
pl2d1:
	move.w	xadd,d0		; d0 = current horizontal offset
	ext.l	d0		; sign-extend for division
	divs	#8,d0		; d0 = xadd / 8 (gradual centering)
	ext.l	d0
	divs	d7,d0		; further reduce by speed factor

	; --- Apply lateral drift to road position ---
pl3:
	; Special case: if car is stationary, don't drift
	move.w	randtab2,d7	; d7 = max speed value
	cmp.w	getfak,d7	; getfak == randtab2 means standstill
	bne	pl3a		; not stationary -> apply drift
	; Stationary: only apply direct steering input, not curve physics
	move.w	scroll1,d0
	add.w	d0,scroll	; apply scroll delta
	move.w	xadd2,d0
	add.w	d0,xadd		; apply direct steering offset
	clr.w	d0		; no curve drift
pl3a:
	add.w	d0,xadd		; accumulate lateral drift
	; Apply total offset to road edge coordinates
	add.w	xadd,d1		; d1 = left edge X + horizontal offset
	add.w	xadd,d2		; d2 = right edge X + horizontal offset

	; === ROAD RENDERING SETUP ===
	lea	fakttab,a3	; a3 = perspective line-count table (70 entries)
	;
	; --- Edge color animation ---
	; The road edges alternate between colors 12 and 13, creating striped
	; appearance. The stripe width decreases with speed (faster = quicker color changes).
	lea	randtab,a4	; a4 = edge color duration table
	move.w	randcnt,d7	; d7 = current edge color countdown
	move.w	d7,randcnt2	; save for scanline loop
	move.w	startcol,randcol ; current edge color (12 or 13)
	; Advance edge color based on speed
	move.w	speedfak,d0	; d0 = movement speed (0=stopped, max=fastest)
	sub.w	d0,randcnt	; subtract speed from countdown
	bpl	pl2f		; still counting? -> keep current color
	; Countdown expired: reload from next randtab entry and toggle color
	move.w	randtab2,d0
	add.w	d0,randcnt	; reload countdown
	tst.w	randcnt		; check for underflow
	bpl	pl2f1
	move.w	d0,randcnt	; force positive
pl2f1:
	; Toggle between colors 12 and 13
	cmp.w	#13,startcol
	beq	pl2e
	move.w	#13,startcol	; switch to color 13
	bra	pl2f
pl2e:
	move.w	#12,startcol	; switch to color 12
pl2f:
	;

	; === FILL ROAD AREA WITH GRASS PATTERN ===
	; Before drawing the road, fill the entire road area (70 lines starting
	; at row 71) with grass color (color 14). Uses movem.l for fast block fill:
	; 11 registers * 4 bytes = 44 bytes per movem, 4 movems = 176 bytes,
	; but we only need 160 bytes/line, so the 4th movem is shorter (5 regs = 20 bytes).
	move.w	#69,d0		; 70 lines (0-based counter)
	movem.l	d0-a6,-(sp)	; save all registers (will be used as grass data)
	move.l	$44e,a6		; a6 = _v_bas_ad (current logical screen)
	add.l	#11360,a6	; offset to row 71 (71 * 160 = 11360)
	movem.l	wiese,d1-d7/a0-a4 ; load grass pattern into 11 registers
				   ; wiese = color 14 pattern (48 bytes of bitplane data)
drwwiese:
	movem.l	d1-d7/a0-a4,(a6)    ; write 44 bytes (pixels 0-87)
	movem.l	d1-d7/a0-a4,48(a6)  ; write 44 bytes (pixels 88-175)
	movem.l	d1-d7/a0-a4,96(a6)  ; write 44 bytes (pixels 176-263)
	movem.l	d1-d5,144(a6)	     ; write 20 bytes (pixels 264-319) [only 5 regs needed]
	; Total: 44+44+44+20 = 152 bytes... but covers full 160 byte line
	; (the grass pattern wraps correctly due to repeating tile nature)
	add.l	#160,a6		; next scanline
	dbf	d0,drwwiese	; repeat for all 70 lines
	movem.l	(sp)+,d0-a6	; restore registers

	; === ROAD RENDERING: SCANLINE-BY-SCANLINE ===
	; Draw road from bottom (row 140) to top (row 71), processing track segments.
	; Each track segment produces multiple scanlines (per fakttab).

	move.w	d0,aktrow	; aktrow = 69 (counts down to 0)
	;
	; Check if the last visible track segment has sign info
	move.w	lastdat,d3
	move.b	0(a1,d3),d3	; read the segment that appears at the horizon
	lsr.b	#4,d3		; upper nibble = sign info
	tst.b	d3		; any sign?
	beq	pl1		; no sign -> skip
	move.b	d3,signinfo	; save sign type and side info
	clr.w	signrow		; sign starts at distance 0 (farthest)
	clr.w	signcnt		; reset sign animation counter

; --- Process one track segment ---
; Each segment in aktseq has a curve value (lower nibble) and may have
; sign info (upper nibble). The curve value is sign-extended to give
; the number of pixels the road shifts per scanline.
pl1:
	move.b	(a1)+,d3	; read next track segment byte
	and.b	#%1111,d3	; extract curve value (lower nibble)
	cmp.b	#7,d3		; end-of-track marker?
	beq	endoftr		; yes -> race complete, process end
	; Sign-extend 4-bit curve value to word
	btst	#3,d3		; negative (bit 3 set)?
	bne	negcurve
	and.w	#%111,d3	; positive: 0-7
	bra	showtr
negcurve:
	or.w	#$fff8,d3	; sign-extend: $fff8-$ffff = -8 to -1

showtr:
	; Get line repetition count for this segment from fakttab
	; fakttab values: bottom segments repeat 8x (thick/close), top segments 0x (thin/far)
	move.w	(a3)+,d5	; d5 = repetition count (0-based)

; --- Draw repeated scanlines for this segment ---
lineloop:
	; Update edge color animation
	dbf	d7,rand1	; decrement color duration counter
	; Counter expired: advance to next randtab entry and toggle color
	add.w	randcnt2,a4	; advance randtab pointer by current duration
	clr.l	d7
	move.b	(a4),d7		; d7 = new duration from randtab
	move.w	d7,randcnt2	; save new duration
	; Toggle edge color between 12 and 13
	cmp.w	#13,randcol
	beq	rand2
	move.w	#13,randcol
	bra	rand1
rand2:
	move.w	#12,randcol
rand1:
	; --- Calculate curve offset for this scanline ---
	; d4 = running curve accumulator (adds d3 each scanline)
	; Perspective: closer rows (higher aktrow) get more curve shift
	add.w	d3,d4		; d4 += curve value
	move.w	d4,d6
	ext.l	d6		; sign-extend for division
	; Perspective division: divide by (2*aktrow + 1)
	; This makes distant rows (low aktrow) shift less than near rows
	move.w	aktrow,d0
	lsl.w	#1,d0		; d0 = aktrow * 2
	addq.w	#1,d0		; d0 = aktrow * 2 + 1
	divs	d0,d6		; d6 = perspective-adjusted curve offset
	add.w	d6,d1		; adjust left edge
	add.w	d6,d2		; adjust right edge
	;
	; --- Apply lateral distortion from xadd (off-center car position) ---
	; The car's horizontal offset causes the road to appear shifted.
	; This effect increases toward the bottom of the screen (closer).
	move.l	d1,-(sp)	; save road edge positions
	move.l	d2,-(sp)
	move.w	xadd,d0		; d0 = horizontal offset
	move.w	aktrow,d6
	sub.w	#70,d6		; d6 = aktrow - 70 (negative = further from camera)
	muls	d6,d0		; d0 = xadd * (aktrow - 70)
	divs	#100,d0		; perspective scaling
	beq	pl3b		; zero offset -> skip
	add.w	d0,d2		; shift right edge
	add.w	d0,d1		; shift left edge
pl3b:
	; --- Calculate road edge width ---
	; Edge width grows toward the bottom (closer = wider)
	move.w	aktrow,d6	; d6 = current row (69=bottom, 0=top)
	move.w	d6,d0		; save for later
	lsr.w	#2,d6		; d6 = aktrow / 4 (edge width in pixels)
	addq.w	#1,d6		; minimum 1 pixel wide
	;
	; --- Draw LEFT edge ---
	move.w	d1,x1		; x1 = left edge start
	move.w	d1,x2		; x2 = left edge end
	sub.w	d6,x1		; extend left by edge width
	; Record left edge position for sign placement
	cmp.w	signrow,d0	; is this the sign's row?
	bne	no1
	move.w	x1,signleft	; save left edge X for sign positioning
no1:
	move.w	randcol,col	; set edge color (12 or 13)
	bsr	hline		; draw left edge line
	;
	; --- Draw ROAD surface ---
	move.w	d1,x1		; x1 = road left boundary
	move.w	d2,x2		; x2 = road right boundary
	clr.w	col		; road color = 0 (black)
	bsr	hline		; draw road surface
	;
	; --- Draw RIGHT edge ---
	move.w	d2,x1		; x1 = right edge start
	move.w	d2,x2
	add.w	d6,x2		; extend right by edge width
	; Record right edge position for sign placement
	cmp.w	signrow,d0
	bne	no2
	move.w	x2,signrigt	; save right edge X for sign positioning
no2:
	move.w	randcol,col	; set edge color
	bsr	hline		; draw right edge line
	;
	; Advance to next scanline
	subq.w	#1,y1		; move up one screen row
	move.l	(sp)+,d2	; restore road edge positions (before distortion)
	move.l	(sp)+,d1
	; Apply road widening factor from rowtab
	; rowtab makes the road slightly wider toward the bottom
	lea	rowtab,a5
	move.w	aktrow,d0
	lsl.w	#1,d0		; word index
	move.w	0(a5,d0),d0	; d0 = widening amount (2 or 3 pixels)
	add.w	d0,d1		; widen left (move left edge left)
	sub.w	d0,d2		; widen right (move right edge right)
	subq.w	#1,aktrow	; advance row counter (toward horizon)
	;
	dbf	d5,lineloop	; repeat for all scanlines of this segment
	;
	tst.w	aktrow		; reached top of road area (row 0)?
	bpl	pl1		; no -> process next track segment

	; === SIGN/BILLBOARD RENDERING ===
	; After road rendering, draw any visible roadside sign.
	; Signs grow larger as they approach (distance tracked by signrow).
	move.b	signinfo,d0	; sign info byte: bits 0-2 = type, bit 3 = side
	and.l	#$7,d0		; mask sign type (1-3, 0 = no sign)
	beq	nosign1		; no sign -> skip
	;
	; Look up sign sprite data based on type
	subq.l	#1,d0		; make 0-based (type 1->0, 2->1, 3->2)
	lsl.w	#2,d0		; longword index into signtab
	lea	signtab,a1
	move.l	0(a1,d0),a2	; a2 = base address of sign sprite data
	;
	; Determine sign size based on distance (signrow)
	; signrtab maps distance -> size index (0=smallest to 8=largest)
	lea	signrtab,a1
	move.w	signrow,d1	; d1 = sign distance (0=far, 70=close)
	move.w	d1,d6
	lsr.w	#1,d6		; d6 = gap between sign and road edge
	move.b	0(a1,d1),d1	; d1 = size index for this distance
	and.w	#$ff,d1		; byte -> word
	lsl.w	#1,d1		; word index for signlen table
	lea	signlen,a1
	move.w	0(a1,d1),d5	; d5 = sign width in pixels (16, 32, or 64)
	lsl.w	#1,d1		; longword index for signoffs table
	lea	signoffs,a1
	add.l	0(a1,d1),a2	; add offset to get specific size variant
	;
	; Determine X position based on which side of the road (bit 3 of signinfo)
	btst	#3,signinfo	; bit 3: 0=left side, 1=right side
	bne	sright
	; Left side: sign is to the left of the road
	move.w	signleft,d1	; d1 = left road edge X
	sub.w	d5,d1		; move left by sign width
	sub.w	d6,d1		; add gap from road
	bra	sside
sright:
	; Right side: sign is to the right of the road
	move.w	signrigt,d1	; d1 = right road edge X
	add.w	d6,d1		; add gap from road
sside:
	; Calculate Y position: sign base is at row 71, adjusted by signrow
	move.w	#71-65,d0	; base Y offset (6 = row 71 - sign height 65)
	add.w	signrow,d0	; d0 = Y position for sign top
	;
	; Draw sign sprite(s) - wider signs need multiple 16-pixel columns
	; First column (always drawn):
	move.l	a2,-(sp)	; sprite data address
	move.w	#64,-(sp)	; height = 65 lines (64 + 1 from 0-base)
	move.w	d0,-(sp)	; Y position
	move.w	d1,-(sp)	; X position
	bsr	setsign		; draw first 16-pixel column
	add.l	#10,sp
	cmp.w	#16,d5		; is sign only 16 pixels wide?
	beq	decsign		; yes -> done
	; Second column (for 32+ pixel signs):
	addq.l	#8,a2		; advance to next column's bitplane data
	add.w	#16,d1		; X + 16
	move.l	a2,-(sp)
	move.w	#64,-(sp)
	move.w	d0,-(sp)
	move.w	d1,-(sp)
	bsr	setsign
	add.l	#10,sp
	cmp.w	#32,d5		; 32 pixels wide?
	beq	decsign		; yes -> done
	; Third and fourth columns (for 64-pixel signs):
	addq.l	#8,a2
	add.w	#16,d1
	move.l	a2,-(sp)
	move.w	#64,-(sp)
	move.w	d0,-(sp)
	move.w	d1,-(sp)
	bsr	setsign
	add.l	#10,sp
	addq.l	#8,a2
	add.w	#16,d1
	move.l	a2,-(sp)
	move.w	#64,-(sp)
	move.w	d0,-(sp)
	move.w	d1,-(sp)
	bsr	setsign
	add.l	#10,sp

; --- Advance sign toward camera ---
decsign:
	subq.w	#1,signcnt	; decrement sign animation delay counter
	bpl	nosign1		; still counting -> don't advance
	addq.w	#1,signcnt	; undo decrement (keep at 0)
	tst.w	speedfak	; car stationary?
	beq	nosign1		; yes -> signs don't move
	; Calculate new delay: slower speed = longer between sign advances
	move.w	randtab2,d0
	sub.w	speedfak,d0	; d0 = inverse speed (higher = slower)
	clr.l	d1
	move.w	signrow,d1
	add.w	#40,d1		; d1 = distance + 40 (perspective factor)
	divu	#20,d1		; d1 = step size (closer = bigger steps)
	divu	d1,d0		; d0 = delay before next advance
	move.w	d0,signcnt	; set new delay counter
	add.w	d1,signrow	; advance sign closer by step size
	cmp.w	#70,signrow	; sign passed the camera? (signrow >= 70)
	blt	nosign1		; no -> still visible
	; Sign has passed: clear sign state
	clr.b	signinfo	; no active sign
	move.w	#-1,signrow	; invalid row
	clr.w	signcnt

	; === CRASH DETECTION ===
nosign1:
	; Check if car is on the road edge (|xadd| >= 130)
	move.w	xadd,d0		; d0 = horizontal offset from center
	cmp.w	#130,d0		; too far right?
	bge	nos1
	cmp.w	#-130,d0	; too far left?
	ble	nos1
	bra	nos3		; on the road -> no edge effects
nos1:
	; ON THE EDGE: play scraping sound and slow down
	tst.w	speedfak	; stationary?
	beq	nos3		; yes -> no friction
	movem.l	d0-a6,-(sp)
	pea	randsnd		; edge/scraping sound effect (PSG noise)
	bsr	setsound	; play on channel C
	addq.l	#4,sp
	subq.w	#1,slowfak	; friction timer
	bpl	nos4		; not yet -> skip deceleration
	bsr	decspeed	; slow the car down
	move.w	#10,slowfak	; reset friction timer (every 10 frames)
nos4:
	movem.l	(sp)+,d0-a6
	bra	nos2
nos3:
	; Not on edge: silence channel C (edge sound)
	move.b	#10,$ff8800	; giselect: select gicamp (channel C amplitude)
	clr.b	$ff8802		; giwrite: volume = 0 (silent)
nos2:
	; --- Full crash check: |xadd| >= 300 ---
	move.w	xadd,d0
	cmp.w	#300,d0		; way off the road to the right?
	bge	crash		; CRASH!
	cmp.w	#-300,d0	; way off to the left?
	ble	crash		; CRASH!
	;
	; --- Sign collision check ---
	; If a sign is close (signrow > 64) and car is on that side
	cmp.w	#64,signrow	; sign close enough to collide?
	ble	nocrash		; no -> safe
	move.b	signinfo,d1
	beq	nocrash		; no active sign -> safe
	btst	#3,d1		; bit 3: sign is on right side?
	beq	ltstside	; no -> sign is on left, check normally
	neg.w	d0		; sign on right: negate offset for comparison
ltstside:
	cmp.w	#140,d0		; car offset > 140 on sign's side?
	ble	nocrash		; within safe range -> no collision
;============================================================================
; CRASH ROUTINE
; Triggered when the car goes too far off the road or hits a sign.
; Plays explosion animation with fire palette cycling and sound,
; penalizes score by 30 points, resets car state, and resumes racing.
;============================================================================
crash:
	movem.l	d0-a6,-(sp)	; save all registers
	; Replace VBL with empty handler during crash animation
	move.w	#$2700,sr	; disable interrupts
	move.l	#leervbl,$70	; install do-nothing VBL (just RTE)
	move.w	#$2300,sr	; re-enable
	;
	; --- Display explosion frame ---
	; Switch video hardware to show primary screen
	lea	$ff8201,a1	; dbaseh (video display base address)
	move.b	screen+1,(a1)	; set dbaseh (high byte)
	move.b	screen+2,2(a1)	; set dbasel (low byte, at +2)
	; Copy explosion image from film buffer to screen
	lea	film,a0		; source: crash animation frame
	move.l	screen,a1	; destination: primary screen
	move.w	#7999,d0	; 32000 bytes
crash1:
	move.l	(a0)+,(a1)+
	dbf	d0,crash1
	;
	; --- Start explosion sound via Timer A ---
	bsr	settimer	; install explosion sound interrupt handler
	;
	; --- Fire palette cycling animation ---
	; Save current palette, then set explosion palette
	lea	$ff8240,a1	; hardware palette registers
	movem.l	(a1),d0-d7	; save all 16 colors
	movem.l	d0-d7,-(sp)	; push onto stack
	movem.l	filmpal+2,d0-d7	; load explosion palette (from film.pi1 header)
	movem.l	d0-d7,(a1)	; set explosion colors
	;
	; Rotate palette colors 60 times to simulate flickering fire
	move.w	#60,d6		; 60 rotation cycles
crash1a:
	; Synchronize to raster beam (wait for specific screen position)
	lea	$ff8240,a2	; color0 (palette base)
	lea	$ff8207,a3	; vcountmid (video counter mid byte)
	move.l	screen,d0	; d0 = screen base (for comparison)
crash1b:
	; movep reads vcountmid(+0) and vcountlow(+2) into d1.w
	movep.w	0(a3),d1	; d1 = current raster beam position
	cmp.w	d1,d0		; wait for specific position
	bne	crash1b
	;
	; Rotate palette: shift colors 1-8 left by one position
	; This creates a cycling fire effect
	move.w	$2(a2),d5	; save color 1
	movem.l	$4(a2),d0-d3	; load colors 2-9
	movem.l	d0-d3,2(a2)	; shift colors 2-9 to positions 1-8
	move.w	d5,$12(a2)	; old color 1 goes to position 9
	; Brief delay between rotations
	move.w	#290,d7
crash1e:
	dbf	d7,crash1e	; ~290 cycles delay
	dbf	d6,crash1a	; repeat 60 times
	;
	; Reset to explosion palette (clean state after rotations)
	movem.l	filmpal+2,d0-d7
	movem.l	d0-d7,(a2)
	; Longer delay to let player see the aftermath
	move.l	#$10000,d0	; ~65536 iterations
crash1d:
	subq.l	#1,d0
	bne.s	crash1d
	;
	; --- Restore normal state ---
	bsr	resettim	; stop explosion sound timer
	; Restore screen from screen2 (clean cockpit backup)
	move.l	screen2,a1
	move.l	screen,a2
	move.w	#7999,d0
crash2:
	move.l	(a1)+,(a2)+	; copy cockpit back to screen
	dbf	d0,crash2
	; Restore saved palette
	lea	$ff8240,a1
	movem.l	(sp)+,d0-d7	; pop saved palette from stack
	movem.l	d0-d7,(a1)	; write back to hardware
	;
	; --- Score penalty: subtract 30 points (BCD arithmetic) ---
	; Score is stored in packed BCD format (e.g., $9998 = 9998)
	; SBCD (Subtract BCD with Extend) performs decimal subtraction
	move.w	#$30,d0		; penalty: 30 in BCD
	moveq.l	#0,d3		; high byte subtraction: 0
	move.b	score+1,d1	; d1 = low byte of score (tens + units)
	move.b	score,d2	; d2 = high byte of score (thousands + hundreds)
	sbcd	d0,d1		; d1 = d1 - $30 (BCD subtraction with extend)
	sbcd	d3,d2		; d2 = d2 - 0 - borrow (propagate borrow)
	bcc	noext		; no underflow (carry clear)
	; Score underflowed below 0000: clamp to 0
	clr.w	d1
	clr.w	d2
noext:
	move.b	d1,score+1	; store updated low byte
	move.b	d2,score	; store updated high byte
	;
	; --- Reset car state ---
	clr.w	xadd		; center car on road
	clr.w	gang		; reset to gear 0
	clr.w	rounds		; reset RPM to 0
	pea	initmtr		; reinitialize engine sound
	bsr	setsound
	addq.l	#4,sp
	bsr	setmotor	; set motor frequency for gear 0, RPM 0
	;
	; Reinstall VBL handler
	move.w	#$2700,sr
	move.l	#vbl,$70	; restore our game VBL
	move.w	#$2300,sr
	movem.l	(sp)+,d0-a6	; restore all registers
	bra	reinit		; reinitialize speed/steering and resume racing

;============================================================================
; TRACK ADVANCEMENT (no crash)
; Each frame, the track pointer advances based on speed.
; speed counts down from getfak to 0; when it reaches 0, advance by 1 segment.
;============================================================================
nocrash:
	move.w	speed,d0	; d0 = speed animation counter
	cmp.w	randtab2,d0	; is getfak == randtab2 (standstill)?
	beq	pl2		; yes -> don't advance, just redraw
	tst.w	d0		; counter reached 0?
	beq	pl5		; yes -> advance track
	subq.w	#1,speed	; decrement counter
	bra	pl2		; next frame (no track advance this frame)
pl5:
	; Counter reached 0: advance track by one segment
	move.w	getfak,speed	; reset counter to current speed factor
	addq.l	#1,a0		; advance track pointer by 1 byte
	bra	pl2		; next frame

;============================================================================
; END OF TRACK - LAP COMPLETE
; Reached when curve value 7 (end marker) is encountered in aktseq.
;============================================================================
endoftr:
	subq.w	#1,nrlaps1	; decrement remaining laps counter
	bne	nextlap		; more laps remaining -> continue racing
	;
	; === ALL LAPS COMPLETE ===
	; Restore system interrupt state
	move.w	#$2700,SR	; disable interrupts
	move.l	(sp)+,$70	; restore original VBL handler
	lea	$fffa07,a2
	move.w	reg79,d1	; restore MFP timer control
	movep.w	d1,0(a2)	; write Timer A+B control registers
	move.w	#$2300,SR	; re-enable interrupts
	;
	pea	initsnd		; silence all PSG channels
	bsr	setsound
	addq.l	#4,sp
	;
	; Set video to show primary screen
	lea	$ff8201,a1
	move.b	screen+1,(a1)	; video base high byte
	move.b	screen+2,2(a1)	; video base low byte
	move.l	screen,a1
	move.l	a1,$44e		; set logical screen
	;
	; Clear screen for game over message
	move.w	#7999,d0
end1:
	clr.l	(a1)+
	dbf	d0,end1
	;
	; Display "GAME OVER - PLAYER X" message
	move.w	nrplay1,d0	; d0 = current player index (0-3)
	add.b	#"1",d0		; convert to ASCII '1'-'4'
	move.b	d0,aktplay	; patch player number into gameover string
	pea	gameover	; "GAME OVER\nPLAYER X"
	bsr	palprint	; display with colored font
	addq.l	#4,sp
	;
	; Play game-over music and animate palette
	bsr	prepdigi	; start digital music playback
	clr.w	cnt1		; palette animation delay counter
end4:
	btst	#7,joystat	; fire button pressed?
	bne	end3		; yes -> advance to next player
	; Palette rotation animation (pulsing colors)
	subq.w	#1,cnt1		; decrement delay
	bpl	end4		; still counting -> wait
	move.w	#4000,cnt1	; reset delay counter
	; Rotate palette colors to create pulsing effect
	lea	$ff8240,a0
	move.w	8(a0),d0	; save color 4
	move.l	4(a0),6(a0)	; shift colors 2-3 -> 3-4
	move.w	2(a0),4(a0)	; color 1 -> 2
	move.w	d0,2(a0)	; saved color 4 -> 1
	; Same rotation for colors 9-12
	move.w	18(a0),d0	; save color 9
	move.l	20(a0),18(a0)	; shift 10-11 -> 9-10
	move.w	24(a0),22(a0)	; 12 -> 11
	move.w	d0,24(a0)	; saved 9 -> 12
	bra	end4
	;
end3:
	; Save this player's score and advance to next player
	bsr	resettim	; stop music
	move.w	nrplay1,d0	; d0 = current player index
	lea	plscore,a0	; plscore = array of 4 scores
	lsl.w	#1,d0		; word index
	move.w	score,0(a0,d0)	; save this player's score
	addq.w	#1,nrplay1	; advance to next player
	move.w	nrplay1,d0
	cmp.w	nrplayer,d0	; all players done?
	bne	end2		; no -> start next player's race
	;
	; === ALL PLAYERS FINISHED ===
	; Restore screen to normal
	move.l	screen,$44e	; reset logical screen
	move.b	screen+2,$ff8203
	move.b	screen+1,$ff8201
	; Process high scores and display results
	bsr	calc_hi		; check if any player earned a high score
	bsr	show_hi		; display high score table with music
	;
; --- Return to editor (shared by abort and normal end) ---
abort:
	; Return to user mode
	move.w	#$20,-(sp)	; GEMDOS Super ($20) - leave supervisor
	trap	#1
	addq.l	#6,sp
	bsr	mouseon		; show mouse cursor
	; Restore editor palette
	pea	pic+2		; editor palette (from trcs.pi1 header)
	move.w	#6,-(sp)	; XBIOS Setpalette ($06)
	trap	#$e
	addq.l	#6,sp
	rts			; return to editor loop (via com_play)

;============================================================================
; PLAY MODE SUPPORT ROUTINES
;============================================================================

;----------------------------------------------------------------------------
; joyirq - Joystick interrupt handler (installed via XBIOS Kbdvbase)
;
; Called by the IKBD when a joystick packet arrives.
; The packet format: $ff, event_type, joystick_data
; We only care about joystick 1 (marker byte = $ff at offset 0).
;
; Parameter: a0 = pointer to IKBD packet data
; Joystick byte format (joystat):
;   Bit 0 = Up, Bit 1 = Down, Bit 2 = Left, Bit 3 = Right, Bit 7 = Fire
;----------------------------------------------------------------------------
joyirq:
	cmp.b	#$ff,(a0)	; is this a joystick 1 packet? ($ff = joy1)
	bne	joyirq1		; no -> ignore
	move.b	2(a0),joystat	; store joystick state byte (offset 2 in packet)
joyirq1:
	rts


;----------------------------------------------------------------------------
; setsky - Initialize sky/scenery on both screen buffers
;
; Copies the first (unshifted) scenery from bitscene to the top 39 lines
; of both screen and screen2. This creates the static sky background that
; the VBL handler will scroll over.
;
; The copy is done column by column (40 longwords wide) to efficiently
; replicate each column across 39 lines.
;----------------------------------------------------------------------------
setsky:
	lea	bitscene,a0	; a0 = source scenery data (32 lines, 160 bytes each)
	move.l	screen,a1	; a1 = destination: primary screen top
	move.l	screen2,a2	; a2 = destination: secondary screen top
	move.w	#39,d0		; 40 longword columns (40 * 4 = 160 bytes per line)
prep6:
	move.l	(a0)+,d7	; d7 = one longword of scenery data
	move.w	#38,d1		; copy to 39 lines (0-based)
	move.l	a1,a3		; a3 = column pointer for screen
	move.l	a2,a4		; a4 = column pointer for screen2
prep6a:
	move.l	d7,(a3)		; write to screen
	move.l	d7,(a4)		; write to screen2
	add.l	#160,a3		; next line (160 bytes per line)
	add.l	#160,a4
	dbf	d1,prep6a	; repeat for 39 lines
	addq.l	#4,a1		; advance to next longword column
	addq.l	#4,a2
	dbf	d0,prep6	; repeat for all 40 columns
	rts

;============================================================================
; SOUND SYSTEM
;============================================================================

;----------------------------------------------------------------------------
; setsound - Write a sequence of register/value pairs to the YM2149 PSG
;
; The YM2149 Programmable Sound Generator (PSG) has 14 registers:
;   Regs 0-5: Tone period (channels A, B, C - 12-bit, two regs each)
;   Reg 6: Noise period (5-bit)
;   Reg 7: Mixer control (bits 0-5: tone/noise enable for A,B,C)
;   Regs 8-10: Volume/envelope mode (channels A, B, C)
;   Regs 11-12: Envelope period (16-bit)
;   Reg 13: Envelope shape
;
; PSG is accessed via $ff8800 (register select) and $ff8802 (data write).
;
; Parameter: 4(sp) = pointer to byte pairs (register, value, ..., -1)
; Special handling for register 7: preserves bits 6-7 (I/O port direction)
;   and only modifies bits 0-5 (mixer enables).
;----------------------------------------------------------------------------
setsound:
	clr.b	$484		; clear conterm: disable keyboard click
	lea	$ff8800,a0	; a0 = giselect/giread (PSG register select/read port)
	move.l	4(sp),a1	; a1 = pointer to register/value pairs
ton1:
	move.b	(a1)+,d0	; d0 = register number
	bmi	end		; negative = end marker (-1)
	move.b	(a1)+,d1	; d1 = value to write
	move.b	d0,(a0)		; select PSG register via giselect
	cmp.b	#7,d0		; is this gimixer (mixer/I/O control)?
	beq	spezial		; yes -> special handling
	move.b	d1,2(a0)	; write value to giwrite ($ff8802)
	bra	ton1		; next pair
spezial:
	; gimixer (reg 7): preserve I/O port direction bits (6-7), only set mixer enables (0-5)
	move.b	(a0),d0		; read current gimixer value via giread
	and.b	#%11000000,d0	; keep bits 6-7 (I/O direction)
	or.b	d1,d0		; OR in new mixer bits
	move.b	d0,2(a0)	; write combined value
	bra	ton1
end:
	rts

;----------------------------------------------------------------------------
; setmotor - Update engine sound based on current gear and RPM
;
; Uses channels A (reg 0-1) and B (reg 2-3) of the PSG.
; Each gear has 4 RPM levels with corresponding frequency values.
; Channel B is detuned by -40 from channel A for a richer engine sound.
;
; The gangsnd table points to 4 gear sub-tables (gang0-gang3).
; Each sub-table has 4 word entries (RPM 0-3) with frequency values.
; RPM is inverted: index 0 = highest RPM, 3 = lowest RPM.
;----------------------------------------------------------------------------
setmotor:
	lea	gangsnd,a2	; gangsnd = array of 4 pointers to gear tables
	move.w	gang,d0		; d0 = current gear (0-3)
	lsl.w	#2,d0		; longword index
	move.l	0(a2,d0),a2	; a2 = pointer to this gear's frequency table
	move.w	#3,d0
	sub.w	rounds,d0	; d0 = 3 - RPM (inverted: 0=high RPM, 3=low RPM)
	lsl.w	#1,d0		; word index
	lea	$ff8800,a3	; giselect port
	move.w	0(a2,d0),d0	; d0 = frequency value (word)
	; Channel A: gitoneaf (reg 0, fine) and gitoneac (reg 1, coarse)
	move.b	#0,(a3)		; select gitoneaf (channel A fine tune)
	move.b	d0,2(a3)	; write low byte of frequency to giwrite
	sub.b	#40,d0		; detune channel B by -40 for richer sound
	move.b	#2,(a3)		; select gitonebf (channel B fine tune)
	move.b	d0,2(a3)	; write detuned low byte
	lsr.w	#8,d0		; d0 = high byte of frequency
	move.b	#1,(a3)		; select gitoneac (channel A coarse tune)
	move.b	d0,2(a3)	; write high byte
	move.b	#3,(a3)		; select gitonebc (channel B coarse tune)
	move.b	d0,2(a3)	; write high byte (same for both channels)
	rts

;----------------------------------------------------------------------------
; setgang - Display gear indicator sprite on dashboard
;
; Shows the current gear (0-3) as a sprite at position (207, 186).
; Gear sprites are stored in datascr1 at offset 20160, each 8 bytes wide
; (16 pixels) and 8 lines tall.
;----------------------------------------------------------------------------
setgang:
	lea	datascr1+20160,a3 ; base of gear indicator sprites
	clr.l	d0
	move.w	gang,d0		; d0 = current gear (0-3)
	lsl.w	#3,d0		; d0 * 8 = byte offset to gear sprite
	add.l	d0,a3		; a3 = sprite data address
	move.l	a3,-(sp)	; push sprite address
	move.w	#7,-(sp)	; height = 8 lines
	move.w	#186,-(sp)	; Y position on dashboard
	move.w	#207,-(sp)	; X position on dashboard
	bsr	set16spr	; draw to both screen buffers
	add.l	#10,sp
	rts

;----------------------------------------------------------------------------
; speedo - Display speedometer on dashboard
;
; Shows current speed as a gauge sprite. Speed = randtab2 - getfak
; (0 = stopped, randtab2 = maximum speed).
; Speed sprites are in datascr1 at offset 1600 (first row: 0-9)
; and offset 4000 (second row: 10-19). Each sprite is 16 pixels wide,
; displayed as two 16-pixel columns at (201,158) and (217,158).
;
; Each speed position uses 16 bytes (2 words per plane * 4 planes * 2 columns?
; No - actually 16 bytes per column = 2 longwords per line).
;----------------------------------------------------------------------------
speedo:
	clr.l	d0
	move.w	randtab2,d0	; max speed
	sub.w	getfak,d0	; d0 = current speed (0 to randtab2)
	lea	datascr1,a3
	add.l	#1600,a3	; a3 = base of speed sprites (row 1: positions 0-9)
	cmp.w	#10,d0		; speed >= 10? (need second row)
	blt	speedo1
	add.l	#2400,a3	; advance to row 2 (10+)
	sub.w	#10,d0		; adjust index
speedo1:
	lsl.w	#4,d0		; d0 * 16 = byte offset to speed sprite
	add.l	d0,a3		; a3 = sprite data for this speed level
	; Draw left half of speedometer
	move.l	a3,-(sp)	; sprite address
	move.w	#14,-(sp)	; height = 15 lines
	move.w	#158,-(sp)	; Y
	move.w	#201,-(sp)	; X (left column)
	bsr	set16spr
	add.l	#10,sp
	; Draw right half of speedometer
	addq.l	#8,a3		; advance to next 16-pixel column
	move.l	a3,-(sp)
	move.w	#14,-(sp)
	move.w	#158,-(sp)
	move.w	#217,-(sp)	; X (right column = left + 16)
	bsr	set16spr
	add.l	#10,sp
	rts

;----------------------------------------------------------------------------
; setscore - Update score display (called every frame)
;
; Every 3 frames, decrements score by 2 (BCD) and redraws the 4-digit
; score display at position (89, 161) and (105, 161) on the dashboard.
;
; Score format: 2-byte packed BCD (e.g., $9998 = score 9998)
;   score byte 0 = thousands + hundreds ($99)
;   score byte 1 = tens + units ($98)
;----------------------------------------------------------------------------
setscore:
	addq.w	#1,scorecnt	; increment frame counter
	cmp.w	#3,scorecnt	; every 3 frames?
	ble	noscore		; not yet -> skip
	clr.w	scorecnt	; reset counter
	movem.l	d0-a6,-(sp)
	; Subtract 2 from score using BCD arithmetic
	moveq.l	#2,d0		; BCD value to subtract
	moveq.l	#0,d3		; zero for high byte borrow propagation
	move.b	score+1,d1	; d1 = tens+units byte
	move.b	score,d2	; d2 = thousands+hundreds byte
	sbcd	d0,d1		; BCD subtract: d1 = d1 - 2 (with extend)
	sbcd	d3,d2		; propagate borrow to high byte
	bcc	noext2		; no underflow? -> keep result
	clr.w	d1		; underflow: clamp to 0000
	clr.w	d2
noext2:
	move.b	d1,score+1	; store updated tens+units
	move.b	d2,score	; store updated thousands+hundreds
	;
	; Convert and display high byte (thousands + hundreds digits)
	move.w	d1,-(sp)	; save low byte for later
	move.w	d2,d0		; d0 = high BCD byte (e.g., $99)
	bsr	dezspr		; convert to sprite data -> sprwork1
	pea	sprwork1	; sprite address
	move.w	#9,-(sp)	; height = 10 lines
	move.w	#161,-(sp)	; Y position
	move.w	#89,-(sp)	; X position (left 2 digits)
	bsr	set16spr
	add.l	#10,sp
	;
	; Convert and display low byte (tens + units digits)
	move.w	(sp)+,d0	; d0 = low BCD byte (e.g., $98)
	bsr	dezspr		; convert to sprite data -> sprwork1
	pea	sprwork1
	move.w	#9,-(sp)
	move.w	#161,-(sp)
	move.w	#89+16,-(sp)	; X position (right 2 digits, +16 pixels)
	bsr	set16spr
	add.l	#10,sp
	;
	movem.l	(sp)+,d0-a6
noscore:
	rts

;----------------------------------------------------------------------------
; dezspr - Convert a BCD byte into a 16-pixel-wide composite digit sprite
;
; Takes a byte with two BCD nibbles (e.g., $93 = digits 9 and 3) and
; composites the two 8-pixel-wide digit sprites into sprwork1.
;
; Parameter: d0.w = BCD byte (upper nibble = tens, lower nibble = units)
; Result: sprwork1 filled with 10 lines of composited sprite data
;
; Digit sprites are at the start of datascr1, each 8 pixels wide (1 longword
; per line in screen format), 10 lines tall, spaced 8 bytes apart.
; The tens digit is copied directly; the units digit is shifted right by 8
; pixels and OR'd on top.
;----------------------------------------------------------------------------
dezspr:
	lea	datascr1,a0	; a0 = digit sprite base (for tens digit)
	move.l	a0,a1		; a1 = digit sprite base (for units digit)
	move.w	d0,d7		; save BCD value
	and.w	#$f0,d0		; isolate tens nibble (e.g., $90)
	lsr.w	#1,d0		; /2 = byte offset (x8 for each digit, /16*8 = /2)
	add.w	d0,a0		; a0 = tens digit sprite address
	lea	sprwork1,a2	; a2 = output buffer
	move.l	a2,a3		; a3 = copy for units digit overlay
	; Copy tens digit (left 8 pixels)
	move.w	#9,d1		; 10 lines
dezspr1:
	move.l	(a0)+,(a2)+	; copy 4 bytes (planes 0+1)
	move.l	(a0),(a2)	; copy 4 bytes (planes 2+3) without advancing
	add.l	#160-4,a0	; next source line (+160 - 4 already read)
	add.l	#160-4,a2	; next output line
	dbf	d1,dezspr1
	; Overlay units digit (right 8 pixels, shifted right by 8)
	and.w	#$0f,d7		; isolate units nibble
	lsl.w	#3,d7		; *8 = byte offset for units digit
	add.w	d7,a1		; a1 = units digit sprite address
	move.w	#9,d1		; 10 lines
dezspr2:
	move.l	(a1)+,d0	; read units digit planes 0+1
	lsr.l	#8,d0		; shift right by 8 pixels (1 byte in bitplane terms)
	or.l	d0,(a3)+	; OR onto output (merges with tens digit)
	move.l	(a1),d0		; read planes 2+3
	lsr.l	#8,d0		; shift right by 8
	or.l	d0,(a3)		; OR onto output
	add.l	#160-4,a1	; next source line
	add.l	#160-4,a3	; next output line
	dbf	d1,dezspr2
	rts

;----------------------------------------------------------------------------
; setsteer - Display steering wheel at current position
;
; Shows one of 9 steering wheel positions (-4 to +4) on the dashboard.
; The wheel sprite is 64 pixels wide (4 x 16-pixel columns) and 43 lines tall.
; Only redraws when the position changes (oldjdir tracks last drawn position).
;
; joydir ranges from about -16 to +16; divide by 4 gives -4 to +4.
; Steering wheel sprites are in datascr1 at offset 6400.
; steertab provides the byte offset for each of the 9 positions.
;----------------------------------------------------------------------------
setsteer:
	move.w	joydir,d0	; d0 = raw steering value
	ext.l	d0		; sign-extend for division
	divs	#4,d0		; d0 = wheel position (-4 to +4)
	cmp.w	oldjdir,d0	; same as last frame?
	beq	nosteer		; yes -> no need to redraw
	move.w	d0,oldjdir	; save current position
	; Clamp to valid range
	tst.w	d0
	bmi	steerneg
	cmp.w	#4,d0		; max positive = +4
	ble	steerok
	subq.w	#1,oldjdir	; clamp: undo over-increment
	subq.w	#4,joydir
	bra	nosteer		; skip drawing
steerneg:
	cmp.w	#-4,d0		; max negative = -4
	bge	steerok
	addq.w	#1,oldjdir	; clamp: undo over-decrement
	addq.w	#4,joydir
	bra	nosteer
steerok:
	movem.l	d0-a6,-(sp)
	lea	datascr1+6400,a0 ; base of steering wheel sprites
	lea	steertab,a1	  ; offset table for 9 positions
	addq.w	#4,d0		  ; map -4..+4 to 0..8
	lsl.w	#2,d0		  ; longword index
	add.l	0(a1,d0),a0	  ; a0 = sprite data for current wheel position
	; Draw 4 columns of 16 pixels each (64 pixels wide total)
	move.l	a0,-(sp)	; column 1 (leftmost)
	move.w	#42,-(sp)	; height = 43 lines
	move.w	#154,-(sp)	; Y
	move.w	#132,-(sp)	; X
	bsr	set16spr
	add.l	#10,sp
	addq.l	#8,a0		; next column (+8 bytes = next 16-pixel group)
	move.l	a0,-(sp)	; column 2
	move.w	#42,-(sp)
	move.w	#154,-(sp)
	move.w	#132+16,-(sp)	; X + 16
	bsr	set16spr
	add.l	#10,sp
	addq.l	#8,a0
	move.l	a0,-(sp)	; column 3
	move.w	#42,-(sp)
	move.w	#154,-(sp)
	move.w	#132+32,-(sp)	; X + 32
	bsr	set16spr
	add.l	#10,sp
	addq.l	#8,a0
	move.l	a0,-(sp)	; column 4 (rightmost)
	move.w	#42,-(sp)
	move.w	#154,-(sp)
	move.w	#132+48,-(sp)	; X + 48
	bsr	set16spr
	add.l	#10,sp
	movem.l	(sp)+,d0-a6
nosteer:
	rts

;============================================================================
; VBL INTERRUPT HANDLER - Scenery scrolling and raster palette split
;
; Called 50 times per second (PAL) or 60 times (NTSC) during the game.
; Two functions:
;   1. Copy scrolled scenery bitmap to the sky area (top 32 lines)
;   2. Wait for raster beam to reach the road area, then switch palette
;      from scenery colors to game/dashboard colors (raster split effect)
;
; The scroll variable determines the horizontal offset of the scenery.
; One of 16 pre-shifted bitmaps (in bitscene) is selected based on the
; sub-pixel component, and the coarse offset determines where to start
; reading within that bitmap.
;============================================================================
vbl:
	movem.l	d0-a6,-(sp)	; save all registers
	move.w	SR,-(sp)	; save status register
	lea	$ff8240,a6	; a6 = color0 (base of 16 palette registers)
	;
	; --- Set scenery palette ---
	move.w	aktscene,d0	; current scenery (0-2)
	lsl.w	#2,d0
	lea	paladdr,a0	; paladdr = array of 3 palette pointers
	move.l	0(a0,d0),a0	; a0 = palette for current scenery
	movem.l	(a0),d0-d7	; load 16 color words (32 bytes)
	movem.l	d0-d7,(a6)	; write to hardware palette
	;
	; --- Calculate scrolled scenery source ---
	; scroll can be positive (scrolled left) or negative (scrolled right)
	; We need to wrap it to 0-319 range and find:
	;   1. Which of 16 pre-shifted bitmaps to use (sub-pixel)
	;   2. Where to start reading within that bitmap (coarse offset)
	move.w	scroll,d0	; d0 = horizontal scroll offset
	bpl	vblpos		; positive -> handle normally
	; Negative scroll: negate and handle as mirror
	neg.w	d0
vblneg:
	cmp.w	#320,d0		; wrap to 0-319
	blt	vbln1
	sub.w	#320,d0
	bra	vblneg
vbln1:
	; For negative scroll, the math is slightly different
	move.w	d0,d2
	lsr.w	#1,d0		; d0 = scroll/2 (byte offset in scanline)
	and.l	#$fff8,d0	; align to 8-byte group boundary
	and.w	#$f,d2		; d2 = sub-pixel (0-15)
	move.w	#15,d1
	sub.w	d2,d1		; d1 = 15 - sub_pixel (select shifted bitmap)
	lsl.w	#2,d1		; longword index into bitoffs table
	lea	bitoffs,a0	; bitoffs = array of 16 bitmap base addresses
	move.l	0(a0,d1),a0	; a0 = pre-shifted bitmap for this sub-pixel
	move.l	a0,a2		; a2 = bitmap base (for wrap-around)
	addq.l	#8,d0		; adjust offset
	bra	vblok
vblpos:
	; Positive scroll
	cmp.w	#320,d0		; wrap to 0-319
	blt	vblp1
	sub.w	#320,d0
	bra	vblpos
vblp1:
	move.w	d0,d1
	lsr.w	#1,d0		; byte offset
	and.l	#$fff8,d0	; align to 8-byte boundary
	move.w	#160,d2
	sub.w	d0,d2		; d2 = bytes from start to end of line
	move.w	d2,d0		; d0 = start offset (reading from right side)
	and.l	#$f,d1		; d1 = sub-pixel
	lsl.w	#2,d1		; longword index
	lea	bitoffs,a0
	move.l	0(a0,d1),a0	; a0 = pre-shifted bitmap
	move.l	a0,a2		; a2 = bitmap base
vblok:
	; a0 + d0 = starting read position in the bitmap
	; The scenery wraps: read (160-d0) bytes from position d0,
	; then d0 bytes from position 0 (wrap-around)
	add.l	d0,a0		; a0 = read position (offset into bitmap line)
	move.w	#160,d1
	sub.w	d0,d1		; d1 = bytes remaining to end of line
	move.w	d0,d3		; d3 = bytes from start (for wrap portion)
	lsr.w	#3,d3		; /8 = number of 8-byte groups to wrap
	lsr.w	#3,d1		; /8 = number of 8-byte groups before wrap
	move.w	#31,d5		; 32 scanlines of scenery
	move.l	$44e,a1		; a1 = _v_bas_ad (current display buffer)
	; Set background color for transition (visible during scroll setup)
	move.w	#$100,$ff8240	; dark red background (color 0)
	add.l	#39*160,a1	; a1 = screen row 39 (just above road area)
	; --- Copy 32 lines of scrolled scenery ---
	; For each line: copy two sections (before and after wrap point)
vbl7:
	move.w	d1,d2		; d2 = groups before wrap
	move.w	d3,d4		; d4 = groups after wrap
	; Copy first portion (from current offset to end of scenery line)
	tst.w	d2
	beq	vbl6a		; no groups before wrap
	subq.w	#1,d2		; dbf is 0-based
vbl5:
	move.l	(a0)+,(a1)+	; copy 8 bytes per iteration
	move.l	(a0)+,(a1)+	; (2 longwords = 1 eight-byte group)
	dbf	d2,vbl5
vbl6a:
	; Copy second portion (wrap: from start of scenery line)
	move.l	a2,a0		; reset source to bitmap line start
	tst.w	d4
	beq	vbl6b		; no wrap-around groups needed
	subq.w	#1,d4
vbl6:
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	dbf	d4,vbl6
vbl6b:
	; Advance to next scenery line
	add.l	#160,a2		; next line in pre-shifted bitmap
	move.l	a2,a0		; reset read pointer
	add.l	d0,a0		; add coarse offset
	dbf	d5,vbl7		; repeat for all 32 lines

	; === RASTER SPLIT: Wait for beam to reach road area, then switch palette ===
	; This creates the illusion of two independent palettes on one screen:
	; - Top (sky): scenery palette (already set above)
	; - Bottom (road + dashboard): game palette (playpal)
	;
	; Load game palette into registers (ready to blast when beam arrives)
	movem.l	playpal+2,d3-d7/a2-a4 ; 8 registers = 16 color words (skip color 0)
	;
	; Calculate the video address where row 71 begins
	; Read current video base from hardware using movep trick:
	; $ff8201 = high byte, $ff8203 = low byte -> combine into word
	moveq.l	#0,d0
	lea	$ff8201,a0	; dbaseh (video display base address high byte)
	movep.w	0(a0),d0	; movep reads dbaseh(+0) and dbasel(+2) into d0.w
	lsl.l	#8,d0		; shift to form full 24-bit address
	add.l	#71*160,d0	; d0 = address where road starts (row 71)
	addq.l	#6,a0		; a0 = $ff8207 = vcountmid (video counter mid byte)
	;
	; Busy-wait for the raster beam to reach the road area
	move.w	waitcnt,d2	; d2 = timeout counter (680 for PAL, 790 for NTSC)
vbl1:
	subq.w	#1,d2		; decrement timeout
	beq	vbl3		; timeout: switch palette anyway (avoid infinite loop)
	movep.w	0(a0),d1	; movep reads vcountmid(+0) and vcountlow(+2) into d1.w
	cmp.w	d0,d1		; has beam reached row 71?
	blt	vbl1		; not yet -> keep waiting
vbl3:
	; Beam has reached the road area: switch to game palette!
	movem.l	d3-d7/a2-a4,(a6) ; blast 16 colors to $ff8240 in one instruction
	;
	move.w	(sp)+,SR	; restore status register
	movem.l	(sp)+,d0-a6	; restore all registers
leervbl:			; empty VBL handler (used during crash animation)
	rte			; return from exception

;============================================================================
; MFP TIMER SETUP FOR SOUND PLAYBACK
;
; The MFP 68901 (Multi-Function Peripheral) provides 4 timers (A-D).
; Timer A is used for interrupt-driven digital sound/music playback.
;
; MFP register map (at $fffa00):
;   $07: IERA (Interrupt Enable A)   $0b: IPRA (Interrupt Pending A)
;   $0f: IMRA (Interrupt Mask A)     $13: ISRA (Interrupt In-Service A)
;   $17: VR (Vector Register)        $19: TACR (Timer A Control)
;   $1f: TADR (Timer A Data)
;
; Timer A interrupt vector is at $134 in the 68000 vector table.
;============================================================================

;----------------------------------------------------------------------------
; settimer - Start explosion sound playback via Timer A
; Saves current MFP state, configures Timer A, installs playexpl handler.
;----------------------------------------------------------------------------
settimer:
	pea	initdat		; set all PSG volumes to max
	bsr	setsound
	addq.l	#4,sp
	move	#$2700,sr	; disable interrupts
	; Save current MFP register state (for later restoration)
	; MFP 68901 base = $fffa00 (mfp); registers at odd byte offsets
	lea	$fffa00,a1	; a1 = mfp base address
	move.b	$f(a1),reg0f	; save isra (Interrupt In-Service A, mfp+$f)
	move.b	$b(a1),reg0b	; save ipra (Interrupt Pending A, mfp+$b)
	move.b	$13(a1),reg13	; save imra (Interrupt Mask A, mfp+$13)
	move.b	$7(a1),reg07	; save iera (Interrupt Enable A, mfp+$7)
	move.b	$19(a1),reg19	; save tacr (Timer A Control, mfp+$19)
	move.b	$17(a1),reg17	; save vr (Vector Register, mfp+$17)
	; Configure Timer A for explosion sound
	bclr	#5,$f(a1)	; isra: clear Timer A in-service bit
	bclr	#5,$b(a1)	; ipra: clear Timer A pending bit
	bset	#5,$13(a1)	; imra: unmask Timer A interrupt
	bset	#5,$7(a1)	; iera: enable Timer A interrupt
	move.b	#1,$19(a1)	; tacr: prescale = /4
	move.b	#$38,$1f(a1)	; tadr: count = $38 (56) -> interrupt rate
	ori.b	#$08,$17(a1)	; vr: set SEI (Software End of Interrupt) mode
	; Install explosion sound handler
	move.l	$134,timerirq	; save original Timer A vector
	move.l	#playexpl,$134	; install our handler
	; Reset playback state
	clr.l	takt1		; current segment pointer
	clr.l	taktend1	; segment end pointer
	clr.w	tloop1		; note duration counter
	clr.w	takptr1		; takt index
	move.w	#$2300,sr	; re-enable interrupts
	rts

;----------------------------------------------------------------------------
; resettim - Restore MFP state (stop sound playback)
; Restores all saved MFP registers and the original Timer A vector.
;----------------------------------------------------------------------------
resettim:
	move.w	#$2700,sr	; disable interrupts
	move.l	timerirq,$134	; restore original Timer A vector
	lea	$fffa00,a1	; mfp base
	move.b	reg0f,$f(a1)	; restore isra (mfp+$f)
	move.b	reg0b,$b(a1)	; restore ipra (mfp+$b)
	move.b	reg13,$13(a1)	; restore imra (mfp+$13)
	move.b	reg07,$7(a1)	; restore iera (mfp+$7)
	move.b	reg19,$19(a1)	; restore tacr (mfp+$19)
	move.b	reg17,$17(a1)	; restore vr (mfp+$17)
	move.w	reg79,d1	; restore Timer A+B control (iera+ierb)
	movep.w	d1,7(a1)	; movep writes d1.hi->iera(+7), d1.lo->ierb(+9)
	move.w	#$2300,sr	; re-enable interrupts
	rts

;============================================================================
; EXPLOSION SOUND PLAYBACK (Timer A interrupt handler)
;
; Plays the explosion sound effect from the explsnd buffer.
; Each sample byte: upper nibble = duration, lower nibble = volume level.
; All 3 PSG channels are set to the same volume (uniform explosion sound).
;============================================================================

; playexpl - Timer A interrupt handler for explosion sound
playexpl:
	movem.l	d0-a6,-(sp)
	;
	subq.w	#1,tloop1	; decrement note duration counter
	cmp.w	#-1,tloop1	; expired?
	bne	playlop1	; no -> continue playing current note
	; Load next sample byte from explosion data
play1:
	clr.w	d6
	clr.w	d5
	move.l	takt1,a1	; a1 = current position in sound segment
	cmp.l	taktend1,a1	; reached end of current segment?
	bne	play1a		; no -> read next byte
	bsr	nxttakt		; yes -> load next segment from taktable
	move.l	takt1,a1
play1a:
	move.b	(a1)+,d5	; d5 = sample byte
	move.l	a1,takt1	; advance position
	move.b	d5,d6
	lsr.b	#4,d6		; d6 = upper nibble = duration
	cmp.w	#$0f,d6		; maximum duration?
	bne	play1b
	subq.w	#1,d6		; cap at 14 (prevent excessively long notes)
play1b:
	and.b	#$0f,d5		; d5 = lower nibble = volume level (0-15)
	move.w	d6,tloop1	; set duration counter
	move.w	d5,note1	; save volume for repeated writes
playlop1:
	; Write volume to all 3 PSG channels (uniform explosion sound)
	lea	$ff8800,a0	; giselect
	move.w	note1,d5
	move.b	#8,(a0)		; select giaamp (channel A amplitude)
	move.b	d5,2(a0)	; write volume to giwrite
	move.b	#9,(a0)		; select gibamp (channel B amplitude)
	move.b	d5,2(a0)
	move.b	#10,(a0)	; select gicamp (channel C amplitude)
	move.b	d5,2(a0)
	;
	movem.l	(sp)+,d0-a6
	bclr	#5,$fffa0f	; clear Timer A interrupt in-service bit (SEI mode)
	rte			; return from interrupt

;----------------------------------------------------------------------------
; nxttakt - Load next explosion sound segment from taktable
;
; The explosion sound is divided into segments referenced by taktable.
; Each taktable entry is 2 longwords: start_offset, end_offset (relative to explsnd).
; The t1 sequence (byte array) determines which taktable entry to use.
; Sequence ends with -1 which causes it to loop.
;----------------------------------------------------------------------------
nxttakt:
	clr.l	d0
gett1:
	move.w	takptr1,d0	; d0 = current index into t1 sequence
	lea	t1,a1
	add.l	d0,a1
	move.b	(a1),d0		; d0 = taktable entry index
	cmp.b	#-1,d0		; end of sequence?
	bne	n1
	clr.w	note1		; silence
	clr.w	takptr1		; restart from beginning
	bra.s	gett1		; re-read first entry
n1:
	clr.w	tloop1		; reset duration counter
	lsl.w	#2,d0		; d0 * 4 = offset into taktable (2 longs per entry, 8 bytes,
				; but entries are pairs so *4 gives first long offset)
	lea	taktable,a1
	move.l	0(a1,d0),a2	; a2 = segment start offset (relative)
	add.l	#explsnd,a2	; convert to absolute address
	move.l	a2,takt1	; set current read position
	move.l	4(a1,d0),a2	; a2 = segment end offset
	add.l	#explsnd,a2
	move.l	a2,taktend1	; set segment end
	addq.w	#1,takptr1	; advance t1 sequence index
	rts

;============================================================================
; DIGITAL MUSIC PLAYBACK (Title screen and pause mode)
;
; Uses Timer A interrupt to play multi-channel music from the digisnd buffer.
; Each sample byte indexes into loudtab (64 entries, 12 bytes each) which
; contains pre-computed PSG register values for 3 channels.
;============================================================================

;----------------------------------------------------------------------------
; playdigi - Play digital music until keypress (blocking)
; Used for the title screen: starts playback, waits for key, returns.
;----------------------------------------------------------------------------
playdigi:
	bsr	prepdigi	; set up Timer A for music
	move.w	#7,-(sp)	; GEMDOS Crawcin ($07) - blocking key read
	trap	#1
	addq.l	#2,sp
	rts

;----------------------------------------------------------------------------
; prepdigi - Set up Timer A for digital music playback
; Same as settimer but installs playmus handler and uses different timing.
;----------------------------------------------------------------------------
prepdigi:
	pea	initdat		; max volume on all channels
	bsr	setsound
	addq.l	#4,sp
	move	#$2700,sr	; disable interrupts
	lea	$fffa00,a1	; mfp base
	; Save MFP state (same registers as settimer)
	move.b	$f(a1),reg0f	; save isra
	move.b	$b(a1),reg0b	; save ipra
	move.b	$13(a1),reg13	; save imra
	move.b	$7(a1),reg07	; save iera
	move.b	$19(a1),reg19	; save tacr
	move.b	$17(a1),reg17	; save vr
	; Configure Timer A for music playback
	bclr	#5,$f(a1)	; isra: clear Timer A in-service
	bclr	#5,$b(a1)	; ipra: clear Timer A pending
	bset	#5,$13(a1)	; imra: unmask Timer A
	bset	#5,$7(a1)	; iera: enable Timer A
	move.b	#1,$19(a1)	; tacr: prescale = /4
	move.b	#$48,$1f(a1)	; tadr: count = $48 (72) -> music sample rate
	ori.b	#$08,$17(a1)	; vr: set SEI mode
	; Install music handler
	move.l	$134,timerirq	; save original vector
	move.l	#playmus,$134	; install music player
	clr.l	takt2		; reset segment pointer
	clr.l	taktend2
	clr.w	takptr2
	movep.w	7(a1),d1	; save Timer A+B control
	move.w	d1,reg79
	move.w	#$2300,sr	; re-enable interrupts
	rts

;----------------------------------------------------------------------------
; playmus - Timer A interrupt handler for digital music
; Thin wrapper that calls playmus2 and handles interrupt acknowledgment.
;----------------------------------------------------------------------------
playmus:
	movem.l	d0-a6,-(sp)
	bsr	playmus2	; do the actual music processing
	movem.l	(sp)+,d0-a6
	bclr	#5,$fffa0f	; clear Timer A in-service bit
	rte

;----------------------------------------------------------------------------
; playmus2 - Music player core (can be called from interrupt or main loop)
;
; Reads one byte from the current music segment in digisnd.
; Uses the byte as an index into loudtab (64 entries, 12 bytes each).
; Each loudtab entry contains 3 longwords that are written directly to
; the PSG via movem.l to $ff8800 (register+data pairs for 3 channels).
;
; The byte is masked to $fc (bits 0-1 cleared) and multiplied by 3
; to get the offset: (byte & $fc) + (byte & $fc)*2 = byte*3 & ~3.
; This gives 12-byte aligned access to loudtab entries.
;----------------------------------------------------------------------------
playmus2:
	move.l	takt2,a1	; a1 = current position in music segment
	cmp.l	taktend2,a1	; reached end of segment?
	bne	play2a		; no -> read next byte
	bsr	nxttakt2	; yes -> load next segment
	move.l	takt2,a1
play2a:
	move.b	(a1)+,d5	; d5 = sample byte
	move.l	a1,takt2	; advance position
	; Convert sample byte to loudtab index
	lea	loudtab,a1
	and.w	#$fc,d5		; clear low 2 bits (align to 4-byte boundary)
	move.w	d5,d1
	lsl.w	#1,d1		; d1 = d5 * 2
	add.w	d1,d5		; d5 = d5 * 3 (total: 12 bytes per entry)
	; Load 3 longwords of PSG register/value data from loudtab
	movem.l	0(a1,d5.w),d1-d3
	; Boost volume slightly (+$300 to each longword's low word)
	add.w	#$300,d1	; channel A volume boost
	add.w	#$300,d2	; channel B volume boost
	add.w	#$300,d3	; channel C volume boost
	; Write all 3 channel settings to PSG in one instruction
	; movem.l to $ff8800 writes consecutive register/value pairs
	movem.l	d1-d3,$ff8800
	;
	rts

;----------------------------------------------------------------------------
; nxttakt2 - Load next music segment from taktabl2
; Same structure as nxttakt but for digital music (uses t2 sequence and taktabl2).
; Loops when t2 sequence reaches -1 marker.
;----------------------------------------------------------------------------
nxttakt2:
	clr.l	d0
gett2:
	move.w	takptr2,d0	; d0 = index into t2 sequence
	lea	t2,a1
	add.l	d0,a1
	move.b	(a1),d0		; d0 = taktabl2 entry index
	cmp.b	#-1,d0		; end of sequence?
	bne	n2
	clr.w	takptr2		; restart from beginning
	bra.s	gett2
n2:
	lsl.w	#2,d0		; d0 * 4 = offset into taktabl2
	lea	taktabl2,a1
	move.l	0(a1,d0),a2	; segment start offset
	add.l	#digisnd,a2	; convert to absolute address
	move.l	a2,takt2	; set current position
	move.l	4(a1,d0),a2	; segment end offset
	add.l	#digisnd,a2
	move.l	a2,taktend2	; set segment end
	addq.w	#1,takptr2	; advance sequence index
	rts

;============================================================================
; PRE-GAME SELECTION SCREENS (Laps and Players)
;
; Both use a similar pattern:
;   1. Clear screen
;   2. Install color-cycling VBL handler for visual effect
;   3. Display prompt text with palprint (colored font)
;   4. Poll joystick for left/right selection and fire to confirm
;   5. Restore original VBL handler
;============================================================================

;----------------------------------------------------------------------------
; asklaps - Select number of laps (1-9)
; Uses joystick left/right to change, fire button to confirm.
; Background color 0 pulses through vbllpal color table.
;----------------------------------------------------------------------------
asklaps:
	move.l	screen,a0
	move.w	#7999,d0
askl1:
	clr.l	(a0)+		; clear screen to black
	dbf	d0,askl1
	; Install color-cycling VBL handler
	move.w	#$2700,sr
	move.l	$70,timerirq	; save current VBL vector
	clr.w	vbllcnt		; reset color cycle counter
	clr.w	vbllcnt1	; reset sub-counter
	move.l	#lapvbl,$70	; install lap selection VBL
	move.w	#$2300,sr
	; Display header text
	pea	askltxt		; "Select Number of Laps"
	bsr	palprint	; display with colored font
	addq.l	#4,sp
askl2:
	; Clear lower portion of screen for number display
	move.l	screen,a0
	add.l	#110*160,a0	; start at row 110
	move.w	#1999,d0	; clear 8000 bytes (50 lines)
askl3:
	clr.l	(a0)+
	dbf	d0,askl3
	; Display current lap count
	move.w	nrlaps,d0
	add.w	#$30,d0		; convert to ASCII digit
	move.b	d0,asciilap	; patch into display string
	pea	askltxt1	; string containing the digit
	bsr	palprint
	addq.l	#4,sp
	; Poll joystick
askl2a:
	btst	#7,joystat	; fire button pressed?
	bne	asklend		; yes -> confirm selection
	btst	#2,joystat	; left pressed?
	beq	asklrigt	; no -> check right
	cmp.w	#1,nrlaps	; already at minimum (1)?
	beq	askl2a		; yes -> ignore
	subq.w	#1,nrlaps	; decrease laps
	bra	askl2		; redisplay
asklrigt:
	btst	#3,joystat	; right pressed?
	beq	askl2a		; no -> keep polling
	cmp.w	#9,nrlaps	; already at maximum (9)?
	beq	askl2a		; yes -> ignore
	addq.w	#1,nrlaps	; increase laps
	bra	askl2		; redisplay
asklend:
	; Restore original VBL handler
	move.w	#$2700,sr
	move.l	timerirq,$70
	move.w	#$2300,sr
	rts

;----------------------------------------------------------------------------
; lapvbl - VBL handler for lap selection screen color cycling
; Cycles through vbllpal (16 color values) at 1/5 frame rate, applied to
; color 0 (background). Creates a pulsing glow effect.
;----------------------------------------------------------------------------
lapvbl:
	movem.l	d0-a6,-(sp)
	move	sr,-(sp)
	subq.w	#1,vbllcnt1	; sub-frame counter (rate divider)
	bpl	lapvbl2		; not yet -> skip color change
	move.w	#5,vbllcnt1	; reset: change color every 5 VBLs
	subq.w	#1,vbllcnt	; advance through color table
	bmi	lapvbl1		; past end? -> reset
	move.w	vbllcnt,d0
	lsl.w	#1,d0		; word index into vbllpal
	lea	vbllpal,a0	; 16-entry color cycle table
	move.w	0(a0,d0),$ff8240 ; set color 0 (background)
	bra	lapvbl2
lapvbl1:
	move.w	#16,vbllcnt	; reset to beginning of cycle
lapvbl2:
	move	(sp)+,sr
	movem.l	(sp)+,d0-a6
	rte

;----------------------------------------------------------------------------
; askplay - Select number of players (1-4)
; Same structure as asklaps but for player count.
;----------------------------------------------------------------------------
askplay:
	move.l	screen,a0
	move.w	#7999,d0
askp1:
	clr.l	(a0)+		; clear screen
	dbf	d0,askp1
	; Install color-cycling VBL
	move.w	#$2700,sr
	move.l	$70,timerirq
	clr.w	vblpcnt
	clr.w	vblpcnt1
	move.l	#playvbl,$70	; install player selection VBL
	move.w	#$2300,sr
	pea	askptxt		; "Select Number of Players"
	bsr	palprint
	addq.l	#4,sp
askp2:
	move.l	screen,a0
	add.l	#110*160,a0
	move.w	#1999,d0
askp3:
	clr.l	(a0)+
	dbf	d0,askp3
	move.w	nrplayer,d0
	add.w	#$30,d0		; convert to ASCII
	move.b	d0,asciplay	; patch into string
	pea	askptxt1
	bsr	palprint
	addq.l	#4,sp
askp2a:
	btst	#7,joystat	; fire -> confirm
	bne	askpend
	btst	#2,joystat	; left -> decrease
	beq	askprigt
	cmp.w	#1,nrplayer	; minimum 1 player
	beq	askp2a
	subq.w	#1,nrplayer
	bra	askp2
askprigt:
	btst	#3,joystat	; right -> increase
	beq	askp2a
	cmp.w	#4,nrplayer	; maximum 4 players
	beq	askp2a
	addq.w	#1,nrplayer
	bra	askp2
askpend:
	move.w	#$2700,sr
	move.l	timerirq,$70
	move.w	#$2300,sr
	rts

;----------------------------------------------------------------------------
; playvbl - VBL handler for player selection color cycling
; Same as lapvbl but uses vblppal color table.
;----------------------------------------------------------------------------
playvbl:
	movem.l	d0-a6,-(sp)
	move	sr,-(sp)
	subq.w	#1,vblpcnt1
	bpl	pvbl2
	move.w	#5,vblpcnt1
	subq.w	#1,vblpcnt
	bmi	pvbl1
	move.w	vblpcnt,d0
	lsl.w	#1,d0
	lea	vblppal,a0
	move.w	0(a0,d0),$ff8240
	bra	pvbl2
pvbl1:
	move.w	#16,vblpcnt
pvbl2:
	move	(sp)+,sr
	movem.l	(sp)+,d0-a6
	rte

;============================================================================
; TEXT PRINTING SYSTEM
;
; Two printing routines that render text character-by-character using Line-A
; text blit ($A008). Both use a custom color scheme where each character's
; color decreases through a 4-character gradient (prntcol counts down).
;
; Special characters in palprint strings:
;   $00 = end of string
;   $0d = carriage return (new line)
;   '"' = reset color palette to mode 1 (colors 4-1)
;   '!' = reset color palette to mode 2 (colors 12-9)
;   < $20 = ignored (control codes)
;
; The text wraps to the next line every ~320 pixels (9-pixel characters).
; When the screen is full (y >= 188), it waits for a keypress, clears
; the screen, and continues printing.
;============================================================================

;----------------------------------------------------------------------------
; palprint - Print text with palette-setting capability
;
; Sets up a custom palette (prpal) for text display, then renders
; each character using Line-A with descending color indices.
;
; Parameter: 4(sp) = pointer to text string
;
; Color scheme:
;   d6 = pixel X position (advances by 1 per char within word, then +5 gap)
;   d7 = pixel Y position (advances by 12 per line)
;   prntcol = current color index (decreases per character in a word)
;   prntpal = starting color for each word (set by " and ! markers)
;
; The unusual X advancement (d6 += 1 per char, then d6 += 5 per word)
; creates proportional-like spacing using the Line-A 8x8 system font.
;----------------------------------------------------------------------------
palprint:
	; Set custom palette for text display
	movem.l	prpal+4,d1-d7	; load 14 colors (colors 2-15)
	movem.l	d1-d7,$ff8244	; write to palette registers 2-15
	move.w	prpal+2,$ff8242	; set color 1
	;
	move.l	4(sp),a0	; a0 = text string pointer
	move.w	#4,prntpal	; default: start color = 4 (mode 1)
	move.w	#0,d6		; X position = 0
	move.w	#0,d7		; Y position = 0
pr2:
	move.w	#3,d0		; d0 = character counter within word (4 chars per word)
	move.w	prntpal,prntcol	; reset color to word start value
	clr.w	d5
	move.b	(a0)+,d5	; read next character
	beq	prquit		; null = end of string
	cmp.b	#$d,d5		; carriage return?
	beq	cr		; yes -> new line
	cmp.b   #'"',d5		; quote = color mode 1 marker?
	bne.s	pr3
	move.w	#4,prntpal	; set color start to 4 (bright text)
	bra.s	pr2		; skip this char, continue
pr3:	cmp.w	#'!',d5		; exclamation = color mode 2 marker?
	bne.s	pr1
	move.w	#8+4,prntpal	; set color start to 12 (dimmer text)
	bra.s	pr2
pr1:
	cmp.b	#$20,d5		; printable character? (>= space)
	blt	pr2		; no -> skip control codes
	bsr	prprint		; render character using Line-A
	add.w	#1 ,d6		; advance X pixel position
	add.w	#1 ,d7		; advance Y tracking (for proportional effect)
	sub.w	#1,prntcol	; decrease color index (gradient effect)
	dbf	d0,pr1		; more chars in current word? -> continue
	; End of 4-char word: add spacing gap
	add.w	#5 ,d6		; inter-word gap (5 extra pixels)
	sub.w	#4,d7		; adjust Y tracking back
	cmp.w	#320,d6		; past right edge?
	blt	pr2		; no -> continue
cr:	; New line
	clr.w	d6		; reset X to left edge
	move.w	#8+4,prntpal	; reset to dim color mode
	add.w	#12,d7		; advance Y by 12 pixels (line height)
	cmp.w	#188,d7		; past bottom of screen?
	blt	pr2		; no -> continue
	; Screen full: wait for keypress, clear screen, continue
	movem.l	d0-a7,saver	; save all registers (including sp!)
	move.w	#7,-(sp)	; GEMDOS Crawcin ($07) - wait for key
	trap	#1
	movem.l	saver,d0-a7	; restore registers
	; Clear screen for next page
	clr.w	d6
	clr.w	d7
	move.l	screen,a6
	move.w	#7999,d0
prclear:clr.l	(a6)+
	dbf	d0,prclear
	bra	pr2		; continue printing
prquit:
	rts

;----------------------------------------------------------------------------
; hiprint - Print text without palette changes (for high score display)
;
; Same rendering as palprint but uses fixed color 12 and doesn't set palette.
; Used to display high scores over the hiscore.pi1 background image.
;
; Parameter: 4(sp) = pointer to text string
;----------------------------------------------------------------------------
hiprint:
	move.l	4(sp),a0	; a0 = text string pointer
	move.w	#12,prntpal	; fixed color = 12 (bright on hiscore background)
	move.w	#0,d6		; X = 0
	move.w	#0,d7		; Y = 0
hpr2:
	move.w	#3,d0		; 4 chars per word
	move.w	prntpal,prntcol
	clr.w	d5
	move.b	(a0)+,d5
	beq	hprquit		; null = end
	cmp.b	#$d,d5		; CR?
	beq	hcr
hpr1:
	cmp.b	#$20,d5		; printable?
	blt	hpr2		; skip control codes
	bsr	prprint		; render character
	add.w	#1 ,d6
	add.w	#1 ,d7
	subq.w	#1,prntcol
	dbf	d0,hpr1
	;
	add.w	#5,d6
	sub.w	#4,d7
	cmp.w	#320,d6
	blt	hpr2
hcr:	clr.w	d6
	move.w	#12,prntpal
	add.w	#12,d7
	cmp.w	#188,d7
	blt	hpr2
	; Screen full: wait for key and clear
	movem.l	d0-a7,saver
	move.w	#7,-(sp)
	trap	#1
	movem.l	saver,d0-a7
	clr.w	d6
	clr.w	d7
	move.l	screen,a6
	move.w	#7999,d0
prclr:	clr.l	(a6)+
	dbf	d0,prclr
	bra	hpr2
hprquit:
	rts



;----------------------------------------------------------------------------
; prprint - Render a single character using Line-A text blit ($A008)
;
; Uses the Line-A text blit to draw one character at position (d6, d7)
; in the color specified by prntcol.
;
; Parameters (in registers, not on stack):
;   d5 = character ASCII code
;   d6 = X pixel position
;   d7 = Y pixel position
;   prntcol = foreground color index
;
; Line-A variables (offsets from varhead base):
;   36: write mode (1 = overwrite)
;   64: text style ($8000 = normal)
;   72: source X offset (character bitmap X start)
;   74: source Y offset (0)
;   76: destination X
;   78: destination Y
;   80: character width
;   82: character height
;   84: font data pointer
;   88: font form width
;   106: foreground color
;
; Font header (offsets from fonthead base):
;   36: first ASCII character in font
;   72: character offset table pointer
;   76: font data base pointer
;   80: font form width (bytes per scanline)
;   82: character cell height
;----------------------------------------------------------------------------
prprint:
	movem.l	d0-a6,saver
	move.l	varhead,a0	; a0 = Line-A variable base
	move.l	fonthead,a2	; a2 = font header
	move.w	d5,d0		; d0 = ASCII character code
	move.w	prntcol,106(a0)	; TEXTFG(106): set foreground color
	; Set up font data pointer and form width
	move.l	76(a2),a5	; a5 = font bitmap data base
	move.l	a5,84(a0)	; FBASE(84): font data pointer
	move.w	80(a2),a5	; a5 = font form width
	move.w	a5,88(a0)	; FWIDTH(88): font form width in bytes
	; Calculate character bitmap X offset from offset table
	sub.w	36(a2),d0	; d0 = char - first_char (index into offset table)
	move.l	72(a2),a1	; a1 = character offset table (word entries)
	lsl.w	#1,d0		; d0 * 2 = byte offset into word table
	move.w	0(a1,d0),a5	; a5 = X offset of this character's bitmap
	move.w	a5,72(a0)	; SRCX(72): source X offset in font bitmap
	clr.w	74(a0)		; SRCY(74): source Y = 0
	move.w	d6,76(a0)	; DSTX(76): destination X position
	move.w	d7,78(a0)	; DSTY(78): destination Y position
	; Calculate character width from offset table
	addq.w	#2,d0		; next character's offset
	move.w	0(a1,d0),d0	; d0 = next char's X offset
	sub.w	72(a0),d0	; d0 = width (next_offset - this_offset)
	move.w	d0,80(a0)	; DELX(80): character width
	move.w	82(a2),a5	; a5 = character height from font header
	move.w	a5,82(a0)	; DELY(82): character height
	move.w	#$8000,64(a0)	; XDDA(64): text style = normal ($8000)
	;
	dc.w	$a008		; Line-A opcode: text blit (render character)
	movem.l	saver,d0-a6
	rts

;----------------------------------------------------------------------------
; init_pr - Initialize Line-A graphics engine
;
; Calls Line-A init ($A000) to get pointers to the variable base and
; font headers. Sets up text rendering parameters:
;   - Overwrite mode, no scaling, no rotation, no proportional
;   - Uses font #1 (8x8 system font)
;   - Background color = 0 (transparent)
;
; $A000 returns: a0 = variable base, a1 = font header table, a2 = (unused)
;----------------------------------------------------------------------------
init_pr:
	dc.w	$a000			; A_init: Line-A init - returns a0=varbase, a1=fonts
	move.l	a0,linetab		; save variable base (also used by fill_rec)
	move.w	#1,d1			; font index 1 (8x8 system font)
	lsl.w	#2,d1			; d1 * 4 = longword offset
	move.l	0(a1,d1),fonthead	; save font header address
	move.l	a0,varhead		; save variable base address
	; Configure Line-A text rendering using official variable offsets
	move.w	#1,36(a0)		; WMODE(36): write mode = 1 (replace)
	move.w	#0,114(a0)		; TEXTBG(114): background color = 0
	move.w	#0,102(a0)		; SCALE(102): scaling = 0 (disabled)
	move.w	#%00000000,90(a0)	; STYLE(90): text effects = none
	clr.w	98(a0)			; ROFF(98): right offset = 0
	clr.w	100(a0)			; LOFF(100): left offset = 0
	clr.w	104(a0)			; CHUP(104): character rotation = 0
	move.w	#1,70(a0)		; MONO(70): monospaced = 1 (fixed-width)
	clr.w	54(a0)			; CLIP(54): clipping = 0 (disabled)
	move.l	#bitscene,108(a0)	; SCRTCHP(108): scratch buffer pointer
	move.w	#$40,112(a0)		; SCRPT2(112): scratch buffer offset
	rts

;============================================================================
; HIGH SCORE PROCESSING
;============================================================================

;----------------------------------------------------------------------------
; calc_hi - Check if any player's score qualifies for the high score list
;
; Processes all players' scores in descending order (highest first).
; For each player, calls tstscore to check against the leaderboard.
; Only processes 1-lap games (multi-lap games don't record high scores).
;
; Uses a sort-flag (sortfl) to track which players have been processed,
; ensuring each player is checked exactly once in score-descending order.
;----------------------------------------------------------------------------
calc_hi:
	bsr	prepdigi		; start digital music for high score screen
	move.w	#3,d7			; 4 passes (for up to 4 players)
	clr.b	sortfl			; clear "already processed" flags
calcloop:
	clr.l	work2
	clr.b	work3
	clr.l	d0
	move.w	plscore,d0
	cmp.l	work2,d0
	blt	calc2
	btst	#0,sortfl
	bne	calc2
	move.l	d0,work2
	move.b	#"1",work3
	move.b	#%1,sortfl2
calc2:
	move.w	plscore+2,d0
	cmp.l	work2,d0
	blt	calc3
	btst	#1,sortfl
	bne	calc3
	move.l	d0,work2
	move.b	#"2",work3
	move.b	#%10,sortfl2
calc3:
	move.w	plscore+4,d0
	cmp.l	work2,d0
	blt	calc4
	btst	#2,sortfl
	bne	calc4
	move.l	d0,work2
	move.b	#"3",work3
	move.b	#%100,sortfl2
calc4:
	move.w	plscore+6,d0
	cmp.l	work2,d0
	blt	calc5
	btst	#3,sortfl
	bne	calc5
	move.l	d0,work2
	move.b	#"4",work3
	move.b	#%1000,sortfl2
calc5:
	move.b	sortfl2,d0
	or.b	d0,sortfl
	move.l	work2,d0
	move.b	work3,d1
	movem.l	d0-a6,-(sp)
	bsr	tstscore		; schauen ob in	rank
	movem.l	(sp)+,d0-a6
	dbf	d7,calcloop
	rts


;----------------------------------------------------------------------------
; tstscore - Check if a player's score ranks in the top 6
;
; Compares the BCD score in d0 against all 6 entries in the hiscore list.
; If the score is higher than any entry, jumps to getscore to record it.
; Only checks if nrlaps == 1 (single lap games only).
;
; Parameters:
;   d0 = player's score (BCD word)
;   d1 = player number character ('1'-'4')
;
; The hiscore data is a formatted ASCII string. hitab provides byte offsets
; to each rank's name field. Score digits are at name_offset + 18..21.
;----------------------------------------------------------------------------
tstscore:
	lea	hiscore,a0
	lea	hitab,a1
	move.w	nrplayer,d2
	add.b	#"0",d2
	cmp.b	d1,d2		; nur soviele player abfragen wie dabei
	blt	notlaps
	clr.w	d2
	cmp.w	#1,nrlaps	; nur bei 1 runde!
	bne	notlaps
tstsc1:
	move.w	d2,d4
	lsl.w	#1,d4
	move.w	0(a1,d4),d3	; 1. platz/name
	add.w	#18,d3		; an score
	clr.w	d4
	move.b	0(a0,d3),d5	; score
	and.b	#$0f,d5
	or.b	d5,d4
	lsl.l	#4,d4
	move.b	1(a0,d3),d5	; score
	and.b	#$0f,d5
	or.b	d5,d4
	lsl.l	#4,d4
	move.b	2(a0,d3),d5	; score
	and.b	#$0f,d5
	or.b	d5,d4
	lsl.l	#4,d4
	move.b	3(a0,d3),d5	; score
	and.b	#$0f,d5
	or.b	d5,d4
	cmp.w	d4,d0		; scores vergleichen
	bhi	getscore	; ok->gr�sser
	addq.w	#1,d2
	cmp.w	#6,d2		; schon	alle scores durch?
	blt	tstsc1
notlaps:
	rts
getscore:
	move.w	d2,work1	; rank des spielers
	move.l	screen,a2
	move.w	#7999,d5
gets1:	clr.l	(a2)+		; bildschirm l�schen
	dbf	d5,gets1
	;
	move.w	#$2700,sr
	move.l	$70,-(sp)	; zwischenspeicher
	clr.w	vbllcnt
	clr.w	vbllcnt1
	move.l	#lapvbl,$70	 ; raster wackeln
	move.w	#$2300,sr
	;
	movem.l	d0-a6,-(sp)
	move.b	d2,hirank
	add.b	#"1",hirank
	move.b	d1,hiplayer	; nummer des spielers
	pea	hitxt1
	bsr	palprint
	addq.l	#4,sp
	bsr	getname
	movem.l	(sp)+,d0-a6
	; einf�gen
	lea	hitab,a0
	lea	hiscore,a1
	moveq.l	#4,d7		; zeiger auf vorletzten	eintrage
tsts7:
	move.w	d7,d4
	lsl.w	#1,d4
	addq.w	#1,d2
	cmp.w	#6,d2
	bge	tsts2
	move.w	0(a0,d4),d6	; startadr. text
	move.w	d7,d5
	lsl.w	#1,d5
	move.w	2(a0,d5),d5	; startadr. next rank
	move.w	d0,-(sp)
	move.w	#22,d0		; 23 zeichen �bertragen
	move.w	d6,d4
tstl1:
	move.b	0(a1,d4),0(a1,d5)
	addq.w	#1,d4
	addq.w	#1,d5
	dbf	d0,tstl1
	move.w	(sp)+,d0
	subq.w	#1,d7
	bra	tsts7
tsts2:	; eintragen
	move.w	d6,-(sp)		; d6 als zeiger	merken
	lea	input2,a2
tsts3:
	move.b	(a2)+,0(a1,d6)
	addq.w	#1,d6
	tst.b	(a2)
	bne	tsts3
tsts4:	; auff�llen mit	punkten
	cmp.b	#'.',0(a1,d6)
	beq	tsts5
	move.b	#' ',0(a1,d6)
	addq.w	#1,d6
	bra	tsts4
tsts5:
	clr.l	d6
	move.w	(sp)+,d6
	add.w	#18,d6			; auf score postieren
	add.l	d6,a1
	move.w	d0,d1
	lsr.w	#6,d1
	lsr.w	#6,d1
	and.l	#$f,d1
	or.w	#$30,d1
	move.b	d1,(a1)+		; 1. stelle
	move.w	d0,d1
	lsr.w	#8,d1
	and.l	#$f,d1
	or.w	#$30,d1
	move.b	d1,(a1)+		; 2. stelle
	move.w	d0,d1
	lsr.w	#4,d1
	and.l	#$f,d1
	or.w	#$30,d1
	move.b	d1,(a1)+		; 3.stelle
	move.w	d0,d1
	and.l	#$f,d1
	or.w	#$30,d1
	move.b	d1,(a1)			; 4.stelle
	; und sichern
	lea	hiend,a4		; sichern
	sub.l	#hiscr,a4		; l�nge
	lea	input,a5
	lea	hiscore,a6
	bsr	save
	; flackern abschalten
	move.w	#$2700,sr
	move.l	(sp)+,$70
	move.w	#$2300,sr
	;
	move.w	work1,d2
	tst.w	d2
	bne	nobest
	; championbild nachladen
	move.l	screen,a6
	sub.l	#$22,a6
	lea	champn,a5
	lea	$22,a4
	bsr	load		; hiscorebild laden
	addq.l	#2,a6
	move.l	a6,-(sp)
	move.w	#6,-(sp)
	trap	#$e		; palette des titelbildes anzeigen
	addq.l	#6,sp
	move.l	screen,a6
	sub.l	#$22,a6
	lea	champn,a5
	lea	$fffff,a4
	bsr	load		; hiscorebild laden
	move.l	#$100000,d0
best:
	subq.l	#1,d0
	bne	best
nobest:
	rts


;----------------------------------------------------------------------------
; getname - Read player name for high score entry (up to 16 characters)
;
; Displays a cursor and reads keyboard input. Same logic as getinput
; but uses input2 buffer and allows 16 characters instead of 12.
;----------------------------------------------------------------------------
getname:
	lea	placetxt,a0	; position cursor for name entry
	bsr	print
	lea	curson,a0	; VT52: show cursor
	bsr	print
	lea	input2,a6	; a6 = write pointer into name buffer
	clr.b	(a6)		; clear buffer
getn2:
	move.w	#7,-(sp)	; GEMDOS Crawcin - blocking key read
	trap	#1
	addq.l	#2,sp
	cmp.b	#13,d0		; Return key?
	beq	getn1		; finish input
	cmp.b	#8,d0		; Backspace?
	bne	getn3
	cmp.l	#input2,a6	; at beginning of buffer?
	beq	getn2		; yes -> ignore backspace
	subq.l	#1,a6		; move back one character
	clr.b	(a6)		; null-terminate
	lea	crsleft,a0	; VT52: erase character
	bsr	print
	bra	getn2
getn3:
	cmp.l	#input2+16,a6	; buffer full? (max 16 chars for names)
	bge	getn2
	cmp.b	#' ',d0		; printable?
	blt	getn2
	cmp.b	#'z',d0
	bhi	getn2
	move.b	d0,(a6)+	; store character
	clr.b	(a6)		; null-terminate
	lea	-1(a6),a0	; echo character to screen
	bsr	print
	bra	getn2
getn1:
	lea	cursoff,a0	; VT52: hide cursor
	bra	print		; tail-call print and return

;----------------------------------------------------------------------------
; show_hi - Display high score table with background image and music
;
; Loads hiscore.pi1, sets its palette, loads the full image, then
; overlays the hiscore text using hiprint. Waits for fire button.
;----------------------------------------------------------------------------
show_hi:
	; Load hiscore picture palette first
	move.l	screen,a6
	sub.l	#$22,a6		; offset for PI1 header
	lea	hiscoren,a5	; filename: "hiscore.pi1"
	lea	$22,a4		; read only 34 bytes (header)
	bsr	load
	addq.l	#2,a6		; skip resolution word -> palette
	move.l	a6,-(sp)
	move.w	#6,-(sp)	; XBIOS Setpalette ($06)
	trap	#$e
	addq.l	#6,sp
	; Now load full image
	move.l	screen,a6
	sub.l	#$22,a6
	lea	hiscoren,a5
	lea	$fffff,a4	; read entire file
	bsr	load
	; Display high score text over the image
	pea	hiscore		; hiscore text buffer (6 ranked entries)
	bsr	hiprint		; render text without palette changes
	addq.l	#4,sp
	; Wait for fire button to dismiss
waitjoy:
	btst	#7,joystat	; fire button pressed?
	beq	waitjoy		; no -> keep waiting
	bra	resettim	; stop music and return

;----------------------------------------------------------------------------
; decspeed - Decrease speed (called when braking or hitting road edge)
;
; Decreases RPM (rounds), increases getfak (slower), and decreases
; speedfak (less track advancement). Updates motor sound and speedometer.
;----------------------------------------------------------------------------
decspeed:
	tst.w	rounds		; any RPM left?
	beq	decs1		; no RPM -> just decrease speedfak
	move.w	randtab2,d0
	cmp.w	getfak,d0	; already at standstill?
	beq	decs2		; yes -> only decrease speedfak
	subq.w	#1,rounds	; decrease RPM
	addq.w	#1,getfak	; increase speed factor (= slower)
	move.w	getfak,speed	; reset speed counter
	bsr	setmotor	; update engine sound
	bsr	speedo		; update speedometer display
decs2:
	tst.w	speedfak	; any movement speed left?
	beq	decs1		; no -> done
	subq.w	#1,speedfak	; decrease movement speed
decs1:
	rts


;============================================================================
; DATA SECTION - Initialized data (strings, tables, palettes, sound data)
;============================================================================
.data

; --- Text strings for high score name entry ---
placetxt:
	.dc.b	$1b,"Y",$20+16,$20+12,0
.even

hitxt1:
	.dc.b	13,13,13,13
	.dc.b	"!              Player "
hiplayer: .dc.b	" ,",13,13
	.dc.b	"      Please enter your name for",13,13
	.dc.b	"            the ",$22
hirank:	.dc.b	"0.! rank.",0
.even

input:
	.dc.b	"default",0,0,0,0,0,0
.even
input2:	.ds.b	20
.even

; --- Default high score data ---
; hiscr = template for saving new tracks (fresh scores)
; hiscore = working copy (modified during gameplay)
; Format: ASCII text with CR line separators, 6 entries of:
;   "    Nth...Name_padded_with_dots..XXXX" (4-digit ASCII score at offset +18)
; hitab gives byte offsets to each rank's name start within the string.
hiscr:
	.dc.b	13,13,13,13,13,13,13
	.dc.b	"    1st...Martin Backschat..0000",13,13
	.dc.b	"    2nd...(c) 1987 by     ..0000",13
	.dc.b	"    3rd...Prism PLC       ..0000",13
	.dc.b	"    4th...Conversion by   ..0000",13
	.dc.b	"    5th...Capital Software..0000",13
	.dc.b	"    6th...Developments Ltd..0000",0
hiend:	; marks end of hiscore data (hiend - hiscr = data length)
hiscore:	; working copy of high scores (loaded from .TOP file)
	.dc.b	13,13,13,13,13,13,13
	.dc.b	"    1st...Martin Backschat..0000",13,13
	.dc.b	"    2nd...(c) 1987 by     ..0000",13
	.dc.b	"    3rd...Prism PLC       ..0000",13
	.dc.b	"    4th...Conversion by   ..0000",13
	.dc.b	"    5th...Capital Software..0000",13
	.dc.b	"    6th...Developments Ltd..0000",0

hitab:	; byte offsets to each rank's name within hiscore string
	.dc.w	17,51,84,117,150,183

clrcolor:	; all-black palette (16 zeros) used during init
	.dc.w	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; --- Editor command button coordinate table ---
; Each entry: min_x, min_y, max_x, max_y, handler_address
; Buttons are 48 pixels wide in the top 12 pixels of the screen
koordtab:
	.dc.w	0,0,	48,12
	.dc.l	com_load
	.dc.w	48,0,	48*2,12
	.dc.l	com_save
	.dc.w	48*2,0,	48*3,12
	.dc.l	com_clr
	.dc.w	48*3,0,	48*4,12
	.dc.l	com_scen
	.dc.w	48*4,0,	48*5,12
	.dc.l	com_play
	.dc.w	48*5,0,	48*6,12
	.dc.l	com_quit
	.dc.w	-1

; --- IKBD command strings ---
mauscurs:	; IKBD: set mouse to cursor key emulation ($0a, threshold_x, threshold_y)
	.dc.b	$a,25,25
.even
mauson:		; IKBD: enable relative mouse mode ($08)
	.dc.b	8
.even

; --- Filenames for resource loading ---
picname:
	.dc.b	"trcs.pi1",0
.even
cockpitn:
	.dc.b	"dashbord.pi1",0
.even
signn1:
	.dc.b	"signs.pi1",0
.even
signn2:
	.dc.b	"signs2.pi1",0
.even
explname:
	.dc.b	"expl.snd",0
.even
filmname:
	.dc.b	"film.pi1",0
.even
diginame:
	.dc.b	"heavy.seq",0
.even
titlen:
	.dc.b	"title.pi1",0
.even
hiscoren:
	.dc.b	"hiscore.pi1",0
.even
champn:
	.dc.b	"champion.pi1",0
.even

; --- AES/VDI parameter blocks ---
; These are arrays of pointers to the various input/output arrays
aespb:	; AES parameter block: contrl, global, intin, intout, addrin, addrout
	.dc.l	contrl,global,intin,intout,addrin,addrout
vdipb:	; VDI parameter block: contrl, intin, ptsin, intout, ptsout
	.dc.l	contrl,intin,ptsin,intout,ptsout
.even
patptr:	; fill pattern for fill_rec (solid: all 1s)
	.dc.w	$ffff
.even

scentxtp:
	.dc.l	scen1txt,scen2txt,scen3txt
scentxt:
	.dc.b	$1b,"Y",$20+9,$20+7, "                           "
	.dc.b	$1b,"Y",$20+10,$20+7,"     Select Scenery:       "
	.dc.b	$1b,"Y",$20+11,$20+7,"                           "
	.dc.b	$1b,"Y",$20+15,$20+7,"                           ",0
.even
scen1txt:
.dc.b	$1b,"Y",$20+12,$20+7,$1b,"p","  ---  Rising Sun/City --- ",$1b,"q"
	.dc.b	$1b,"Y",$20+13,$20+7,"  ---  High Noon/City  --- "
	.dc.b	$1b,"Y",$20+14,$20+7,"  ---  Alps/Village    --- ",0
.even
scen2txt:
	.dc.b	$1b,"Y",$20+12,$20+7,"  ---  Rising Sun/City --- "
.dc.b	$1b,"Y",$20+13,$20+7,$1b,"p","  ---  High Noon/City  --- ",$1b,"q"
	.dc.b	$1b,"Y",$20+14,$20+7,"  ---  Alps/Village    --- ",0
.even
scen3txt:
	.dc.b	$1b,"Y",$20+12,$20+7,"  ---  Rising Sun/City --- "
	.dc.b	$1b,"Y",$20+13,$20+7,"  ---  High Noon/City  --- "
.dc.b	$1b,"Y",$20+14,$20+7,$1b,"p","  ---  Alps/Village    --- ",$1b,"q",0
.even

askltxt:
	.dc.b	13,13,13,13,13,13,13,13
	.dc.b	"       Select Number of Laps",0
.even
askltxt1:
	.dc.b	13,13,13,13,13,13,13,13,13,13
	.dc.b	"                 ",$22
asciilap:.dc.b	 "3",0
.even

askptxt:
	.dc.b	13,13,13,13,13,13,13,13
	.dc.b	"     Select Number of Players",0
.even
askptxt1:
	.dc.b	13,13,13,13,13,13,13,13,13,13
	.dc.b	"                 ",$22
asciplay:.dc.b	 "3",0
.even

gameover:
	.dc.b	13,13,13,13,13,13,13,"            !GAME OVER",13,13,13
	.dc.b	$22,"             PLAYER "
aktplay:.dc.b	"1",0
.even

clr_txt:
	.dc.b	$1b,"Y",$20+11,$20+7,"                           "
	.dc.b	$1b,"Y",$20+12,$20+7,"                           "
	.dc.b	$1b,"Y",$20+13,$20+7,"                           ",0
.even
disk_txt:
	.dc.b	$1b,"Y",$20+24,$20+7," Enter name: ",0
.even
err_txt:
	.dc.b	$1b,"Y",$20+12,$20+7," Disk Error! Press Key!",0
.even
curson:
	.dc.b	$1b,"e",0
.even
cursoff:
	.dc.b	$1b,"f",0
.even
crsleft:
	.dc.b	$1b,"D"," ",$1b,"D",0
.even
;============================================================================
; TRACK COMPONENT DEFINITIONS
;
; playtab: array of 18 longword pointers to component definitions (bau1-bau18)
;
; Each bauN definition has:
;   Word 0: exit direction 1 (primary)     \
;   Word 1: entry direction                 |  Direction codes use compass:
;   Word 2: exit direction 2 (alternate)   /
;   Bytes:  curve sequence data, terminated by $80
;
;                5  1  6
; Direction       \ | /       1=N, 2=E, 3=S, 4=W
; compass:     4-- *** --2    5=NW, 6=NE, 7=SE, 8=SW
;                 / | \
;                8  3  7
;
; offs[]: maps direction code to grid index offset (18-column grid)
;   0=stay, 1=N(-18), 2=E(+1), 3=S(+18), 4=W(-1), 5=NW(-19), 6=NE(-17), 7=SE(+19), 8=SW(+17)
;
; Curve values: 0=straight, +1/+2=right curve, -1/-2=left curve
;============================================================================
playtab:
	.dc.l	bau1,bau2,bau3,bau4,bau5,bau6,bau7,bau8,bau9
	.dc.l	bau10,bau11,bau12,bau13,bau14,bau15,bau16,bau17,bau18

	;	      5	 1  6
	;	       \ | /		direction compass for entry/exit
	;	    4--	*** --2
	;	       / | \
	;	      8	 3  7

offs:	; grid offsets for each direction (9 entries, direction 0-8)
	;     0	  1    2   3  4	 5   6	 7   8
	.dc.w 0, -18, 1, 18,-1,-19,-17,	19, 17

	; Each component: exit1_dir, entry_dir, exit2_dir, curve_bytes..., $80
bau1:	; gentle right curve (S->W exit, E->W alt)
	.dc.w	3,4,	2
	.dc.b	0,-2 ,-2 ,0,$80
.even
bau2:
	.dc.w	3,2,	4
	.dc.b	0, 2  ,2 ,0,$80
.even
bau3:
	.dc.w	8,4,	2
	.dc.b	0,-1 ,-1 ,-1 ,0,$80
.even
bau4:
	.dc.w	7,2,	4
	.dc.b	0, 1  ,1  ,1 ,0, $80
.even
bau5:
	.dc.w	3,8,	6
	.dc.b	0, -1 ,-1 ,-1 ,0,  $80
.even
bau6:
	.dc.w	5,1,	3
	.dc.b	0,-1 ,-1 ,-1 ,0,  $80
.even
bau7:
	.dc.w	5,5,	7
	.dc.b	0  ,0  ,0  ,0  ,0  ,$80
.even
bau8:
	.dc.w	8,8,	6
	.dc.b	0  ,0  ,0  ,0  ,0  ,$80
.even
bau9:
	.dc.w	4,4,	2
	.dc.b	0  ,0  ,0  ,0  ,0  ,$80
.even
bau10:
	.dc.w	1,4,	2
	.dc.b	0, 2  ,2 ,0, $80
.even
bau11:
	.dc.w	4,3,	1
	.dc.b	0, 2  ,2  ,0, $80
.even
bau12:
	.dc.w	5,4,	2
	.dc.b	0, 1  ,1  ,1 ,0, $80
.even
bau13:
	.dc.w	4,8,	6
	.dc.b	0, 1  ,1  ,1  ,0, $80
.even
bau14:
	.dc.w	1,5,	7
	.dc.b	0, 1  ,1  ,1  ,0, $80
.even
bau15:
	.dc.w	8,3,	1
	.dc.b	0, 1  ,1  ,1  ,0, $80
.even
bau16:
	.dc.w	4,4,	2
	.dc.b	0  ,0  ,0  ,0  ,0  ,$80
.even
bau17:
	.dc.w	1,1,	3
	.dc.b	0  ,0  ,0  ,0  ,0  ,$80
.even
bau18:
	.dc.w	1,1,	3
	.dc.b	0  ,0  ,0  ,0  ,0  ,$80
.even

;============================================================================
; RENDERING AND PHYSICS LOOKUP TABLES
;============================================================================

; fakttab - Line repetition table for perspective road rendering (70 entries)
; Each value = number of additional scanlines for that track segment.
; Bottom of screen (index 0): 8 extra lines = thick (close to camera)
; Top of screen (index 49+): 0 extra lines = thin (far away at horizon)
; This creates the pseudo-3D perspective foreshortening effect.
fakttab:
	.dc.w	8,6,4,3,2,2,1,1,1,1
	.dc.w	1,1,0,0,0,0,0,0,0,0
	.dc.w	0,0,0,0,0,0,0,0,0,0
	.dc.w	0,0,0,0,0,0,0,0,0,0
	.dc.w	0,0,0,0,0,0,0,0,0,0

; randtab - Edge color band duration table (100+ entries)
; Controls how many scanlines each colored stripe persists before toggling.
; Values decrease from 15 (bottom/close) to 0 (top/far), creating the
; illusion of alternating stripes that move faster near the horizon.
; The first value (randtab[0]) also serves as the maximum speed value (randtab2).
randtab:
	.dc.b	15,15,15,15,14,14,14,14,13,13
	.dc.b	13,13,12,12,12,12,11,11,11,11
	.dc.b	10,10,10,10, 9,	9, 9, 9, 8, 8
	.dc.b	 7, 7, 7, 7, 6,	6, 6, 6, 5, 5
	.dc.b	 5, 5, 4, 4, 4,	4, 3, 3, 3, 3
	.dc.b	 2, 2, 2, 2, 1,	1, 1, 1, 0, 0
	.dc.b	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
.even

; --- IKBD joystick control commands ---
joyon:	; IKBD: $12=disable mouse, $14=enable joystick events
	.dc.b	$12,$14
.even
joyoff:	; IKBD: $15=disable joystick, $08=enable relative mouse
	.dc.b	$15,$08
.even

; --- Grass fill pattern ---
; 48 bytes = one scanline of grass (color 14 in all 4 bitplanes)
; In low-res 4-plane format: for color 14 (binary 1110):
;   plane 0 = $0000, plane 1 = $ffff, plane 2 = $ffff, plane 3 = $ffff
; Repeated 6 times to cover the full 160-byte movem.l register set
wiese:
	.dc.l	$0000ffff,$ffffffff	; 16 pixels
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff

; coltab - Color bitplane patterns for all 16 Atari ST low-res colors
; Each entry = 8 bytes (4 words): plane0, plane1, plane2, plane3
; Color N has bit pattern N in binary across the 4 planes.
; E.g., color 5 = 0101 binary: plane0=$ffff, plane1=$0000, plane2=$ffff, plane3=$0000
coltab:
	.dc.w	$0000,$0000,$0000,$0000
	.dc.w	$ffff,$0000,$0000,$0000
	.dc.w	$0000,$ffff,$0000,$0000
	.dc.w	$ffff,$ffff,$0000,$0000
	.dc.w	$0000,$0000,$ffff,$0000
	.dc.w	$ffff,$0000,$ffff,$0000
	.dc.w	$0000,$ffff,$ffff,$0000
	.dc.w	$ffff,$ffff,$ffff,$0000
	.dc.w	$0000,$0000,$0000,$ffff
	.dc.w	$ffff,$0000,$0000,$ffff
	.dc.w	$0000,$ffff,$0000,$ffff
	.dc.w	$ffff,$ffff,$0000,$ffff
	.dc.w	$0000,$0000,$ffff,$ffff
	.dc.w	$ffff,$0000,$ffff,$ffff
	.dc.w	$0000,$ffff,$ffff,$ffff
	.dc.w	$ffff,$ffff,$ffff,$ffff

; bittab - Left-edge bit masks for hline (16 entries)
; bittab[N] has bits N..15 set (1s from position N to the right edge)
; Used to mask the starting word when a line doesn't start at bit 0.
bittab:
	.dc.w	%1111111111111111
	.dc.w	%0111111111111111
	.dc.w	%0011111111111111
	.dc.w	%0001111111111111
	.dc.w	%0000111111111111
	.dc.w	%0000011111111111
	.dc.w	%0000001111111111
	.dc.w	%0000000111111111
	.dc.w	%0000000011111111
	.dc.w	%0000000001111111
	.dc.w	%0000000000111111
	.dc.w	%0000000000011111
	.dc.w	%0000000000001111
	.dc.w	%0000000000000111
	.dc.w	%0000000000000011
	.dc.w	%0000000000000001

; --- PSG sound initialization data ---
; initmtr - Motor sound initialization: sets channels A+B to mid-frequency,
;   mixer to enable tones on A+B, volumes to 12/12/15
initmtr:
	.dc.b	0,255,1,15,2,191,3,15,7,%011100,8,12,9,12,10,15
	.dc.b	-1,-1
.even

; gangsnd - Engine sound frequency tables for each gear
; 4 pointers to sub-tables (gang0-gang3). Each sub-table has 4 word entries
; for RPM levels 0-3. Values are PSG tone period (lower = higher pitch).
; gang3 has the highest frequencies (top gear), gang0 the lowest.
gangsnd:
	.dc.l	gang0,gang1,gang2,gang3
gang3:
	.dc.b	 8,128,	9,128,10,128,11,128
gang2:
	.dc.b	 9,128,10,128,11,128,12,128
gang1:
	.dc.b	10,128,11,128,12,128,13,128
gang0:
	.dc.b	11,128,12,128,13,128,14,128


; bittab2 - Right-overlap masks for sprite rendering (16 entries)
; bittab2[N] has bits 15..(16-N) set (1s from the LEFT edge, N bits wide)
; Used in set16spr/setsign to mask the overflow portion of shifted sprites.
; bittab2[0] = $0000 (no overflow), bittab2[15] = $fffe (almost full overlap)
bittab2:
	.dc.w	%0000000000000000
	.dc.w	%1000000000000000
	.dc.w	%1100000000000000
	.dc.w	%1110000000000000
	.dc.w	%1111000000000000
	.dc.w	%1111100000000000
	.dc.w	%1111110000000000
	.dc.w	%1111111000000000
	.dc.w	%1111111100000000
	.dc.w	%1111111110000000
	.dc.w	%1111111111000000
	.dc.w	%1111111111100000
	.dc.w	%1111111111110000
	.dc.w	%1111111111111000
	.dc.w	%1111111111111100
	.dc.w	%1111111111111110

; steertab - Steering wheel sprite offsets (9 entries for positions -4 to +4)
; Each longword is a byte offset from datascr1+6400 to the sprite data
; for that wheel position. The wheel is 64 pixels wide (4 columns of 16px).
steertab:
	.dc.l	6880+96,6880+64,6880+32,6880
	.dc.l	128,96,64,32,0

; --- Sign/billboard data tables ---
; signtab - Base addresses for 4 sign types (each is a 64-line tall sprite)
;   #0: Prism Leisure logo (in signscr1)
;   #1: ST advertisement (signscr1+10400)
;   #2: Capital Software (signscr2)
;   #3: GO! sign (signscr1+20800)
signtab:
	.dc.l	signscr1	; #0 prism leisure logo
	.dc.l	signscr1+10400	; #1 ST	ad
	.dc.l	signscr2	; #2 CAPITAL Software
	.dc.l	signscr1+20800	; #3 GO!

signoffs:	; offsets der schilder innerhalb der zeile (in bytes)
	.dc.l	152,144,136,128,  112,96,  64,32,0
signlen:
	.dc.w	16, 16,	16, 16,	  32, 32,  64,64,64

signrtab:
	.dc.b	0,0,0,0,0,1,1,1,1,1	; von hinten nach vorne
	.dc.b	1,1,1,2,2,2,2,2,3,3
	.dc.b	3,3,3,3,3,3,4,4,4,4
	.dc.b	4,4,4,4,4,5,5,5,5,5
	.dc.b	5,5,5,6,6,6,6,6,6,6
	.dc.b	7,7,7,7,7,7,7,7,8,8
	.dc.b	8,8,8,8,8,8,8,8,8,8
	.dc.b	8,8,8,8,8,8,8,8,8,8
	.dc.b	8,8,8,8,8,8,8,8,8,8
	.dc.b	8,8,8,8,8,8,8,8,8,8
	.dc.b	8,8,8,8,8,8,8,8,8,8

lrand:
	.dc.w	%0111111111111111
	.dc.w	%0011111111111111
	.dc.w	%0001111111111111
	.dc.w	%0000111111111111
	.dc.w	%0000011111111111
	.dc.w	%0000001111111111
	.dc.w	%0000000111111111
	.dc.w	%0000000011111111
	.dc.w	%0000000001111111
	.dc.w	%0000000000111111
	.dc.w	%0000000000011111
	.dc.w	%0000000000001111
	.dc.w	%0000000000000111
	.dc.w	%0000000000000011
	.dc.w	%0000000000000001
	.dc.w	%0000000000000000

rrand:
	.dc.w	%1111111111111110
	.dc.w	%1111111111111100
	.dc.w	%1111111111111000
	.dc.w	%1111111111110000
	.dc.w	%1111111111100000
	.dc.w	%1111111111000000
	.dc.w	%1111111110000000
	.dc.w	%1111111100000000
	.dc.w	%1111111000000000
	.dc.w	%1111110000000000
	.dc.w	%1111100000000000
	.dc.w	%1111000000000000
	.dc.w	%1110000000000000
	.dc.w	%1100000000000000
	.dc.w	%1000000000000000
	.dc.w	%0000000000000000

; --- Scenery palettes ---
; paladdr - Pointers to 3 scenery palettes (16 colors each)
; Each palette is 32 bytes (16 words, Atari ST RGB format: 0x0RGB, 3 bits per component)
paladdr:
	.dc.l	scen1pal,scen3pal,scen2pal

scen1pal:  ; palette der 1. scenerie
	.dc.w	$000,$761,$750,$740,$730,$720,$710,$610
	.dc.w	$500,$421,$200,$310,$420,$020,$373,$777
scen2pal:  ; palette der 2. scenerie
	.dc.w	$000,$235,$245,$467,$144,$567,$021,$030
	.dc.w	$250,$210,$320,$420,$540,$642,$764,$777
scen3pal:  ; palette der 3. scenerie
	.dc.w	$000,$136,$237,$320,$144,$300,$021,$030
	.dc.w	$250,$111,$222,$333,$444,$555,$666,$777

; bitoffs - Base addresses for 16 pre-shifted scenery bitmaps
; Each shifted copy is 5120 bytes (32 lines * 160 bytes/line).
; Copy 0 = original, copy 1 = shifted 1px right, ..., copy 15 = shifted 15px right.
; Used by VBL handler to select the correct sub-pixel-shifted scenery.
bitoffs:
	.dc.l	bitscene,bitscene+5120,bitscene+10240
	.dc.l	bitscene+15360,bitscene+20480,bitscene+25600
	.dc.l	bitscene+30720,bitscene+35840,bitscene+40960
	.dc.l	bitscene+46080,bitscene+51200,bitscene+56320
	.dc.l	bitscene+61440,bitscene+66560,bitscene+71680
	.dc.l	bitscene+76800

; scenaddr - Source addresses for 3 scenery bitmaps (within signscr2)
; These are the original unshifted scenery graphics that get copied
; and pre-shifted into bitscene during play initialization.
scenaddr:
	.dc.l	signscr2+16800,signscr2+26880,signscr2+21760

; rowtab - Road widening table (70 entries)
; Applied per scanline to make the road slightly wider toward the bottom.
; Values alternate between 2 and 3 pixels, with 3 appearing every 5th entry.
rowtab:
	.dc.w	2,2,2,2,2, 3,2,2,2,2
	.dc.w	2,2,2,2,2, 3,2,2,2,2
	.dc.w	2,2,2,2,2, 3,2,2,2,2
	.dc.w	2,2,2,2,2, 3,2,2,2,2
	.dc.w	2,2,2,2,2, 3,2,2,2,2
	.dc.w	2,2,2,2,2, 3,2,2,2,2
	.dc.w	2,2,2,2,2, 3,2,2,2,2

vbllpal:
	.dc.w	$057,$047,$037,$027,$017,$016,$005,$004
	.dc.w	$004,$005,$016,$017,$027,$037,$047,$057
vblppal:
	.dc.w	$075,$074,$074,$072,$071,$061,$050,$040
	.dc.w	$040,$050,$061,$071,$072,$073,$074,$075

; --- PSG initialization sequences (register/value pairs, terminated by -1) ---
; initsnd - Silence all channels: all frequencies to 0, mixer off, volumes 0
initsnd:
	.dc.b	0,0, 1,0, 2,0, 3,0, 4,0, 5,0, 6,0, 7,%111111
	.dc.b	8,0, 9,0,10,0,11,0,12,0,13,0,-1,-1
.even
; initdat - Max volume: all tone frequencies to max (255), noise off, mixer=$3f
initdat:    .dc.b	0,255,1,255,2,255,3,255,4,255,5,255,6,0,7,$3f
	    .dc.b	8,0,9,0,10,0,-1,0
.even
; randsnd - Road edge/scraping sound: channel C with noise, envelope modulation
randsnd:
	.dc.b	4,55,5,9,6,20,10,16,11,80,12,0,13,12,-1,-1
.even

; t1 - Explosion sound segment sequence (indexes into taktable, -1=loop)
	.dc.b	0,0,0,0,0,-1
.even
; t2 - Digital music segment sequence (indexes into taktabl2, -1=loop)
;   Sequences through different sections of the digisnd buffer
t2:
	.dc.b	0,0,0,0,0,0, 1,1, 2,2, 3,3, 4,4, 5,5, 4,4, 3,3
	.dc.b	2,2, 1,1, 0,0, 2,2, 3,3, 2,2, 3,3, 4,4,	5,5, 4,4
	.dc.b	5,5, 4,4, 3,3, 2,2, 1,1, -1,0
.even
; taktable - Explosion sound segment boundaries (pairs of: start_offset, end_offset)
; Offsets are relative to explsnd buffer base.
taktable:
	.dc.l	1,$16f5,0,0

; taktabl2 - Digital music segment boundaries (pairs of start, end offsets)
; Offsets relative to digisnd buffer. Multiple segments cover the 78KB music file.
taktabl2:
	.dc.l	4,3460,16280,31510,46595,61730,76870

prpal:		.dc.w $000,$445,$334,$223,$112,$666,$666,$666
		.dc.w $666,$444,$333,$222,$111,$666,$666,$666

nrlaps:
	.dc.w	1	; normal 1 laps
nrplayer:
	.dc.w	1

; loudtab - Digital music PSG register value table (64 entries, 12 bytes each)
; Each entry is 3 longwords written directly to $ff8800 via movem.l.
; Format: reg8/vol_A, reg9/vol_B, reg10/vol_C (PSG register + volume data)
; The sample bytes from digisnd index into this table after masking to $fc
; and multiplying by 3, giving 64 possible volume/tone combinations.
loudtab:
   .dc.l  $8000000,$9000000,$a000000
   .dc.l  $8000000,$9000000,$a000200
   .dc.l  $8000000,$9000000,$a000300
   .dc.l  $8000200,$9000200,$a000200
   .dc.l  $8000500,$9000000,$a000000
   .dc.l  $8000500,$9000200,$a000000
   .dc.l  $8000600,$9000100,$a000000
   .dc.l  $8000600,$9000200,$a000100
   .dc.l  $8000700,$9000100,$a000000
   .dc.l  $8000700,$9000200,$a000000
   .dc.l  $8000700,$9000300,$a000100
   .dc.l  $8000800,$9000000,$a000000
    dc.l  $8000800,$9000200,$a000000
    dc.l  $8000800,$9000300,$a000100
    dc.l  $8000800,$9000400,$a000100
    dc.l  $8000900,$9000000,$a000000

    dc.l  $8000900,$9000200,$a000000
    dc.l  $8000900,$9000300,$a000100
    dc.l  $8000900,$9000400,$a000100
    dc.l  $8000900,$9000500,$a000000
    dc.l  $8000900,$9000500,$a000200
    dc.l  $8000900,$9000600,$a000000
    dc.l  $8000900,$9000600,$a000200
    dc.l  $8000a00,$9000200,$a000000
    dc.l  $8000a00,$9000200,$a000200
    dc.l  $8000a00,$9000400,$a000100
    dc.l  $8000a00,$9000500,$a000000
    dc.l  $8000a00,$9000500,$a000200
    dc.l  $8000a00,$9000600,$a000100
    dc.l  $8000a00,$9000600,$a000300
    dc.l  $8000b00,$9000100,$a000000
    dc.l  $8000b00,$9000200,$a000100

    dc.l  $8000b00,$9000300,$a000100
    dc.l  $8000b00,$9000400,$a000100
    dc.l  $8000b00,$9000500,$a000100
    dc.l  $8000b00,$9000600,$a000000
    dc.l  $8000b00,$9000600,$a000200
    dc.l  $8000b00,$9000700,$a000000
    dc.l  $8000b00,$9000700,$a000100
    dc.l  $8000b00,$9000700,$a000300
    dc.l  $8000b00,$9000700,$a000400
    dc.l  $8000b00,$9000800,$a000100
    dc.l  $8000b00,$9000800,$a000300
    dc.l  $8000b00,$9000800,$a000400
    dc.l  $8000b00,$9000800,$a000500
    dc.l  $8000b00,$9000800,$a000500
    dc.l  $8000c00,$9000200,$a000000
    dc.l  $8000c00,$9000200,$a000200

    dc.l  $8000c00,$9000400,$a000100
    dc.l  $8000c00,$9000500,$a000000
    dc.l  $8000c00,$9000500,$a000300
    dc.l  $8000c00,$9000600,$a000000
    dc.l  $8000c00,$9000600,$a000200
    dc.l  $8000c00,$9000700,$a000000
    dc.l  $8000c00,$9000700,$a000300
    dc.l  $8000c00,$9000700,$a000400
    dc.l  $8000c00,$9000800,$a000000
    dc.l  $8000c00,$9000800,$a000300
    dc.l  $8000c00,$9000800,$a000400
    dc.l  $8000c00,$9000800,$a000500
    dc.l  $8000c00,$9000900,$a000000
    dc.l  $8000c00,$9000900,$a000300
    dc.l  $8000c00,$9000900,$a000400
    dc.l  $8000c00,$9000900,$a000500
    dc.l  $8000c00,$9000900,$a000500

filemask:
	.dc.b	"*.*",0
.even

postxt:
	.dc.b	$1b,"Y",$20+0,$20+14,$1b,"b",14,0
.even
endpost:
	.dc.b	$1b,"b",15,0
.even

; faktab - Curve response factors when STEERING into a curve (16 entries)
; Lower values = tighter turning radius. Indexed by speed (0=fast, 15=slow).
; Used in curve physics: drift = 220_or_300 / faktab[speed]
; At high speed (index 0-3): values 7-11 -> aggressive drift
; At low speed (index 12-15): values 64-86 -> gentle drift
faktab:
	.dc.b	7 ,8 ,9	,11,13,18,24,30
	.dc.b	36,43,50,57,64,71,78,86
.even
; faktab2 - Curve drift factors when NOT steering (wider/more sliding)
; Same structure but ~2x the values of faktab -> less responsive, more drift
faktab2:
	.dc.b	14,16,18,22,26,36,48,60
	.dc.b	72,86,100,114,128,142,156,172
.even

;============================================================================
; BSS SECTION - Uninitialized data (runtime variables and buffers)
; All storage here is zeroed at program start by TOS.
; Total BSS: ~371 KB (dominated by graphics buffers)
;============================================================================
.bss
.even

; --- AES/VDI communication arrays ---
; These arrays are shared between the application and GEM for parameter passing.
contrl:	; VDI/AES control array (function code, param counts)
	opcode:		.ds.w	1
	sintin:		.ds.w	1
	sintout:	.ds.w	1
	saddrin:	.ds.w	1
	saddrout:	.ds.w	1
			.ds.w	6

global:
	apvers:		.ds.w	1
	apcount:	.ds.w	1
	apid:		.ds.w	1
	appriv:		.ds.w	1
	apptree:	.ds.w	1
	ap1resv:	.ds.w	1
	ap2resv:	.ds.w	1
	ap3resv:	.ds.w	1
	ap4resv:	.ds.w	1

intin:
	.ds.w	128

ptsin:
	.ds.w	256

intout:
	.ds.w	128

ptsout:
	.ds.w	12

addrin:
	.ds.w	128

addrout:
	.ds.w	128

; === GAME STATE VARIABLES ===
; --- Road rendering state ---
startcol:	; current starting edge color (12 or 13)
	.ds.w	1
randcol:
	.ds.w	1
randcnt:
	.ds.w	1
randcnt2:
	.ds.w	1

keystat:
	.ds.w	1
mausstat:
	.ds.w	1
mausx:
	.ds.w	1
mausy:
	.ds.w	1
screen:		; primary screen buffer address (set by XBIOS Logbase)
	.ds.l	1
rez:		; original screen resolution (saved for quit)
	.ds.w	1
pic:		; working picture buffer for editor (PI1 format: 2+32+32000 bytes)
	.ds.b	32066
mouseblk:
	.ds.w	5+32
linetab:
	.ds.l	1
saver:
	.ds.l	16

x1:	.ds.w	1
y1:	.ds.w	1
x2:	.ds.w	1
y2:	.ds.w	1
col:	.dc.w	1

handle:
	.ds.w	1
; --- Track editor state ---
playdat:	; track grid data: 18 columns x 9 rows = 162 bytes + padding
	.ds.b	200
.even

randtab2:
	.ds.w	1
aktbaut:
	.ds.w	1	; aktuelles bauteil
starter:
	.ds.w	1
olddir:
	.ds.w	1
savcolor:
	.ds.w	16
; --- Car physics state ---
joystat:	; joystick state byte (bit 0=up,1=down,2=left,3=right,7=fire)
	.ds.b	1
.even
speed:		; speed animation counter (counts down from getfak to 0, then advances track)
	.ds.w	1
getfak:		; speed factor: 0=fastest, randtab2=stopped (inverse of actual speed)
	.ds.w	1
xadd:		; horizontal offset from road center (positive=left, negative=right)
	.ds.w	1
speedfak:	; actual movement speed for track advancement (0=stopped, max=fastest)
	.ds.w	1
screen2:	; secondary screen buffer address (256-byte aligned)
	.ds.l	1
aktscr2:
	.ds.l	1
aktscr:
	.ds.l	1	; gerade aktuelle screen (screen o. screen2)
aktrow:
	.ds.w	1
playpal:
	.ds.w	20
score:
	.ds.w	1
scorecnt:
	.ds.w	1
sprwork1:
	.ds.b	160*10		; kleiner teil e. screens (10 zeilen)
.even
joydir:
	.ds.w	1
oldjdir:
	.ds.w	1
signinfo:
	.ds.w	1
signrow:
	.ds.w	1
signleft:
	.ds.w	1
signrigt:
	.ds.w	1
lastdat:
	.ds.w	1
signcnt:
	.ds.w	1
scroll:
	.ds.w	1
gang:
	.ds.w	1
rounds:
	.ds.w	1
takptr1:
	.ds.w	1
takt1:
	.ds.l	1
taktend1:
	.ds.l	1
tloop1:
	.ds.w	1
note1:
	.ds.w	1
timerirq:
	.ds.l	1
reg0b:
	.ds.w	1
reg0f:
	.ds.w	1
reg07:
	.ds.w	1
reg13:
	.ds.w	1
reg17:
	.ds.w	1
reg19:
	.ds.w	1
aktscene:
	.ds.w	1
reg79:
	.ds.w	1
vbllcnt:
	.ds.w	1
vbllcnt1:
	.ds.w	1
vblpcnt:
	.ds.w	1
vblpcnt1:
	.ds.w	1

prntpal:    .ds.w   1
varhead:.ds.l	1
fonthead:ds.l	1
prntcol:.ds.w	1

takptr2:
	.ds.w	1
takt2:
	.ds.l	1
taktend2:
	.ds.l	1
nrlaps1:
	.ds.w	1
nrplay1:
	.ds.w	1
cnt1:
	.ds.w	1
;
plscore:		; scores der spieler
	.ds.w	4
work1:
	.ds.w	1
work2:
	.ds.l	1
work3:
	.ds.w	1
sortfl:
	.ds.w	1
sortfl2:
	.ds.w	1
waitcnt:
	.ds.w	1
slowfak:
	.ds.w	1
scroll1:
	.ds.w	1
xadd2:
	.ds.w	1
dta:
	.ds.b	50

.ds.l	300
usersp:
.ds.l	10

; === LARGE GRAPHICS AND SOUND BUFFERS ===
scndscr:	; raw buffer for secondary screen (32000 + 256 alignment padding)
	.ds.b	32000+256	; extra 256 bytes: scanned to find 256-byte aligned addr
playseq:	; compressed track sequence from generate() (max 2000 bytes)
	.ds.b	2000
aktseq:		; decompressed active track data (6 bytes per segment)
	.ds.b	6*6*162	      ;	6*6*162 = 5832 bytes (generous allocation)
datascr1:	; dashboard sprites: digits, speed gauge, gear, steering wheel
	.ds.b	32000		; extracted from dashbord.pi1 during init
	.ds.b	$22		; palette header space (unused after extraction)
signscr1:	; billboard sprites set 1 (loaded from signs.pi1)
	.ds.b	32000
	.ds.b	$22		; palette header space
signscr2:	; billboard sprites set 2 + scenery bitmaps (from signs2.pi1)
	.ds.b	32000
filmpal:	; explosion animation palette (from film.pi1 header, 34 bytes)
	.ds.b	$22
film:		; explosion animation frame (from film.pi1 screen data)
	.ds.b	32000
bitscene:	; 16 pixel-shifted copies of scenery for smooth scrolling
	.ds.b	81920		; 16 * 5120 bytes (32 lines * 160 bytes * 16 shifts)
explsnd:	; explosion sound effect data (from expl.snd)
	.ds.b	$1700		; 5888 bytes
digisnd:	; digital music data (from heavy.seq, ~78KB)
	.ds.b	78000
