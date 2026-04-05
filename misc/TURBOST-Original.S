start:
	move.l	a7,a5		; retten des stackpt
	move.l	#usersp,a7
	move.l	4(a5),a5
	move.l	$c(a5),d0
	add.l	$14(a5),d0
	add.l	$1c(a5),d0
	add.l	#$100,d0
	move.l	d0,-(sp)
	move.l	a5,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)
	trap	#1
	add.l	#12,sp
	bsr	main
	clr.w	-(sp)
	trap	#1


aes:
	move.l	#aespb,d1
	move.w	#$c8,d0
	trap	#2
	rts

vdi:
	move.l	#vdipb,d1
	move.w	#$73,d0
	trap	#2
	rts


set16spr:      ; setzt 16xheigth in screen und screen2
		movem.l	d0-a6,saver	;save regs
		move.w	4(sp),d3	;x-position
		move.w	6(sp),d4	;y-postion
		move.w	8(sp),d6	; height in bit
		move.l	10(sp),a1	;sprite	data
		move.l	screen,a3
		move.l	screen2,a4
		;
		moveq.l	#0,d1
		move.w	d4,d1		;move.w	YPOS,d1
		asl.l	#1,d1		;YPOS*2
		move.l	d1,d2
		asl.l	#2,d1		;YPOS*8
		add.l	d2,d1		;YPOS*10
		asl.l	#4,d1		;YPOS*160
		;
		moveq.l	#0,d0
		move.w	d3,d0		;move.w	XPOS,d0
		move.l	d0,d2
		moveq.l	#16,d5
		and.l	#$f,d2		;pixels to shift
		sub.l	d2,d5
		and.l	#$fffffff0,d0
		lsr.l	#1,d0		;XPOS/2
		add.l	d1,d0		;offset
		add.l	#16,d0		; da in	zeile von hinten gest.
		add.l	d0,a3		;add offset to base screen address
		add.l	d0,a4
		;
		lea	bittab2,a2
		lsl.w	#1,d2
		move.w	0(a2,d2),d7
		move.w	d7,d4
		not.w	d4
		;
nextline:	moveq.l	#0,d0
		moveq.l	#0,d1
		moveq.l	#0,d2
		moveq.l	#0,d3
		move.w	(a1)+,d0	;bit plane 0
		move.w	(a1)+,d1	;bit plane 1
		move.w	(a1)+,d2	;bit plane 2
		move.w	(a1)+,d3	;bit plane 3
		add.l	#160-8,a1      ; next line
		;
		lsl.l	d5,d0		;shift all bit planes
		lsl.l	d5,d1
		lsl.l	d5,d2
		lsl.l	d5,d3
		;
		and.w	d4,-(a3)	;now map data onto the screen
		or.w	d3,(a3)
		and.w	d4,-(a4)
		or.w	d3,(a4)
		swap	d3
		and.w	d4,-(a3)
		or.w	d2,(a3)
		and.w	d4,-(a4)
		or.w	d2,(a4)
		swap	d2
		and.w	d4,-(a3)
		or.w	d1,(a3)
		and.w	d4,-(a4)
		or.w	d1,(a4)
		swap	d1
		and.w	d4,-(a3)
		or.w	d0,(a3)
		and.w	d4,-(a4)
		or.w	d0,(a4)
		swap	d0
		and.w	d7,-(a3)
		or.w	d3,(a3)
		and.w	d7,-(a3)
		or.w	d2,(a3)
		and.w	d7,-(a3)
		or.w	d1,(a3)
		and.w	d7,-(a3)
		or.w	d0,(a3)
		and.w	d7,-(a4)
		or.w	d3,(a4)
		and.w	d7,-(a4)
		or.w	d2,(a4)
		and.w	d7,-(a4)
		or.w	d1,(a4)
		and.w	d7,-(a4)
		or.w	d0,(a4)
		;
		lea.l	176(a3),a3	;set up	for next line
		lea.l	176(a4),a4
		dbf.w	d6,nextline
;
;now exit the plot routine
;
		movem.l	saver,d0-a6	;restore registers
		rts


setsign:       ; setzt 16xheigth in screen und screen2,	jedoch nur OR
	       ; speziell fÅr schilder,	da nur im akt. screen!
		movem.l	d0-a6,saver	;save regs
		move.w	4(sp),d3	;x-position
		move.w	6(sp),d4	;y-postion
		move.w	8(sp),d6	; height in bit
		move.l	10(sp),a1	;sprite	data
		move.l	$44e,a3
		; verhindern, dass Åbern rand gezeichnet wird
		moveq.l	#-1,d7
		move.w	d3,d0
		bpl	sok1
		neg.w	d0		; positiv machen
		cmp.w	#16,d0
		bhi	sexit		; nicht	mehr sichtabr -> exit
		subq.w	#1,d0
		move.w	#15,d3
		sub.w	d0,d3		; neue koordinate
		subq.l	#8,a3
		lea	lrand,a0
		lsl.w	#1,d0		; auf wort-tab erweitern
		move.w	0(a0,d0),d7
		bra	sok2
sok1:
		cmp.w	#320-15,d3
		ble	sok2
		sub.w	#320-15,d0
		cmp.w	#15,d0
		bhi	sexit
		lea	rrand,a0
		lsl.w	#1,d0
		move.w	0(a0,d0),d7
sok2:
		;
		move.l	a3,a4
		move.l	a3,a5
		add.l	#160*140,a4	; tiefste zeile, wo schilder sind
		add.l	#160*71,a5	; hîchste zeile	(darÅber nichts!)
		;
		moveq.l	#0,d1
		move.w	d4,d1		;move.w	YPOS,d1
		asl.l	#1,d1		;YPOS*2
		move.l	d1,d2
		asl.l	#2,d1		;YPOS*8
		add.l	d2,d1		;YPOS*10
		asl.l	#4,d1		;YPOS*160
		;
		moveq.l	#0,d0
		move.w	d3,d0		;move.w	XPOS,d0
		move.l	d0,d2
		moveq.l	#16,d5
		and.l	#$f,d2		;pixels to shift
		sub.l	d2,d5
		and.l	#$fffffff0,d0
		lsr.l	#1,d0		;XPOS/2
		add.l	d1,d0		;offset
		add.l	#16,d0		; da in	zeile von hinten gest.
		add.l	d0,a3		;add offset to base screen address
		;
nextlin1:
		cmp.l	a4,a3
		bhi	sexit
		; testen, ob zeile zu hoch
		cmp.l	a5,a3
		bge	itsok		; ja, dann zur nÑchsten	zeile
		add.l	#160,a1
		add.l	#160,a3
		dbf	d6,nextlin1
		bra	sexit
itsok:
		moveq.l	#0,d0
		moveq.l	#0,d1
		moveq.l	#0,d2
		moveq.l	#0,d3
		move.w	(a1)+,d0	;bit plane 0
		and.w	d7,d0
		move.w	(a1)+,d1	;bit plane 1
		and.w	d7,d1
		move.w	(a1)+,d2	;bit plane 2
		and.w	d7,d2
		move.w	(a1)+,d3	;bit plane 3
		and.w	d7,d3
		add.l	#160-8,a1      ; next line
		;
		lsl.l	d5,d0		;shift all bit planes
		lsl.l	d5,d1
		lsl.l	d5,d2
		lsl.l	d5,d3
		; maske	erzeugen
		move.l	d0,d4
		or.l	d1,d4
		or.l	d2,d4
		or.l	d3,d4
		not.l	d4
		;
		and.w	d4,-(a3)	;now map data onto the screen
		or.w	d3,(a3)
		swap	d3
		and.w	d4,-(a3)
		or.w	d2,(a3)
		swap	d2
		and.w	d4,-(a3)
		or.w	d1,(a3)
		swap	d1
		and.w	d4,-(a3)
		or.w	d0,(a3)
		swap	d0
		swap	d4
		and.w	d4,-(a3)
		or.w	d3,(a3)
		and.w	d4,-(a3)
		or.w	d2,(a3)
		and.w	d4,-(a3)
		or.w	d1,(a3)
		and.w	d4,-(a3)
		or.w	d0,(a3)
		;
		lea.l	176(a3),a3	;set up	for next line
		dbf.w	d6,nextlin1
;
;now exit the plot routine
;
sexit:
		movem.l	saver,d0-a6	;restore registers
		rts



hline:
	movem.l	d0-d7/a0-a6,saver
	move.w	x2,d1
	move.w	x1,d0
	bpl	hl1
	clr.w	d0
hl1:
	cmp.w	#320,d0
	blt	hl1a
	move.w	#319,d0
	move.w	#319,d1
hl1a:
	cmp.w	#320,d1
	blt	hl2
	move.w	#319,d1
hl2:
	tst.w	d1
	bpl	hl2a
	clr.w	d1
hl2a:
	move.l	$44e,a0		; bs basis
	move.w	y1,d2
	mulu	#160,d2
	add.l	d2,a0		; startzeile
	move.w	d0,d2
	move.w	d0,d7
	lsr.w	#4,d2		; /8 ->	startwort plane	0
	and.l	#$fff0,d7
	lsr.l	#1,d7
	add.l	d7,a0
	move.w	d1,d7		; fÅr spÑter fÅr vergleich
	lsr.w	#4,d7		; end-wort x
	and.w	#%1111,d0	; startbit
	lea	bittab,a2
	lsl.w	#1,d0
	move.w	0(a2,d0),d0
	cmp.w	d2,d7		; sind anfang und end wort gleich?
	bne	hline2
	and.w	#%1111,d1
	lsl.w	#1,d1
	move.w	0(a2,d1),d1
	not.w	d1
	and.w	d1,d0
hline2:
	move.w	d0,d3
	swap	d0
	move.w	d3,d0		; unters auch ins upper	wort
	move.l	d0,d4
	not.l	d4		; umgekehrte maske von d0
	clr.l	d3
	move.w	col,d3
	lsl.w	#3,d3		; mal 8	-> auf tab. mit	8 byte-eintrÑgen
	lea	coltab,a1
	add.l	d3,a1
	move.l	(a1),d5
	move.l	4(a1),d6
	and.l	d0,d5
	and.l	d0,d6
	move.l	(a0),d3
	and.l	d4,d3
	or.l	d5,d3
	move.l	d3,(a0)+
	move.l	(a0),d3
	and.l	d4,d3
	or.l	d6,d3
	move.l	d3,(a0)+
	cmp.w	d2,d7		; war start und	end wort gleich?
	beq	hline3
	move.l	(a1),d5
	move.l	4(a1),d6
hline0:
	addq.w	#1,d2		; start	x
	cmp.w	d7,d2
	bge	hline1		; endwort mit end-x errecht?
	move.l	d5,(a0)+
	move.l	d6,(a0)+
	bra	hline0
hline1:
	and.w	#%1111,d1	; startbit
	lsl.w	#1,d1
	move.w	0(a2,d1),d1
	move.w	d1,d2
	swap	d1
	move.w	d2,d1		; unters auch ins upper	wort
	move.l	d1,d4
	not.l	d4		; umgekehrte maske von d1
	move.l	(a1),d5
	move.l	4(a1),d6
	and.l	d4,d5
	and.l	d4,d6
	move.l	(a0),d3
	and.l	d1,d3
	or.l	d5,d3
	move.l	d3,(a0)+
	move.l	(a0),d3
	and.l	d1,d3
	or.l	d6,d3
	move.l	d3,(a0)+
hline3:
	movem.l	saver,d0-d7/a0-a6
	rts

fill_rec:
	movem.l	d0-a6,saver
	bsr	mouseoff
	move.l	linetab,a0
	move.w	x1,38(a0)   ; min x
	move.w	y1,40(a0)
	move.w	x2,42(a0)    ; max x
	move.w	y2,44(a0)
	move.w	#0,24(a0)	; plane	0-3 farbwerte
	move.w	#0,26(a0)
	move.w	#0,28(a0)
	move.w	#0,30(a0)
	move.w	#2,36(a0)	; Schreibmodus auf Xor
	move.l	#patptr,46(a0)
	clr.w	50(a0)
	clr.w	54(a0)		; kein clipping
	.dc.w	$a005
	bsr	mouseon
	movem.l	saver,d0-a6
	rts

app_init:
	move.w	#10,opcode		; opcode fÅr appl_init
	clr.w	sintin
	move.w	#1,sintout
	clr.w	saddrin
	clr.w	saddrout
	bra	aes

op_vwork:				; VDI-Init.
	move.w	#100,opcode
	clr.w	sintin
	move.w	#11,saddrin
	move.w	handle,contrl+12
	lea	intin,a0
	move.w	#9,d0
opv1:	move.w	#1,(a0)+
	dbf	d0,opv1
	move.w	#2,(a0)+
	bsr	vdi
	move.w	contrl+12,handle
	rts

v_clswrk:				; VDI schliessen
	move.w	#101,opcode
	clr.w	sintin
	clr.w	sintout
	clr.w	saddrin
	clr.w	saddrout
	move.w	handle,contrl+12
	bra	vdi

clr_work:
	move.w	#3,opcode
	clr.w	sintin
	clr.w	saddrin
	bra	vdi

vq_mouse:
	move.w	handle,contrl+12
	move.w	#124,opcode
	clr.w	sintin
	move.w	#1,sintout
	clr.w	saddrin
	move.w	#1,saddrout
	bsr	vdi
	move.l	12(sp),a0		; status
	move.w	intout,(a0)
	move.l	4(sp),a0
	move.w	ptsout,(a0)		; x
	move.l	8(sp),a0
	move.w	ptsout+2,(a0)		; y
	rts

gr_hand:
	move.w	#77,opcode
	clr.w	sintin
	move.w	#5,sintout
	clr.w	saddrin
	clr.w	saddrout
	bsr	aes
	move.w	intout,handle
	rts

mouseoff:
	pea	mouseblk		; maus ist zeigefinger
	move.w	#256,-(sp)
	bsr	gr_mouse
	addq.l	#6,sp
	rts

mouseon:
	pea	mouseblk		; maus ist zeigefinger
	move.w	#257,-(sp)
	bsr	gr_mouse
	addq.l	#6,sp
	rts

gr_mouse:
	move.w	4(sp),intin		; art der maus
	move.l	6(sp),addrin		; mausblock
	move.w	#78,opcode
	move.w	#1,d0
	move.w	d0,sintin
	move.w	d0,sintout
	move.w	d0,saddrin
	clr.w	saddrout
	bsr	aes
	move.w	intout,d0
	rts

load:
	clr.w	-(sp)
	move.l	a5,-(sp)
	move.w	#$3d,-(sp)
	trap	#1
	add.l	#8,sp
	tst.w	d0
	bmi	dskerr
	move.w	d0,-(sp)
	move.l	a6,-(sp)
	move.l	a4,-(sp)
	move.w	d0,-(sp)
	move.w	#$3f,-(sp)
	trap	#1
	add.l	#12,sp
	move.w	#$3e,-(sp)
	trap	#1
	addq.l	#4,sp
	rts

save:
	clr.w	-(sp)
	move.l	a5,-(sp)
	move.w	#$3c,-(sp)
	trap	#1
	add.l	#8,sp
	tst.w	d0
	bmi	dskerr
	move.w	d0,-(sp)
	move.l	a6,-(sp)
	move.l	a4,-(sp)
	move.w	d0,-(sp)
	move.w	#$40,-(sp)
	trap	#1
	add.l	#12,sp
	move.w	#$3e,-(sp)
	trap	#1
	addq.l	#4,sp
	rts

dskerr:
	bsr	mouseoff
	lea	clr_txt,a0
	bsr	print
	lea	err_txt,a0
	bsr	print
	move.w	#7,-(sp)
	trap	#1
	addq.l	#2,sp
	bra	mouseon


print:
	move.l	a0,-(sp)
	move.w	#9,-(sp)
	trap	#1
	addq.l	#6,sp
	rts


clr_pic:
	bsr	mouseoff
	move.l	screen,a0
	move.w	#7999,d0
clp0:	clr.l	(a0)+
	dbf	d0,clp0
	bra	mouseon

save_pic:
	bsr	mouseoff
	move.l	screen,a0
	lea	pic+$22,a1
	bra	sp0

show_pic:
	bsr	mouseoff
	lea	pic+$22,a0
	move.l	screen,a1
sp0:	move.w	#7999,d0
sp1:	move.l	(a0)+,(a1)+
	dbf	d0,sp1
	bra	mouseon

dez_str:	; gibt dreistellige zahl im string aus
	clr.l	d0
	clr.l	d1
	clr.l	d2
	move.w	4(sp),d0		; wert
	move.l	6(sp),a0		; strptr
	move.w	d0,d1
	move.w	#100,d2
	bsr	ds1
	move.w	#10,d2
	bsr	ds1
	move.b	d0,(a0)
	add.b	#'0',(a0)+
	rts
ds1:
	divu	d2,d1
	move.b	d1,(a0)
	add.b	#'0',(a0)+
	mulu	d2,d1
	sub.w	d1,d0
	move.w	d0,d1
	rts

wait:
	move.l	#$20000,d0
wait1:	subq.l	#1,d0
	bne.s	wait1
	rts


infield:	; maus befindet	sich nach klick	im playfield
	bsr	mouseoff
	clr.l	d6
	clr.l	d7
	clr.l	d0
	clr.l	d1
	clr.l	d2
	move.w	mausx,d6
	move.w	mausy,d7
	move.w	x1,d0
	move.w	y1,d1
	divu	#16,d6
	divu	#16,d7		; auf wort bringen
;	errechnen der position im array	(18,9)
	move.w	d7,d2
	sub.w	#1,d2		; startwort (y)	des playfields
	mulu	#18,d2		; 18
	move.w	d6,d3
	sub.w	#1,d3		; startwort (x)
	add.w	d3,d2
	lea	playdat,a0
	move.b	aktbaut+1,0(a0,d2.w)

	mulu	#8,d6
	divu	#16,d0
	mulu	#8,d0
	move.l	screen,a0	; quelladresse festlegen
	mulu	#160,d1
	add.l	d1,a0
	add.l	d0,a0
	move.l	screen,a1	; zieladresse festlegen
	mulu	#2560,d7
	add.l	d7,a1
	add.l	d6,a1

	move.w	#15,d0
inf1:
	move.l	(a0),(a1)
	move.l	4(a0),4(a1)
	add.l	#160,a0
	add.l	#160,a1
	dbf	d0,inf1
	bra	mouseon



click:		; testet auf kommandos
	move.w	mausx,d6
	move.w	mausy,d7
	cmp.w	#16,d6		; playfield min	x
	blt	click1
	cmp.w	#304,d6		; playfield max	x
	bge	click1
	cmp.w	#16,d7		; min y
	blt	click1
	cmp.w	#160,d7		; max y
	bge	click1
	cmp.w	#-1,aktbaut
	beq	click1
	bra	infield

click1:
	lea	koordtab,a0
click2:
	move.w	(a0)+,d0	; min x
	cmp.w	#-1,d0		; ende der tabelle erreicht?
	beq	click3
	move.w	(a0)+,d1	; min y
	move.w	(a0)+,d2	; max x
	move.w	(a0)+,d3	; max y
	move.l	(a0)+,a1	; befehlsadr
	cmp.w	d0,d6		; kleiner als min x?
	blt	click2
	cmp.w	d2,d6		; grîsser als max x
	bge	click2
	cmp.w	d1,d7
	blt	click2
	cmp.w	d3,d7
	bge	click2

	move.w	d0,x1
	move.w	d1,y1
	move.w	d2,x2
	move.w	d3,y2
	move.w	#-1,aktbaut
	jsr	(a1)
waitmaus:	; warten, bis maustaste	losgelassen wurde
	pea	mausstat
	pea	mausy
	pea	mausx
	bsr	vq_mouse
	add.l	#12,sp
	tst.w	mausstat
	bne	waitmaus		; auf linke taste ist commandotest
	rts

click3:		; auf bauteile prÅfen
	clr.w	d5	; zÑhler
	move.w	#0,d0
	move.w	#163,d1
	move.w	#16,d2
	move.w	#163+16,d3
click5:
	cmp.w	d0,d6		; kleiner als min x?
	blt	click4
	cmp.w	d2,d6		; grîsser als max x
	bge	click4
	cmp.w	d1,d7
	blt	click4
	cmp.w	d3,d7
	bge	click4
	move.w	d0,x1
	move.w	d1,y1
	move.w	d2,x2
	move.w	d3,y2
	move.w	d5,aktbaut
	bsr	fill_rec
	bsr	wait
	bra	fill_rec

click4:
	addq.w	#1,d5
	cmp.w	#19,d5
	bge	click6
	add.w	#32,d0
	add.w	#32,d2
	cmp.w	#310,d2
	blt	click5
	move.w	#32,d0
	move.w	#48,d2
	add.w	#20,d1
	add.w	#20,d3
	bra	click5
click6:
	rts



com_load:
	bsr	opndsk
	bsr	load
	move.w	162(a6),aktscene	; eingestellte scenerie	einst.
	bsr	chng_ext		; und nun hiscores laden
	lea	hiend,a4		; sichern
	sub.l	#hiscr,a4		; lÑnge
	lea	input,a5
	lea	hiscore,a6
	bsr	load
	bsr	show_pic
	bra	build

com_save:
	bsr	opndsk
	move.w	aktscene,162(a6)	; aktuelle scenerie mitsichern
	bsr	save
	bsr	chng_ext		; auf 'TOP' Ñndern und hiscores
	lea	hiend,a4		; sichern
	sub.l	#hiscr,a4		; lÑnge
	lea	input,a5
	lea	hiscr,a6
	bsr	save
	bra	show_pic

chng_ext:	; extension auf	'.TOP' Ñndern
	lea	input,a0		; zweites file ext. auf	.seq Ñndern
com_s2:
	move.b	(a0),d0
	tst.b	d0
	beq	com_s1
	cmp.b	#'.',d0
	beq	com_s1
	addq.l	#1,a0
	bra	com_s2
com_s1:
	move.b	#'.',(a0)+		; '.SEQ' als extension
	move.b	#'T',(a0)+
	move.b	#'O',(a0)+
	move.b	#'P',(a0)+
	clr.b	(a0)
	rts

opndsk:
	bsr	save_pic
	bsr	clr_pic
	; 23 mîgliche files ausgeben
	move.b	#$20+4,postxt+3	; starten mit spalte 4
	clr.w	d7		; 23 counter
	pea	dta
	move.w	#$1a,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#0,-(sp)
	pea	filemask
	move.w	#$4e,-(sp)	; FSfirst
	trap	#1
	addq.l	#8,sp
opndsk2:
	tst.w	d0
	bne	opndsk1
	move.b	d7,postxt+2	; zeile	einstellen
	add.b	#$20,postxt+2
	lea	postxt,a0
	bsr	print
	lea	dta+30,a0
	bsr	print		; filename ausgeben
	addq.w	#1,d7
	cmp.w	#23,d7
	bne.s	opndsk3		; 23 mgl. files	aufgelistet?
	cmp.b	#$20+24,postxt+3
	beq.s	opndsk1
	clr.w	d7
	move.b	#$20+24,postxt+3
opndsk3:
	move.w	#$4f,-(sp)
	trap	#1
	addq.l	#2,sp
	bra	opndsk2
opndsk1:
	lea	endpost,a0
	bsr	print
	lea	disk_txt,a0
	bsr	print
	bsr	getinput
	move.l	#164,a4		; 2 mehr, da aktscene mitgesichert wird!
	lea	input,a5
	lea	playdat,a6
	rts

com_clr:
	bsr	fill_rec
	bsr	clrfield
	bra	fill_rec
clrfield:
	lea	playdat,a0	; array	lîschen
	move.w	#161,d0
clr1:	clr.b	(a0)+
	dbf	d0,clr1
	bra	build

com_quit:
	bsr	fill_rec
	addq.l	#4,sp
	bra	quit

com_play:
	bsr	save_pic
	bsr	fill_rec
	bsr	generate	; aufbau der sequenz
	; joystick erlauben, maus abschalten
	pea	joyon
	move.w	#1,-(sp)
	move.w	#25,-(sp)
	trap	#$e
	addq.l	#8,sp
	;
	bsr	play
	; joystick abschalten, maus ein
	pea	joyoff
	move.w	#1,-(sp)
	move.w	#25,-(sp)
	trap	#$e
	addq.l	#8,sp
	;
	bra	show_pic

com_scen:
	bsr	save_pic
	bsr	fill_rec
	pea	mauscurs		; maus simuliert cursortasteb
	move.w	#2,-(sp)
	move.w	#25,-(sp)
	trap	#$e
	addq.l	#8,sp
	lea	scentxt,a0
	bsr	print
com_snxt:
	move.w	aktscene,d0
	lsl.w	#2,d0
	lea	scentxtp,a0
	move.l	0(a0,d0),a0
	bsr	print
	move.w	#7,-(sp)
	trap	#1			; taste	holen
	addq.l	#2,sp
	cmp.b	#13,d0
	beq	com_send
	lsr.l	#8,d0
	lsr.l	#8,d0			; scan code
	cmp.b	#$48,d0			; cursor up?
	bne	com_sen1
	tst.w	aktscene
	beq	com_snxt
	subq.w	#1,aktscene
	bra	com_snxt
com_sen1:
	cmp.b	#$50,d0			; cursor down?
	bne	com_snxt
	cmp.w	#2,aktscene		; schon	maximales erreich?
	beq	com_snxt
	addq.w	#1,aktscene
	bra	com_snxt
com_send:
	pea	mauson			; maus wieder erlauben
	clr.w	-(sp)
	move.w	#25,-(sp)
	trap	#$e
	addq.l	#8,sp
	bra	show_pic


build:	; baut display auf
	bsr	mouseoff
	lea	playdat,a6
	clr.l	d6		; zeiger auf aktuelles playfield
build2:
	clr.l	d0
	move.b	0(a6,d6.w),d0
	movem.l	d0-a6,-(sp)
	bsr	build1
	movem.l	(sp)+,d0-a6
	addq.w	#1,d6
	cmp.w	#162,d6		; schon	ende des arrays	erreicht?
	bne	build2
	bra	mouseon
build1:
	move.w	#1,d1		; zeile	des ziels (start bei z.3)
build1a:
	cmp.w	#18,d6
	blt	build1b
	addq.l	#1,d1
	sub.w	#18,d6
	bra	build1a
build1b:
	move.l	screen,a1
	addq.l	#1,d6		; da erst bei pixel #16	begonnen wird
	mulu	#8,d6
	add.l	d6,a1
	mulu	#2560,d1
	add.l	d1,a1		; zieladr. hergestellt

	move.l	#0,d1		; xpos der quelle
	move.l	#163,d2		; ypos der quelle
build1c:
	tst.w	d0
	beq	build1d
	subq.w	#1,d0
	addq.w	#2,d1
	cmp.w	#19,d1
	blt	build1c
	moveq.l	#2,d1
	add.w	#20,d2
	bra	build1c
build1d:
	move.l	screen,a0
	mulu	#8,d1
	add.l	d1,a0
	mulu	#160,d2
	add.l	d2,a0		; quelladr. erreicht
	move.w	#15,d0
build1e:
	move.l	(a0),(a1)
	move.l	4(a0),4(a1)
	add.l	#160,a0
	add.l	#160,a1
	dbf	d0,build1e
	rts

getinput:
	bsr	mouseoff
	lea	curson,a0
	bsr	print
	lea	input,a6
	clr.b	(a6)
geti2:
	move.w	#7,-(sp)
	trap	#1
	addq.l	#2,sp
	cmp.b	#13,d0		; return gedrÅckt?
	beq	geti1
	cmp.b	#8,d0		; backspace ?
	bne	geti3
	cmp.l	#input,a6	; bei bs schon anfang erreicht?
	beq	geti2
	subq.l	#1,a6
	clr.b	(a6)
	lea	crsleft,a0
	bsr	print
	bra	geti2
geti3:
	cmp.l	#input+12,a6	; nur 12 zeichen erlaubt
	bge	geti2
	cmp.b	#' ',d0
	blt	geti2
	cmp.b	#'z',d0
	bhi	geti2
	move.b	d0,(a6)+
	clr.b	(a6)
	lea	-1(a6),a0
	bsr	print
	bra	geti2
geti1:
	lea	cursoff,a0
	bsr	print
	bra	mouseon

generate:	; generiert .SEQ in playdat (->	D0.l enthÑlt lÑnge)
	lea	playdat,a0
	lea	playseq,a1
	clr.l	d0
	moveq	#1,d1			; 2 mal	soll startteil da sein
gen0:
	move.b	(a0),d0
	move.w	d0,starter
	cmp.b	#18,d0			; Startbauteile	suchen
	beq	gen1a
	cmp.b	#9,d0
	beq	gen1a
	addq.l	#1,a0
	bra	gen0
gen1:
	clr.l	d0
	move.b	(a0),d0			; teilchennr holen
gen1a:
	subq.w	#1,d0			; da teil 0 nur	leerzeichen ist
	lsl.w	#2,d0
	lea	playtab,a2
	move.l	0(a2,d0.w),a3		; tabelle mit seq. werten
	move.w	(a3)+,d4		; aufahrt1 direction
	move.w	(a3)+,d2		; richtung der einfahrt
	move.w	(a3)+,d6		; ausfahrt2 direktion
	lea	offs,a5
	move.w	d4,d5
	mulu	#2,d5
	move.w	0(a5,d5.w),d5		; offset holen
	ext.l	d5
	move.w	d6,d7
	mulu	#2,d7
	move.w	0(a5,d7.w),d7		; offset holen
	ext.l	d7
	move.w	starter,d0		; bei ersten teilchen
	cmp.b	(a0),d0			; stimmt eingetragene richtung!
	beq	gen2
	cmp.w	olddir,d2		; ist teil richtig rum?
					; mit d2 (ausf2, da ausf-einf stimmen)
	beq	gen2			; ja...ansonsten andersrum einlesen
	exg	d4,d6			; einfahrt und ausfahrt	swappen
	exg	d5,d7			; offsets swappen
	move.l	a3,a4			; ansonsten andersrum lesen
gen1d:
	cmp.b	#$80,(a4)		; ans ende der sequenz
	beq	gen1c
	addq.l	#1,a4			; solange suchen, bis $80 gefunden
	bra	gen1d
gen1c:					; sequenz verkehrtrum einlesen
	move.b	-(a4),d0
	neg.b	d0			; richtung genau umdrehen
	move.b	d0,(a1)+
	cmp.l	a4,a3
	bne	gen1c
	bra	gen3
gen2:
	move.b	(a3)+,(a1)+		; dir gl.-> sequenz norm. einlesen
	cmp.b	#$80,(a3)
	bne	gen2
gen3:
	move.w	d4,olddir		; ausfahrtsdir.
	move.b	(a0),d0
	cmp.w	starter,d0		; starter wieder erreicht?
	beq	genend
gen4:
	add.l	d5,a0			; offset im playgrd dazuaddieren
	bra	gen1
genend:
	dbf	d1,gen4			; schon	alle 2 startteile verar.?
	move.b	#$80,(a1)+		; endkennung
	move.l	a1,d0
	sub.l	#playseq,d0		; lÑnge	in D0.l
	rts


;-------------------------------------------------------------------
main:
	clr.l	-(sp)
	move.w	#$20,-(sp)		; in SPVI
	trap	#1
	addq.l	#6,sp
	move.l	d0,-(sp)
	move.b	$ff820a,d0		; 50/60	hertz bei vbl!
	move.w	#680,waitcnt
	btst	#1,d0			; 1 -> 50 Hz
	bne	main1
	move.w	#790,waitcnt
main1:
	movem.l	$ff8240,d0-d7		; Farben sichern
	movem.l	d0-d7,savcolor
	movem.l	clrcolor,d0-d7
	movem.l	d0-d7,$ff8240		; Bildschirm auf Schwarz
	move.w	#$20,-(sp)
	trap	#1
	addq.l	#6,sp

	bsr	app_init
	bsr	gr_hand
	bsr	op_vwork
	bsr	clr_work

	bsr	init_pr			; line-A init.
	bsr	mouseoff

	move.w	#3,-(sp)
	trap	#$e
	addq.l	#2,sp
	move.l	d0,screen

	move.w	#4,-(sp)
	trap	#$e
	addq.l	#2,sp
	move.w	d0,rez

	clr.w	-(sp)
	pea	-1
	pea	-1
	move.w	#5,-(sp)
	trap	#$e
	add.l	#12,sp

	lea	scndscr,a0	; zweiten bildschirm auf 256 bytes berechnen
scrn2:
	move.l	a0,d0
	and.l	#$ff,d0
	beq	scrn1
	addq.l	#2,a0
	bra	scrn2
scrn1:
	move.l	a0,screen2	; startadresse merken

	lea	digisnd,a6
	lea	diginame,a5
	lea	$fffff,a4	; zuerst title musik laden
	bsr	load
	move.l	screen,a6
	sub.l	#$22,a6
	lea	titlen,a5
	lea	$fffff,a4
	bsr	load		; titelbild laden
	addq.l	#2,a6
	move.l	a6,-(sp)
	move.w	#6,-(sp)
	trap	#$e		; palette des titelbildes anzeigen
	addq.l	#6,sp
	;	digital	snd spielen
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1		; enter	SPVI
	addq.l	#6,sp
	move.l	d0,-(sp)
	bsr	playdigi	; spiel	digital	sound bis tastendruck!
	lea	playpal,a6
	lea	cockpitn,a5	; load the cockpit palette
	lea	$22,a4		; length
	bsr	load
	move.l	screen2,a6
	sub.l	#$22,a6
	lea	cockpitn,a5
	lea	$fffff,a4
	bsr	load
	move.w	#5439,d0
	move.l	screen2,a0
	lea	datascr1,a1	; spritebereich	kopieren und
da1:				; im alten bild	lîschen
	move.l	(a0),(a1)+
	clr.l	(a0)+
	dbf	d0,da1

	lea	signscr1-$22,a6	; hier stehen die schilder sprites
	lea	signn1,a5
	lea	$fffff,a4
	bsr	load		; bild laden

	lea	signscr2-$22,a6	; hier stehen die schilder sprites
	lea	signn2,a5
	lea	$fffff,a4
	bsr	load		; bild laden

	lea	film-$22,a6
	lea	filmname,a5
	lea	$fffff,a4	; film nachladen
	bsr	load

	lea	explsnd,a6
	lea	explname,a5
	lea	$fffff,a4	; explusion nachladen
	bsr	load

	move.w	#34,-(sp)	; ACIA-IRQ Vektortab holen
	trap	#$e
	addq.l	#2,-(sp)
	move.l	d0,a0
	move.l	#joyirq,24(a0)	; eigene joystickroutine

	lea	picname,a5
	lea	pic,a6
	move.l	#$fffff,a4	 ; arbeitsbild laden
	bsr	load
	pea	pic+2
	move.w	#6,-(sp)
	trap	#$e
	addq.l	#6,sp

	bsr	resettim	 ; musik auschalten
	move.w	#$20,-(sp)
	trap	#1
	addq.l	#6,sp

	bsr	mouseon
	bsr	show_pic		; bild zeigen
	bsr	mouseoff

	lea	164,a4
	lea	input,a5
	lea	playdat,a6		; default track	laden
	bsr	load
	move.w	162(a6),aktscene	; eingestellte scenerie	einst.
	bsr	chng_ext		; und nun hiscores laden
	lea	hiend,a4		; sichern
	sub.l	#hiscr,a4		; lÑnge
	lea	input,a5
	lea	hiscore,a6
	bsr	load

	pea	mouseblk		; maus ist zeigefinger
	move.w	#3,-(sp)
	bsr	gr_mouse
	addq.l	#6,sp
	bsr	mouseon

	pea	mauson			; maus wieder erlauben
	clr.w	-(sp)
	move.w	#25,-(sp)
	trap	#$e
	addq.l	#8,sp

	bsr	build
loop1:
	pea	mausstat
	pea	mausy
	pea	mausx
	bsr	vq_mouse
	add.l	#12,sp

	move.w	mausstat,d0
	btst	#0,d0
	beq	loop1a			; auf linke taste ist commandotest
	bsr	click
loop1a:
	bra	loop1


quit:
	move.w	rez,-(sp)
	pea	-1
	pea	-1
	move.w	#5,-(sp)
	trap	#$e
	add.l	#12,sp

	pea	savcolor		 ; Farben wieder herstellen
	move.w	#6,-(sp)
	trap	#$e
	addq.l	#6,sp

	bra	v_clswrk

; ---------------- hauptroutine	der play-routinen ------------------
play:
	bsr	mouseoff
	clr.l	-(sp)
	move.w	#$20,-(sp)	; in SPVI gehen	wÑhrend	dem spiel
	trap	#1
	addq.l	#6,sp
	move.l	d0,-(sp)
	bsr	prepdigi
	bsr	asklaps		; anzahl der laps holen
	bsr	askplay		; anzahl der spieler holen
	bsr	resettim
	pea	initsnd
	bsr	setsound
	addq.l	#4,sp
	lea	plscore,a0
	move.w	#$0000,d0
	move.w	d0,0(a0)	; hiscores initialsieren
	move.w	d0,2(a0)
	move.w	d0,4(a0)
	move.w	d0,6(a0)
	clr.w	nrplay1
	;
end2:	; einsprung bei	spieler	countdown
	move.w	#7999,d0	; show cockpit on the screen
	move.l	screen2,a0
	move.l	screen,a1
pl01:	move.l	(a0)+,(a1)+
	dbf	d0,pl01
	;
	pea	playpal+2	; neue palette setzen
	move.w	#6,-(sp)
	trap	#$e
	addq.l	#6,sp
	move.l	screen,aktscr	; startscreen angeben
	; total	laps setzen
	clr.l	d0
	move.w	nrlaps,d0
	lea	datascr1+80,a0	; basis	der zeichen
	lsl.w	#3,d0
	add.l	d0,a0
	move.l	a0,-(sp)	; adr des sprites
	move.w	#9,-(sp)	; hîhe des sprites
	move.w	#188,-(sp)	; y
	move.w	#108,-(sp)	; x
	bsr	set16spr
	add.l	#10,sp
	;
	lea	playseq,a0	; 1. sequenz auswerten
	lea	aktseq,a1	; und in aktseq	dekomp.	schreiben
pl0a:
	move.b	(a0)+,d0
	cmp.b	#$80,d0		; ende des tracks?
	beq	pl0c
	and.w	#$0f,d0		; nur unteren 4	bits als trackbez.
	move.w	d0,d1		; lower	nibble auch ins	upper
	lsl.w	#8,d1		; gleich zweimal trackbez. im wort
	or.w	d1,d0
	move.w	#2,d6		; 3 mal
pl0:
	move.w	d0,(a1)+	; 2 bytes -> 1 teil aus	ca. 6*10= 60 b.
	dbf	d6,pl0
	bra	pl0a
pl0c:
	move.w	#3,d6
pl0ca:
	clr.w	(a1)+		; noch leerseqs	anhÑngen
	dbf	d6,pl0ca
	move.b	#%0111,(a1)	; endkennung ist trackbez. 7
	;
	; schilder zufÑllig erzeugen
	lea	aktseq,a6
	sub.l	a6,a1		; lÑnge	des tracks in bytes
	move.l	a1,d7
	move.w	#35,d6		; starten mit schilder aufbau bei seq#35
tryagain:
	move.w	#17,-(sp)
	trap	#$e		; random function
	addq.l	#2,sp
	and.b	#%1111,d0
	move.b	d0,d1
	and.b	#%0111,d1
	cmp.b	#$3,d1		; nur 3	schilder sind da, darum	abfragen!
	bhi	tryagain	; undef. schild, dann neu erzeuegen!
	lsl.b	#4,d0
	or.b	d0,0(a6,d6)	; schild einschreiben
	add.w	#40,d6		; offset zum nÑchsten schild
	cmp.w	d7,d6		; schon	ende erreicht?
	blt	tryagain
	;
	; scenerie bitverschoben erstellen
	move.w	aktscene,d0
	lsl.w	#2,d0
	lea	scenaddr,a0
	move.l	0(a0,d0),a0		; adr. der akt.	scenerie
	lea	bitscene,a1		; adr der 16 verschobenen
	move.l	a1,a2
	move.w	#1279,d0		; 32 zeilen kopieren
prep1:
	move.l	(a0)+,(a1)+		; erstmal kopieren
	dbf	d0,prep1
	;
	move.w	#14,d5			; 16 verschobene sceneries
prep4:
	move.l	a2,a0
	move.l	a2,a1
	add.l	#5120,a1		; nÑchsten 32 zeilen
	move.l	a1,a2			; als neue arbeitsseq. nehmen
	move.w	#1279,d0
prep2:
	move.l	(a0)+,(a1)+
	dbf	d0,prep2
	;
	move.l	a2,a0
	move.w	#31,d7			; 32 zeilen
prep3d:
	move.w	#3,d6			; a la 4 bitplanes
prep3c:
	roxr.w	0(a0)			; nach rechts verschieben
	roxr.w	8(a0)
	roxr.w	16(a0)
	roxr.w	24(a0)
	roxr.w	32(a0)
	roxr.w	40(a0)
	roxr.w	48(a0)
	roxr.w	56(a0)
	roxr.w	64(a0)
	roxr.w	72(a0)
	roxr.w	80(a0)
	roxr.w	88(a0)
	roxr.w	96(a0)
	roxr.w	104(a0)
	roxr.w	112(a0)
	roxr.w	120(a0)
	roxr.w	128(a0)
	roxr.w	136(a0)
	roxr.w	144(a0)
	roxr.w	152(a0)
	bcc	prep3a
	or.w	#$8000,(a0)	; bit setzen
	bra	prep3b
prep3a:
	and.w	#$7fff,(a0)
prep3b:
	addq.l	#2,a0		; zur nÑchsten bitplane
	dbf	d6,prep3c
	add.l	#160-8,a0	; in nÑchste zeile
	dbf	d7,prep3d
	dbf	d5,prep4	; nÑchste scenerie

	; himmel gestalten
	bsr	setsky
	pea	initmtr
	bsr	setsound
	addq.l	#4,sp

	; -----	beginn des spieles
	lea	fakttab,a2	; trackdatenanhaltewert
	clr.l	d0
	clr.l	d1
pl0c1:
	addq.w	#1,d0
	move.w	(a2)+,d2
	addq.w	#1,d2
	add.w	d2,d1
	cmp.w	#70,d1
	blt	pl0c1
	subq.w	#1,d0
	move.w	d0,lastdat	; anz der angezeigten trackdaten
	;
	move.w	#$9998,score	; score	fÅr den	spieler
	lea	$fffa07,a2
	movep.w	0(a2),d1
	move.w	d1,reg79
	move.l	$70,-(sp)
	move.w	nrlaps,nrlaps1	; counter
nextlap:; einsprung fÅr	die nÑchste runde
	; lap setzen
	clr.l	d0
	move.w	nrlaps,d0
	sub.w	nrlaps1,d0
	addq.w	#1,d0
	lea	datascr1+80,a0	; basis	der zeichen
	lsl.w	#3,d0
	add.l	d0,a0
	move.l	a0,-(sp)	; adr des sprites
	move.w	#9,-(sp)	; hîhe des sprites
	move.w	#177,-(sp)	; y
	move.w	#108,-(sp)	; x
	bsr	set16spr
	add.l	#10,sp
	;
	lea	aktseq,a0	; start	des tracks
	move.b	#%0100,signinfo	; GO! Schild
	move.w	#40,signrow
	clr.w	signcnt
	move.w	nrlaps,d0
	cmp.w	nrlaps1,d0	; andere runde,	dann init. Åberspringen
	beq	reinit
	clr.w	signrow
	bra	pl2
reinit:	; einsprung nach crash!
	clr.l	d0
	move.b	randtab,d0
	move.w	d0,randtab2
	move.w	d0,randcnt
	move.w	#13,startcol
	clr.w	slowfak
	clr.w	xadd
	clr.w	speedfak
	clr.w	joydir		; joy. direction fÅr lenkrad
	clr.w	scroll
	clr.w	gang
	clr.w	rounds
	movem.l	d0-a6,-(sp)
	bsr	setgang
	movem.l	(sp)+,d0-a6
	clr.w	scorecnt	; nicht	bei jedem aufbau score decr.
	move.w	d0,speed
	move.w	d0,getfak
	bsr	speedo		; speedometer init.
	; zunÑchste vbl	auf eigene routine, alten vbl auf den stack!
	move.w	#$2700,SR
	lea	$fffa07,a2
	clr.b	(a2)
	and.b	#%01000000,2(a2)
	move.l	#vbl,$70
	move.w	#$2300,SR
	;

pl2:	; -----	start des bildschirmaufbaus
	; zunÑchst auf pause-tasten testen
	cmp.b	#$39,$fffc02
	bne	pl2key
	movem.l	d0-a6,-(sp)
	pea	initdat
	bsr	setsound
	addq.l	#4,sp
	move.w	#$2700,sr
	; scenerie lîschen und pausenbild einblenden
	clr.l	d0
	move.b	$ff8201,d0
	lsl.l	#8,d0
	move.b	$ff8203,d0
	lsl.l	#8,d0
	move.l	d0,a0
	move.l	a0,a1
	move.w	#2839,d0
pl0key:
	clr.l	(a0)+
	dbf	d0,pl0key
	lea	signscr2+10400,a0
	add.l	#2400,a1
	move.w	#40*38,d0
pl0key1:
	move.l	(a0)+,(a1)+
	dbf	d0,pl0key1
	;
	lea	$fffa00,a1
	move.b	#1,$19(a1)		; vorteiler 4
	move.b	#$48,$1f(a1)
	clr.l	takt2
	clr.l	taktend2
	clr.w	takptr2
	or.b	#$20,7(a1)		; timer	A an
pl2key1:
	cmp.b	#$39,$fffc02
	beq	pl2key1
pl2key2:
	bsr	playmus2
pl2key1a:
	btst	#5,$fffa0b
	beq	pl2key1a
	move.b	#$df,$fffa0b
	cmp.b	#$39,$fffc02
	bne	pl2key2
pl2key3:
	cmp.b	#$39,$fffc02
	beq	pl2key3
	;
	bsr	setsky
	pea	initsnd
	bsr	setsound
	addq.l	#4,sp
	pea	initmtr
	bsr	setsound
	addq.l	#4,sp
	move.w	#$2300,sr
	clr.b	$fffa07
	movem.l	(sp)+,d0-a6

pl2key:
	; zunÑchst auf abort-tasten testen
	cmp.b	#$61,$fffc02
	bne	noabort
	move.w	#$2700,SR
	move.l	(sp)+,$70
	lea	$fffa07,a2
	move.w	reg79,d1
	movep.w	d1,0(a2)
	move.w	#$2300,SR
	;
	pea	initsnd
	bsr	setsound
	addq.l	#4,sp
	move.l	screen,$44e	; logical screen wieder	normal setzen
	move.b	screen+2,$ff8203
	move.b	screen+1,$ff8201
	bra	abort
noabort:
	; zunÑchst auf anderen bildschirm schalten
	lea	aktscr,a1
	move.l	screen,d1
	cmp.l	(a1),d1		; akt. bearbeitender scr ist screen?
	beq	setscr1
	move.l	d1,(a1)		; fÅrs nÑchste mal anderen screen setzen
	move.l	screen2,$44e
	bra	setscr2
setscr1:
	move.l	screen2,(a1)
	move.l	d1,$44e
setscr2:
	move.b	2(a1),$ff8203
	move.b	1(a1),$ff8201
	move.b	1(a1),d0
sync:				; das ganze noch synchronisieren
	cmp.b	$ff8205,d0	; warten, bis andere bildschirm	angenommen
	bne	sync

	bsr	setscore	; aktualisiere score
	;
	move.l	a0,a1
	move.w	#0,d1
	move.w	#319,d2
	move.w	#70+70,y1
	clr.l	d4
	clr.w	scroll1
	clr.w	xadd2
	; joystickabfrage
	btst	#2,joystat	; links?
	beq	pl2a
	addq.w	#1,scroll
	subq.w	#1,scroll1
	addq.w	#4,joydir	; lenkrad mitbewegen
	move.w	randtab2,d0
	sub.w	getfak,d0
	addq.w	#4,d0
	subq.w	#4,xadd2
	add.w	d0,xadd
pl2a:
	btst	#3,joystat	; rechts?
	beq	pl2b
	subq.w	#1,scroll
	addq.w	#1,scroll1
	subq.w	#4,joydir	; lenkrad mitbewegen
	move.w	randtab2,d0
	sub.w	getfak,d0
	addq.w	#4,d0
	addq.w	#4,xadd2
	sub.w	d0,xadd
pl2b:	; keine	joystickbewegung
	btst	#0,joystat	; nach oben (speed up?)
	beq	pl2c
	btst	#7,joystat	; knopf	- gang schltung
	beq	pl2b2
	cmp.w	#3,gang		; schon	hîchster gang?
	beq	pl2c
	cmp.w	#3,rounds
	bne	pl2c
	addq.w	#1,gang
	clr.w	rounds
	bsr	setgang
	subq.w	#1,rounds
pl2b2:
	cmp.w	#3,rounds	; schon	hîchste	umdrehung
	beq	pl2c
	tst.w	getfak		; schon	grîûtmgl. speed?
	beq	pl2b1
	addq.w	#1,rounds
	subq.w	#1,getfak
	move.w	getfak,speed
	bsr	setmotor
	bsr	speedo
pl2b1:
	move.w	randtab2,d0
	subq.w	#1,d0
	cmp.w	speedfak,d0	; max. schon erreicht?
	beq	pl2d
	addq.w	#1,speedfak
	bra	pl2d
pl2c:
	btst	#1,joystat	; nach unten (bremsen?)
	beq	pl2d
	btst	#7,joystat	; knopf	- gang schltung
	beq	pl2c2
	tst.w	gang		; schon	niedrigster gang?
	beq	pl2d
	tst.w	rounds
	bne	pl2d
	subq.w	#1,gang
	move.w	#3,rounds
	bsr	setgang
	addq.w	#1,rounds
pl2c2:
	bsr	decspeed
pl2d:	; ende der joystcikabfragen
	; steuerrad berichtigen
	tst.w	joydir
	beq	joywork
	bmi	joyneg
	subq.w	#2,joydir
	bra	joywork
joyneg:
	addq.w	#2,joydir
joywork:
	bsr	setsteer
	; strassenfaktoren berichtigen
	move.w	getfak,d7	; speedfaktor 0(fast) -	15(slow)
	addq.w	#1,d7
	move.b	(a1),d0		; akt. vorderes	seq.teil
	and.b	#%1111,d0	; nur trackverlauf herausfiltern
	btst	#3,d0		; negativ im nibble
	bne	negcurv1
	and.w	#%111,d0
	bra	setfak
negcurv1:
	or.w	#$fff8,d0      ; ext.nibble
setfak:
	tst.w	d0
	beq	pl2d1		; keine	kurve, dann Åbergehen
	tst.w	xadd2		; wird in kurve	gelenkt?
	beq	setfak2
	lea	faktab,a3
	bra	setfak21
setfak2:
	lea	faktab2,a3
setfak21:
	move.b	-1(a3,d7),d7
	ext.w	d7
	tst.w	d0
	bpl	setfak2a	; negativ
	neg.w	d0
	neg.w	d7		; damit	neg/pos-verhÑltn. wieder stimmt
setfak2a:
	cmp.w	#1,d0		; kurvesteile =	1
	beq.s	setfak2b
	move.l	#300,d0		 ; bei 2...
	bra.s	setfak2c
setfak2b:
	move.l	#220,d0
setfak2c:
	divs	d7,d0
	bra	pl3
pl2d1:
	move.w	xadd,d0
	ext.l	d0
	divs	#8,d0
	ext.l	d0
	divs	d7,d0
pl3:	;
	move.w	randtab2,d7	; if speed is 0	then no	left-right move!
	cmp.w	getfak,d7
	bne	pl3a
	move.w	scroll1,d0
	add.w	d0,scroll
	move.w	xadd2,d0
	add.w	d0,xadd
	clr.w	d0
pl3a:
	add.w	d0,xadd
	add.w	xadd,d1
	add.w	xadd,d2
	;
	lea	fakttab,a3	; verkleinerungsfaktorentabelle
	;
	lea	randtab,a4
	move.w	randcnt,d7
	move.w	d7,randcnt2
	move.w	startcol,randcol
	move.w	speedfak,d0
	sub.w	d0,randcnt
	bpl	pl2f
	move.w	randtab2,d0
	add.w	d0,randcnt
	tst.w	randcnt
	bpl	pl2f1
	move.w	d0,randcnt
pl2f1:
	cmp.w	#13,startcol
	beq	pl2e
	move.w	#13,startcol
	bra	pl2f
pl2e:
	move.w	#12,startcol
pl2f:
	;

	move.w	#69,d0		; zeilenzÑhler
	movem.l	d0-a6,-(sp)
	move.l	$44e,a6
	add.l	#11360,a6	; 71 zeilen x 160 bytes
	movem.l	wiese,d1-d7/a0-a4
drwwiese:
	movem.l	d1-d7/a0-a4,(a6)	; wiese	auf bildschirm
	movem.l	d1-d7/a0-a4,48(a6)
	movem.l	d1-d7/a0-a4,96(a6)
	movem.l	d1-d5,144(a6)
	add.l	#160,a6
	dbf	d0,drwwiese
	movem.l	(sp)+,d0-a6

	move.w	d0,aktrow	; 69
	move.w	lastdat,d3
	move.b	0(a1,d3),d3	; letztes teilseg. des jetzigen	aufbaus
	lsr.b	#4,d3		; schilderinfo
	tst.b	d3		; nur sichern, wenn schild ist
	beq	pl1
	move.b	d3,signinfo	; sichern
	clr.w	signrow		; zeile	des schildes (start unten 0)
	clr.w	signcnt		; init.

pl1:	; ------- start	des zeilenaufbaus (je 1	zeile)
	move.b	(a1)+,d3
	and.b	#%1111,d3	; nur trackverlauf herausfiltern
	cmp.b	#7,d3
	beq	endoftr		; 7 ist	kennung	fÅr ende der strecke
	btst	#3,d3		; negativ im nibble
	bne	negcurve
	and.w	#%111,d3
	bra	showtr
negcurve:
	or.w	#$fff8,d3      ; ext.nibble
showtr:
	;
	move.w	(a3)+,d5	; anzahl, wie oft diese	zeile vorkommt
lineloop:
	;
	dbf	d7,rand1	; randhaltezÑhler abgelaufen?
	add.w	randcnt2,a4
	clr.l	d7
	move.b	(a4),d7
	move.w	d7,randcnt2
	cmp.w	#13,randcol
	beq	rand2
	move.w	#13,randcol
	bra	rand1
rand2:
	move.w	#12,randcol
rand1:	;
	add.w	d3,d4
	move.w	d4,d6
	ext.l	d6
	move.w	aktrow,d0
	lsl.w	#1,d0
	addq.w	#1,d0
	divs	d0,d6		; faktor dritteln
	add.w	d6,d1
	add.w	d6,d2
	; und nun noch den verzerrungsfaktor (links bzw	rechts einfahrend)
	move.l	d1,-(sp)
	move.l	d2,-(sp)	; register merken
	move.w	xadd,d0
	move.w	aktrow,d6
	sub.w	#70,d6
	muls	d6,d0
	divs	#100,d0
	beq	pl3b		; if ergebnis =	0, dann	Åbergehen
	add.w	d0,d2
	add.w	d0,d1
pl3b:
	move.w	aktrow,d6	; zeilenzÑhler
	move.w	d6,d0
	lsr.w	#2,d6		; durch	8 als grîssenfaktor fÅr	rand
	addq.w	#1,d6		; rand auch am schluss (0) als pixel da
	move.w	d1,x1
	move.w	d1,x2
	sub.w	d6,x1		; rand bis zur strasse
	cmp.w	signrow,d0
	bne	no1
	move.w	x1,signleft
no1:
	move.w	randcol,col	; randfarbe
	bsr	hline
	move.w	d1,x1
	move.w	d2,x2
	clr.w	col
	bsr	hline		; strasse
	move.w	d2,x1
	move.w	d2,x2
	add.w	d6,x2
	cmp.w	signrow,d0
	bne	no2
	move.w	x2,signrigt
no2:
	move.w	randcol,col	; zweiten rand an rechter seite
	bsr	hline
	subq.w	#1,y1
	move.l	(sp)+,d2
	move.l	(sp)+,d1
	lea	rowtab,a5
	move.w	aktrow,d0
	lsl.w	#1,d0
	move.w	0(a5,d0),d0
	add.w	d0,d1
	sub.w	d0,d2
	subq.w	#1,aktrow
	;
	dbf	d5,lineloop
	;
	tst.w	aktrow		; schon	bildschirm aufgebaut?
	bpl	pl1

	; ja, dann kann	ja ein mgl. schild aufgebaut werden...
	move.b	signinfo,d0	; schildinfos
	and.l	#$7,d0
	beq	nosign1		; 0? ->	kein schild
	subq.l	#1,d0		; mit 0	beginnen
	lsl.w	#2,d0		; auf lwort-tabelle vorbereiten...
	lea	signtab,a1
	move.l	0(a1,d0),a2	; startadr. der	schilderzeile (13 stÅck)
	lea	signrtab,a1
	move.w	signrow,d1
	move.w	d1,d6
	lsr.w	#1,d6		; abstand schild - strasse
	move.b	0(a1,d1),d1	; schildnr (grîsse) in abhÑgnigkeit von	row
	and.w	#$ff,d1
	lsl.w	#1,d1		; auf wort tab
	lea	signlen,a1
	move.w	0(a1,d1),d5	; breite des schildes in pixels
	lsl.w	#1,d1		; auf lwort-tab
	lea	signoffs,a1
	add.l	0(a1,d1),a2	; startadr. des	spez. schildes
	btst	#3,signinfo	; seite	des schildes
	bne	sright
	move.w	signleft,d1
	sub.w	d5,d1
	sub.w	d6,d1
	bra	sside
sright:
	move.w	signrigt,d1	; startkkordinate
	add.w	d6,d1
sside:
	move.w	#71-65,d0
	add.w	signrow,d0	; basiszeile
	; schild ausgeben
	move.l	a2,-(sp)	; adr. des schildes
	move.w	#64,-(sp)	; hîhe des sprites
	move.w	d0,-(sp)	; y
	move.w	d1,-(sp)	; x
	bsr	setsign
	add.l	#10,sp
	cmp.w	#16,d5		; bei grossen schildern	nochmal
	beq	decsign
	addq.l	#8,a2
	add.w	#16,d1
	move.l	a2,-(sp)	; adr. des schildes
	move.w	#64,-(sp)	; hîhe des sprites
	move.w	d0,-(sp)	; y
	move.w	d1,-(sp)	; x
	bsr	setsign
	add.l	#10,sp
	cmp.w	#32,d5		; bei grossen schildern	nochmal
	beq	decsign
	addq.l	#8,a2		; 64 pixels breite schilder
	add.w	#16,d1
	move.l	a2,-(sp)	; adr. des schildes
	move.w	#64,-(sp)	; hîhe des sprites
	move.w	d0,-(sp)	; y
	move.w	d1,-(sp)	; x
	bsr	setsign
	add.l	#10,sp
	addq.l	#8,a2
	add.w	#16,d1
	move.l	a2,-(sp)	; adr. des schildes
	move.w	#64,-(sp)	; hîhe des sprites
	move.w	d0,-(sp)	; y
	move.w	d1,-(sp)	; x
	bsr	setsign
	add.l	#10,sp
decsign:	; schild nach vorne kommen lassen
	subq.w	#1,signcnt
	bpl	nosign1
	addq.w	#1,signcnt
	tst.w	speedfak
	beq	nosign1		; stillstand?
	move.w	randtab2,d0
	sub.w	speedfak,d0
	clr.l	d1
	move.w	signrow,d1
	add.w	#40,d1
	divu	#20,d1
	divu	d1,d0
	move.w	d0,signcnt
	add.w	d1,signrow
	cmp.w	#70,signrow	; schild schon durch?
	blt	nosign1
	clr.b	signinfo
	move.w	#-1,signrow
	clr.w	signcnt
	;
nosign1:; auf crash abfragen
	move.w	xadd,d0
	cmp.w	#130,d0
	bge	nos1
	cmp.w	#-130,d0
	ble	nos1
	bra	nos3
nos1:
	tst.w	speedfak
	beq	nos3		; stillstand?
	movem.l	d0-a6,-(sp)
	pea	randsnd
	bsr	setsound	; 3.stimme ist rand
	addq.l	#4,sp
	subq.w	#1,slowfak
	bpl	nos4
	bsr	decspeed
	move.w	#10,slowfak	; nicht	jedesmal erniedrigen
nos4:
	movem.l	(sp)+,d0-a6
	bra	nos2
nos3:
	move.b	#10,$ff8800
	clr.b	$ff8802		; ansonsten lautspr. abschalten
nos2:
	move.w	xadd,d0
	cmp.w	#300,d0
	bge	crash		; es hat gekracht!
	cmp.w	#-300,d0
	ble	crash
	cmp.w	#64,signrow
	ble	nocrash
	move.b	signinfo,d1
	beq	nocrash
	btst	#3,d1
	beq	ltstside
	neg.w	d0
ltstside:
	cmp.w	#140,d0
	ble	nocrash
crash:	; hier steht die routine fÅr den CRASH!
	movem.l	d0-a6,-(sp)
	move.w	#$2700,sr
	move.l	#leervbl,$70
	move.w	#$2300,sr
	; explosion simulieren
	lea	$ff8201,a1	; video	ram basis adr.
	move.b	screen+1,(a1)	; bildschirm ist screen
	move.b	screen+2,2(a1)
	lea	film,a0
	move.l	screen,a1
	move.w	#7999,d0
crash1:
	move.l	(a0)+,(a1)+	; bild zeigen
	dbf	d0,crash1
	; palettenwechsel (simuliert feuer!)
	bsr	settimer	; explusion dazuschalten
	lea	$ff8240,a1
	movem.l	(a1),d0-d7
	movem.l	d0-d7,-(sp)	; alte palette merken
	movem.l	filmpal+2,d0-d7
	movem.l	d0-d7,(a1)
	move.w	#60,d6
crash1a:
	lea	$ff8240,a2
	lea	$ff8207,a3
	move.l	screen,d0
crash1b:
	movep.w	0(a3),d1	; auf rasterstrahl sync	warten
	cmp.w	d1,d0
	bne	crash1b
	;
	move.w	$2(a2),d5
	movem.l	$4(a2),d0-d3
	movem.l	d0-d3,2(a2)
	move.w	d5,$12(a2)
	move.w	#290,d7
crash1e:
	dbf	d7,crash1e
	dbf	d6,crash1a
	movem.l	filmpal+2,d0-d7
	movem.l	d0-d7,(a2)
	move.l	#$10000,d0
crash1d:
	subq.l	#1,d0
	bne.s	crash1d

	bsr	resettim
	move.l	screen2,a1
	move.l	screen,a2
	move.w	#7999,d0
crash2:				; bildschirm wieder herstellen
	move.l	(a1)+,(a2)+
	dbf	d0,crash2
	lea	$ff8240,a1
	movem.l	(sp)+,d0-d7
	movem.l	d0-d7,(a1)	; alte palette wieder herstellen
	; zur strafe score um 30 vermindern!
	move.w	#$30,d0
	moveq.l	#0,d3
	move.b	score+1,d1
	move.b	score,d2
	sbcd	d0,d1
	sbcd	d3,d2
	bcc	noext		; nicht	0000 unterlaufen!
	clr.w	d1
	clr.w	d2
noext:
	move.b	d1,score+1
	move.b	d2,score
	; variablen init.
	clr.w	xadd
	clr.w	gang
	clr.w	rounds
	pea	initmtr		; sound	wieder init.
	bsr	setsound
	addq.l	#4,sp
	bsr	setmotor
	;
	move.w	#$2700,sr
	move.l	#vbl,$70
	move.w	#$2300,sr
	movem.l	(sp)+,d0-a6
	bra	reinit
nocrash:
	; strasse nÑher	holen
	move.w	speed,d0
	cmp.w	randtab2,d0	    ; stillstand?
	beq	pl2
	tst.w	d0
	beq	pl5
	subq.w	#1,speed
	bra	pl2
pl5:
	move.w	getfak,speed
	addq.l	#1,a0
	bra	pl2


endoftr:
	subq.w	#1,nrlaps1	; alle laps schon gefahren?
	bne	nextlap
	;
	move.w	#$2700,SR
	move.l	(sp)+,$70
	lea	$fffa07,a2
	move.w	reg79,d1
	movep.w	d1,0(a2)
	move.w	#$2300,SR
	;
	pea	initsnd
	bsr	setsound
	addq.l	#4,sp
	;
	lea	$ff8201,a1	; video	ram basis adr.
	move.b	screen+1,(a1)	; bildschirm ist screen
	move.b	screen+2,2(a1)
	move.l	screen,a1
	move.l	a1,$44e
	move.w	#7999,d0
end1:
	clr.l	(a1)+		; bildschirm lîschen
	dbf	d0,end1
	move.w	nrplay1,d0
	add.b	#"1",d0
	move.b	d0,aktplay	; aktuellen spieler anzeigen
	pea	gameover
	bsr	palprint	; Game over fÅr	player x ausgeben
	addq.l	#4,sp
	bsr	prepdigi
	clr.w	cnt1
end4:
	btst	#7,joystat	; knopfdruck?
	bne	end3
	subq.w	#1,cnt1
	bpl	end4
	move.w	#4000,cnt1
	lea	$ff8240,a0
	move.w	8(a0),d0
	move.l	4(a0),6(a0)
	move.w	2(a0),4(a0)
	move.w	d0,2(a0)
	move.w	18(a0),d0
	move.l	20(a0),18(a0)
	move.w	24(a0),22(a0)
	move.w	d0,24(a0)
	bra	end4
end3:
	bsr	resettim
	move.w	nrplay1,d0
	lea	plscore,a0
	lsl.w	#1,d0
	move.w	score,0(a0,d0)
	addq.w	#1,nrplay1	; schon	alle spieler durch?
	move.w	nrplay1,d0
	cmp.w	nrplayer,d0
	bne	end2
	;
	move.l	screen,$44e	; logical screen wieder	normal setzen
	move.b	screen+2,$ff8203
	move.b	screen+1,$ff8201
	; hiscores anzeigen
	bsr	calc_hi		; schauen, ob sich hiscores Ñndern
	bsr	show_hi
	;
abort:
	move.w	#$20,-(sp)	; wieder in USER gehen
	trap	#1
	addq.l	#6,sp
	bsr	mouseon
	pea	pic+2		; alte palette wieder setzen
	move.w	#6,-(sp)
	trap	#$e
	addq.l	#6,sp
	rts


; ------------ unteroutinen fÅr	das mainplay -----------------

joyirq:	; routine, die die daten vom joystick verarbeitet
	cmp.b	#$ff,(a0)	; nur joystick 1
	bne	joyirq1
	move.b	2(a0),joystat
joyirq1:
	rts


setsky:
	lea	bitscene,a0
	move.l	screen,a1
	move.l	screen2,a2
	move.w	#39,d0
prep6:
	move.l	(a0)+,d7
	move.w	#38,d1
	move.l	a1,a3
	move.l	a2,a4
prep6a:
	move.l	d7,(a3)
	move.l	d7,(a4)
	add.l	#160,a3
	add.l	#160,a4
	dbf	d1,prep6a
	addq.l	#4,a1
	addq.l	#4,a2
	dbf	d0,prep6
	rts


setsound:	; schreibt string (auf stack) in soundchip (ende = -1)
	clr.b	$484
	lea	$ff8800,a0
	move.l	4(sp),a1
ton1:
	move.b	(a1)+,d0
	bmi	end
	move.b	(a1)+,d1
	move.b	d0,(a0)
	cmp.b	#7,d0
	beq	spezial
	move.b	d1,2(a0)
	bra	ton1
spezial:
	move.b	(a0),d0
	and.b	#%11000000,d0
	or.b	d1,d0
	move.b	d0,2(a0)
	bra	ton1
end:
	rts


setmotor:	; nur 1/2 stimmen verwenden
	; motorgerÑusch
	lea	gangsnd,a2
	move.w	gang,d0
	lsl.w	#2,d0
	move.l	0(a2,d0),a2
	move.w	#3,d0
	sub.w	rounds,d0
	lsl.w	#1,d0
	lea	$ff8800,a3
	move.w	0(a2,d0),d0
	move.b	#0,(a3)
	move.b	d0,2(a3)
	sub.b	#40,d0
	move.b	#2,(a3)
	move.b	d0,2(a3)
	lsr.w	#8,d0
	move.b	#1,(a3)
	move.b	d0,2(a3)
	move.b	#3,(a3)
	move.b	d0,2(a3)
	rts


setgang:	; gibt gangschaltung aus
	lea	datascr1+20160,a3
	clr.l	d0
	move.w	gang,d0
	lsl.w	#3,d0		; mal 8
	add.l	d0,a3
	move.l	a3,-(sp)
	move.w	#7,-(sp)
	move.w	#186,-(sp)
	move.w	#207,-(sp)
	bsr	set16spr
	add.l	#10,sp
	rts


speedo:	; displays the right sprite on screen
	clr.l	d0
	move.w	randtab2,d0
	sub.w	getfak,d0
	lea	datascr1,a3
	add.l	#1600,a3
	cmp.w	#10,d0		; in nÑchste zeile ( 13	spr. in	linie)
	blt	speedo1
	add.l	#2400,a3
	sub.w	#10,d0
speedo1:
	lsl.w	#4,d0		; x16
	add.l	d0,a3
	move.l	a3,-(sp)
	move.w	#14,-(sp)
	move.w	#158,-(sp)
	move.w	#201,-(sp)
	bsr	set16spr
	add.l	#10,sp
	addq.l	#8,a3
	move.l	a3,-(sp)
	move.w	#14,-(sp)
	move.w	#158,-(sp)
	move.w	#217,-(sp)
	bsr	set16spr
	add.l	#10,sp
	rts


; score	aktualisieren und anzeigen
setscore:
	addq.w	#1,scorecnt
	cmp.w	#3,scorecnt    ; muss score erniedrigt werden?
	ble	noscore
	clr.w	scorecnt
	movem.l	d0-a6,-(sp)
	; score	erniedrigen
	moveq.l	#2,d0		; um zwei decremieren
	moveq.l	#0,d3
	move.b	score+1,d1
	move.b	score,d2
	sbcd	d0,d1
	sbcd	d3,d2
	bcc	noext2		; nicht	0000 unterlaufen!
	clr.w	d1
	clr.w	d2
noext2:
	move.b	d1,score+1
	move.b	d2,score
	move.w	d1,-(sp)	; merken
	; zahlen in sprites wandeln
	move.w	d2,d0		; zahl (zehner - einer in hexa)
	bsr	dezspr		; spritezahlen ausgeben
	; sprites ausgeben
	pea	sprwork1	; adr. der gewandelten zahlen
	move.w	#9,-(sp)	; hîhe des sprites
	move.w	#161,-(sp)	; y
	move.w	#89,-(sp)      ; x
	bsr	set16spr
	add.l	#10,sp
	move.w	(sp)+,d0	; zahl (zehner - einer in hexa)
	bsr	dezspr		; spritezahlen ausgeben
	; sprites ausgeben
	pea	sprwork1	; adr. der gewandelten zahlen
	move.w	#9,-(sp)	; hîhe des sprites
	move.w	#161,-(sp)	; y
	move.w	#89+16,-(sp)   ; x
	bsr	set16spr
	add.l	#10,sp
	;
	movem.l	(sp)+,d0-a6
noscore:
	rts


; errechnet aus	zahl in	d0.w die sprites -> sprwork1
dezspr:
	lea	datascr1,a0	; hier stehen die zahlen
	move.l	a0,a1
	move.w	d0,d7
	and.w	#$f0,d0
	lsr.w	#1,d0		; zehnerpotenz	(x8 auf	wortstart)
	add.w	d0,a0
	lea	sprwork1,a2	; basis	des arbeitspeichers #1
	move.l	a2,a3
	move.w	#9,d1
dezspr1:
	move.l	(a0)+,(a2)+
	move.l	(a0),(a2)
	add.l	#160-4,a0
	add.l	#160-4,a2
	dbf	d1,dezspr1
	and.w	#$0f,d7
	lsl.w	#3,d7		; einerpotenz (x8 auf wortstart)
	add.w	d7,a1
	move.w	#9,d1
dezspr2:
	move.l	(a1)+,d0
	lsr.l	#8,d0
	or.l	d0,(a3)+
	move.l	(a1),d0
	lsr.l	#8,d0
	or.l	d0,(a3)
	add.l	#160-4,a1
	add.l	#160-4,a3
	dbf	d1,dezspr2
	rts

; lenkrad anzeigen
setsteer:
	move.w	joydir,d0
	ext.l	d0
	divs	#4,d0
	cmp.w	oldjdir,d0	; nur bei Ñnderung neu zeichnen
	beq	nosteer
	move.w	d0,oldjdir
	tst.w	d0		; pos. oder neg.
	bmi	steerneg
	cmp.w	#4,d0		; max. zahl der	st.rÑder
	ble	steerok
	subq.w	#1,oldjdir
	subq.w	#4,joydir
	bra	nosteer
steerneg:
	cmp.w	#-4,d0
	bge	steerok
	addq.w	#1,oldjdir
	addq.w	#4,joydir
	bra	nosteer
steerok:
	movem.l	d0-a6,-(sp)
	lea	datascr1+6400,a0	; basis	der steuerrÑder
	lea	steertab,a1
	addq.w	#4,d0
	lsl.w	#2,d0		; lwort	tabelle
	add.l	0(a1,d0),a0	; rel. offset dazuaddieren
	; steuerradsprites darstellen
	move.l	a0,-(sp)	; adr. des steuerrades
	move.w	#42,-(sp)	 ; hîhe	des sprites
	move.w	#154,-(sp)	; y
	move.w	#132,-(sp)	; x
	bsr	set16spr
	add.l	#10,sp
	addq.l	#8,a0
	move.l	a0,-(sp)	; adr. des steuerrades
	move.w	#42,-(sp)	 ; hîhe	des sprites
	move.w	#154,-(sp)	; y
	move.w	#132+16,-(sp)	   ; x
	bsr	set16spr
	add.l	#10,sp
	addq.l	#8,a0
	move.l	a0,-(sp)	; adr. des steuerrades
	move.w	#42,-(sp)	 ; hîhe	des sprites
	move.w	#154,-(sp)	; y
	move.w	#132+32,-(sp)	   ; x
	bsr	set16spr
	add.l	#10,sp
	addq.l	#8,a0
	move.l	a0,-(sp)	; adr. des steuerrades
	move.w	#42,-(sp)	 ; hîhe	des sprites
	move.w	#154,-(sp)	; y
	move.w	#132+48,-(sp)	   ; x
	bsr	set16spr
	add.l	#10,sp
	movem.l	(sp)+,d0-a6
nosteer:
	rts

; --------------- vbl routine zum scrollen des hintergrundes -----------
vbl:
	movem.l	d0-a6,-(sp)
	move.w	SR,-(sp)
	lea	$ff8240,a6
	;
	move.w	aktscene,d0
	lsl.w	#2,d0
	lea	paladdr,a0
	move.l	0(a0,d0),a0
	movem.l	(a0),d0-d7	 ; palette der scenerie
	movem.l	d0-d7,(a6)
	; errechnen des	starts der scenerie
	move.w	scroll,d0	 ; ablenkung (faktor fÅr scrollen)
	bpl	vblpos
	neg.w	d0
vblneg:
	cmp.w	#320,d0
	blt	vbln1
	sub.w	#320,d0
	bra	vblneg
vbln1:
	move.w	d0,d2
	lsr.w	#1,d0		; delta	x/2 and	0xfff0
	and.l	#$fff8,d0
	and.w	#$f,d2		; start	bit (0-15)
	move.w	#15,d1
	sub.w	d2,d1
	lsl.w	#2,d1		; fÅr lwort tab
	lea	bitoffs,a0
	move.l	0(a0,d1),a0	; startadresse der scenerie
	move.l	a0,a2
	addq.l	#8,d0
	bra	vblok
vblpos:
	cmp.w	#320,d0
	blt	vblp1
	sub.w	#320,d0
	bra	vblpos
vblp1:
	move.w	d0,d1
	lsr.w	#1,d0		; delta	x/2 and	0xfff0
	and.l	#$fff8,d0
	move.w	#160,d2
	sub.w	d0,d2
	move.w	d2,d0
	and.l	#$f,d1		; start	bit (0-15)
	lsl.w	#2,d1		; fÅr lwort tab
	lea	bitoffs,a0
	move.l	0(a0,d1),a0	; startadresse der scenerie
	move.l	a0,a2
vblok:
	add.l	d0,a0
	move.w	#160,d1
	sub.w	d0,d1
	move.w	d0,d3
	lsr.w	#3,d3
	lsr.w	#3,d1		; /8 ->	anzahl der loops mit je	2 lws
	move.w	#31,d5		; 32 zeilen
	move.l	$44e,a1
	move.w	#$100,$ff8240
	add.l	#39*160,a1	; bildschirmadresse
vbl7:
	move.w	d1,d2
	move.w	d3,d4
	tst.w	d2
	beq	vbl6a
	subq.w	#1,d2
vbl5:
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	dbf	d2,vbl5
vbl6a:
	move.l	a2,a0
	tst.w	d4
	beq	vbl6b
	subq.w	#1,d4
vbl6:
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	dbf	d4,vbl6
vbl6b:
	add.l	#160,a2
	move.l	a2,a0
	add.l	d0,a0
	dbf	d5,vbl7
	;
	;
	movem.l	playpal+2,d3-d7/a2-a4
	moveq.l	#0,d0
	lea	$ff8201,a0	; basis	videoram
	movep.w	0(a0),d0
	lsl.l	#8,d0
	add.l	#71*160,d0	; beginn des tracks
	addq.l	#6,a0		; basis	videocnt
	move.w	waitcnt,d2	; cnt, wenn leer rÅcksprung
vbl1:
	subq.w	#1,d2
	beq	vbl3
	movep.w	0(a0),d1	; auf diese zeile warten
	cmp.w	d0,d1
	blt	vbl1
vbl3:
	movem.l	d3-d7/a2-a4,(a6)
	move.w	(sp)+,SR
	movem.l	(sp)+,d0-a6
leervbl:
	rte


; explusion sound timer	anschalten
settimer:
	pea	initdat
	bsr	setsound
	addq.l	#4,sp
	move	#$2700,sr
	lea	$fffa00,a1
	move.b	$f(a1),reg0f
	move.b	$b(a1),reg0b
	move.b	$13(a1),reg13
	move.b	$7(a1),reg07
	move.b	$19(a1),reg19
	move.b	$17(a1),reg17
	bclr	#5,$f(a1)
	bclr	#5,$b(a1)
	bset	#5,$13(a1)
	bset	#5,$7(a1)
	move.b	#1,$19(a1)		; vorteiler 4
	move.b	#$38,$1f(a1)
	ori.b	#$08,$17(a1)  ;	set SEI	mode in	Vector Reg.
	move.l	$134,timerirq
	move.l	#playexpl,$134
	clr.l	takt1
	clr.l	taktend1
	clr.w	tloop1
	clr.w	takptr1
	move.w	#$2300,sr
	rts

resettim:
	move.w	#$2700,sr
	move.l	timerirq,$134
	lea	$fffa00,a1
	move.b	reg0f,$f(a1)
	move.b	reg0b,$b(a1)
	move.b	reg13,$13(a1)
	move.b	reg07,$7(a1)
	move.b	reg19,$19(a1)
	move.b	reg17,$17(a1)
	move.w	reg79,d1
	movep.w	d1,7(a1)
	move.w	#$2300,sr
	rts

; -------------	timer irq. routine -----------------
playexpl:
	movem.l	d0-a6,-(sp)
	;
	subq.w	#1,tloop1
	cmp.w	#-1,tloop1
	bne	playlop1
play1:
	clr.w	d6
	clr.w	d5
	move.l	takt1,a1
	cmp.l	taktend1,a1
	bne	play1a
	bsr	nxttakt
	move.l	takt1,a1
play1a:
	move.b	(a1)+,d5
	move.l	a1,takt1
	move.b	d5,d6
	lsr.b	#4,d6
	cmp.w	#$0f,d6
	bne	play1b
	subq.w	#1,d6
play1b:
	and.b	#$0f,d5
	move.w	d6,tloop1
	move.w	d5,note1
playlop1:
	lea	$ff8800,a0
	move.w	note1,d5
	move.b	#8,(a0)
	move.b	d5,2(a0)
	move.b	#9,(a0)
	move.b	d5,2(a0)
	move.b	#10,(a0)
	move.b	d5,2(a0)
	;
	movem.l	(sp)+,d0-a6
	bclr	#5,$fffa0f
	rte

; holt neuen takt fÅr jede stimme
nxttakt:
	clr.l	d0
gett1:
	move.w	takptr1,d0
	lea	t1,a1
	add.l	d0,a1
	move.b	(a1),d0
	cmp.b	#-1,d0
	bne	n1
	clr.w	note1
	clr.w	takptr1
	bra.s	gett1
n1:
	clr.w	tloop1
	lsl.w	#2,d0		; x4
	lea	taktable,a1
	move.l	0(a1,d0),a2
	add.l	#explsnd,a2
	move.l	a2,takt1
	move.l	4(a1,d0),a2
	add.l	#explsnd,a2
	move.l	a2,taktend1
	addq.w	#1,takptr1
	rts



playdigi:	; spielt digisound, schaltet ab
	bsr	prepdigi
	move.w	#7,-(sp)
	trap	#1
	addq.l	#2,sp
	rts

; digital sound	timer anschalten
prepdigi:
	pea	initdat
	bsr	setsound
	addq.l	#4,sp
	move	#$2700,sr
	lea	$fffa00,a1
	move.b	$f(a1),reg0f
	move.b	$b(a1),reg0b
	move.b	$13(a1),reg13
	move.b	$7(a1),reg07
	move.b	$19(a1),reg19
	move.b	$17(a1),reg17
	bclr	#5,$f(a1)
	bclr	#5,$b(a1)
	bset	#5,$13(a1)
	bset	#5,$7(a1)
	move.b	#1,$19(a1)		; vorteiler 4
	move.b	#$48,$1f(a1)
	ori.b	#$08,$17(a1)  ;	set SEI	mode in	Vector Reg.
	move.l	$134,timerirq
	move.l	#playmus,$134
	clr.l	takt2
	clr.l	taktend2
	clr.w	takptr2
	movep.w	7(a1),d1
	move.w	d1,reg79
	move.w	#$2300,sr
	rts

; -------------	timer irq. routine -----------------
playmus:
	movem.l	d0-a6,-(sp)
	bsr	playmus2
	movem.l	(sp)+,d0-a6
	bclr	#5,$fffa0f
	rte

playmus2: ; spielroutine, nicht	unbedingt irq-zwang!
	;
	move.l	takt2,a1
	cmp.l	taktend2,a1
	bne	play2a
	bsr	nxttakt2
	move.l	takt2,a1
play2a:
	move.b	(a1)+,d5
	move.l	a1,takt2
	lea	loudtab,a1
	and.w	#$fc,d5
	move.w	d5,d1
	lsl.w	#1,d1
	add.w	d1,d5
	movem.l	0(a1,d5.w),d1-d3
	add.w	#$300,d1
	add.w	#$300,d2
	add.w	#$300,d3		; etwas	lauter
	movem.l	d1-d3,$ff8800
	;
	rts

; holt neuen takt fÅr jede stimme
nxttakt2:
	clr.l	d0
gett2:
	move.w	takptr2,d0
	lea	t2,a1
	add.l	d0,a1
	move.b	(a1),d0
	cmp.b	#-1,d0
	bne	n2
	clr.w	takptr2
	bra.s	gett2
n2:
	lsl.w	#2,d0		; x4
	lea	taktabl2,a1
	move.l	0(a1,d0),a2
	add.l	#digisnd,a2
	move.l	a2,takt2
	move.l	4(a1,d0),a2
	add.l	#digisnd,a2
	move.l	a2,taktend2
	addq.w	#1,takptr2
	rts


asklaps:	; anzahl der laps holen
	move.l	screen,a0
	move.w	#7999,d0
askl1:
	clr.l	(a0)+		; bild lîschen
	dbf	d0,askl1
	move.w	#$2700,sr
	move.l	$70,timerirq	; zwischenspeicher
	clr.w	vbllcnt
	clr.w	vbllcnt1
	move.l	#lapvbl,$70
	move.w	#$2300,sr
	pea	askltxt
	bsr	palprint	; mit neuem font ausgeben
	addq.l	#4,sp
askl2:
	move.l	screen,a0
	add.l	#110*160,a0
	move.w	#1999,d0
askl3:
	clr.l	(a0)+		; bild lîschen
	dbf	d0,askl3
	move.w	nrlaps,d0
	add.w	#$30,d0
	move.b	d0,asciilap
	pea	askltxt1
	bsr	palprint
	addq.l	#4,sp
askl2a:
	btst	#7,joystat	; knopf	-> ende
	bne	asklend
	btst	#2,joystat	; left -> vermindern
	beq	asklrigt
	cmp.w	#1,nrlaps
	beq	askl2a
	subq.w	#1,nrlaps
	bra	askl2
asklrigt:
	btst	#3,joystat
	beq	askl2a
	cmp.w	#9,nrlaps
	beq	askl2a
	addq.w	#1,nrlaps
	bra	askl2
asklend:
	move.w	#$2700,sr
	move.l	timerirq,$70
	move.w	#$2300,sr
	rts

lapvbl:	; farbstufen durchscrollen
	movem.l	d0-a6,-(sp)
	move	sr,-(sp)
	subq.w	#1,vbllcnt1
	bpl	lapvbl2
	move.w	#5,vbllcnt1
	subq.w	#1,vbllcnt		; counter schon	abgelaufen?
	bmi	lapvbl1
	move.w	vbllcnt,d0
	lsl.w	#1,d0
	lea	vbllpal,a0
	move.w	0(a0,d0),$ff8240
	bra	lapvbl2
lapvbl1:
	move.w	#16,vbllcnt
lapvbl2:
	move	(sp)+,sr
	movem.l	(sp)+,d0-a6
	rte


askplay:	; anzahl der spieler holen
	move.l	screen,a0
	move.w	#7999,d0
askp1:
	clr.l	(a0)+		; bild lîschen
	dbf	d0,askp1
	move.w	#$2700,sr
	move.l	$70,timerirq	; zwischenspeicher
	clr.w	vblpcnt
	clr.w	vblpcnt1
	move.l	#playvbl,$70
	move.w	#$2300,sr
	pea	askptxt
	bsr	palprint	; mit neuem font ausgeben
	addq.l	#4,sp
askp2:
	move.l	screen,a0
	add.l	#110*160,a0
	move.w	#1999,d0
askp3:
	clr.l	(a0)+		; bild lîschen
	dbf	d0,askp3
	move.w	nrplayer,d0
	add.w	#$30,d0
	move.b	d0,asciplay
	pea	askptxt1
	bsr	palprint
	addq.l	#4,sp
askp2a:
	btst	#7,joystat	; knopf	-> ende
	bne	askpend
	btst	#2,joystat	; left -> vermindern
	beq	askprigt
	cmp.w	#1,nrplayer
	beq	askp2a
	subq.w	#1,nrplayer
	bra	askp2
askprigt:
	btst	#3,joystat
	beq	askp2a
	cmp.w	#4,nrplayer	; max. vier spieler
	beq	askp2a
	addq.w	#1,nrplayer
	bra	askp2
askpend:
	move.w	#$2700,sr
	move.l	timerirq,$70
	move.w	#$2300,sr
	rts

playvbl: ; farbstufen durchscrollen
	movem.l	d0-a6,-(sp)
	move	sr,-(sp)
	subq.w	#1,vblpcnt1
	bpl	pvbl2
	move.w	#5,vblpcnt1
	subq.w	#1,vblpcnt		; counter schon	abgelaufen?
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

palprint:	; ptr auf text auf stack!
	movem.l	prpal+4,d1-d7
	movem.l	d1-d7,$ff8244
	move.w	prpal+2,$ff8242
	move.l	4(sp),a0
	move.w	#4,prntpal
	move.w	#0,d6
	move.w	#0,d7
pr2:
	move.w	#3,d0
	move.w	prntpal,prntcol		; startwert fÅr	col
	clr.w	d5
	move.b	(a0)+,d5
	beq	prquit
	cmp.b	#$d,d5
	beq	cr
        cmp.b   #'"',d5
	bne.s	pr3
	move.w	#4,prntpal
	bra.s	pr2
pr3:	cmp.w	#'!',d5
	bne.s	pr1
	move.w	#8+4,prntpal
	bra.s	pr2
pr1:
	cmp.b	#$20,d5			; keine	steuerkodes
	blt	pr2
	bsr	prprint
	add.w	#1 ,d6
	add.w	#1 ,d7
	sub.w	#1,prntcol
	dbf	d0,pr1

	add.w	#5 ,d6
	sub.w	#4,d7
	cmp.w	#320,d6
	blt	pr2
cr:	clr.w	d6
	move.w	#8+4,prntpal
	add.w	#12,d7
	cmp.w	#188,d7
	blt	pr2

	movem.l	d0-a7,saver
	move.w	#7,-(sp)
	trap	#1
	movem.l	saver,d0-a7

	clr.w	d6
	clr.w	d7
	move.l	screen,a6
	move.w	#7999,d0
prclear:clr.l	(a6)+
	dbf	d0,prclear
	bra	pr2
prquit:
	rts


hiprint:	; gibt text wie	palprint bloss ohne palettenÑnderung
	move.l	4(sp),a0
	move.w	#12,prntpal
	move.w	#0,d6
	move.w	#0,d7
hpr2:
	move.w	#3,d0
	move.w	prntpal,prntcol		; startwert fÅr	col
	clr.w	d5
	move.b	(a0)+,d5
	beq	hprquit
	cmp.b	#$d,d5
	beq	hcr
hpr1:
	cmp.b	#$20,d5			; keine	steuerkodes
	blt	hpr2
	bsr	prprint			; ausgeben
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



prprint:
	movem.l	d0-a6,saver
	move.l	varhead,a0
	move.l	fonthead,a2
	move.w	d5,d0			; zeichen nach d0
	move.w	prntcol,106(a0)		; farbe	15 als vordergrund
	move.l	76(a2),a5		; anfang bitmuster der chars
	move.l	a5,84(a0)
	move.w	80(a2),a5
	move.w	a5,88(a0)
	sub.w	36(a2),d0
	move.l	72(a2),a1
	lsl.w	#1,d0			; worttabelle
	move.w	0(a1,d0),a5
	move.w	a5,72(a0)
	clr.w	74(a0)
	move.w	d6,76(a0)		; x-position
	move.w	d7,78(a0)		; y-position
	addq.w	#2,d0			; nÑchster char
	move.w	0(a1,d0),d0
	sub.w	72(a0),d0
	move.w	d0,80(a0)
	move.w	82(a2),a5
	move.w	a5,82(a0)
	move.w	#$8000,64(a0)

	dc.w	$a008
	movem.l	saver,d0-a6
	rts

init_pr:
	dc.w	$a000			; a000 aufrufen
	move.l	a0,linetab
	move.w	#1,d1			; fontnummer
	lsl.w	#2,d1			; mal 2
	move.l	0(a1,d1),fonthead	; adr. des fontheaders n. a2
	move.l	a0,varhead
	move.w	#1,36(a0)		; mode = overwrite
	move.w	#0,114(a0)		; farbe	0 als hintergrund
	move.w	#0,102(a0)		; scaling ausschalten
	move.w	#%00000000,90(a0)	; outlined
	clr.w	98(a0)
	clr.w	100(a0)
	clr.w	104(a0)			; keine	drehung
	move.w	#1,70(a0)		; kein proportional
	clr.w	54(a0)			; kein clipping
	move.l	#bitscene,108(a0)	; buffer fÅr special effects
	move.w	#$40,112(a0)		; pointer in buffer fÅr	scaling
	rts

; schaut, ob einer der spieler eintragen kann
calc_hi:
	bsr	prepdigi		; digital sound	einschalten
	move.w	#3,d7			; 4 durchgÑnge
	clr.b	sortfl
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


; testet bcd.l in d0 mit eintrÑgen in hiscore liste
; D0-> 1,2,3,4/	D1 -> "1","2","3","4"
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
	bhi	getscore	; ok->grîsser
	addq.w	#1,d2
	cmp.w	#6,d2		; schon	alle scores durch?
	blt	tstsc1
notlaps:
	rts
getscore:
	move.w	d2,work1	; rank des spielers
	move.l	screen,a2
	move.w	#7999,d5
gets1:	clr.l	(a2)+		; bildschirm lîschen
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
	; einfÅgen
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
	move.w	#22,d0		; 23 zeichen Åbertragen
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
tsts4:	; auffÅllen mit	punkten
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
	sub.l	#hiscr,a4		; lÑnge
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


getname:
	lea	placetxt,a0
	bsr	print
	lea	curson,a0
	bsr	print
	lea	input2,a6     ;	hinter dem namen
	clr.b	(a6)
getn2:
	move.w	#7,-(sp)
	trap	#1
	addq.l	#2,sp
	cmp.b	#13,d0		; return gedrÅckt?
	beq	getn1
	cmp.b	#8,d0		; backspace ?
	bne	getn3
	cmp.l	#input2,a6	 ; bei bs schon	anfang erreicht?
	beq	getn2
	subq.l	#1,a6
	clr.b	(a6)
	lea	crsleft,a0
	bsr	print
	bra	getn2
getn3:
	cmp.l	#input2+16,a6	 ; nur 16 zeichen erlaubt
	bge	getn2
	cmp.b	#' ',d0
	blt	getn2
	cmp.b	#'z',d0
	bhi	getn2
	move.b	d0,(a6)+
	clr.b	(a6)
	lea	-1(a6),a0
	bsr	print
	bra	getn2
getn1:
	lea	cursoff,a0
	bra	print


; hiscores mit musik anzeigen
show_hi:
	move.l	screen,a6
	sub.l	#$22,a6
	lea	hiscoren,a5
	lea	$22,a4
	bsr	load		; hiscorebild laden
	addq.l	#2,a6
	move.l	a6,-(sp)
	move.w	#6,-(sp)
	trap	#$e		; palette des titelbildes anzeigen
	addq.l	#6,sp
	move.l	screen,a6
	sub.l	#$22,a6
	lea	hiscoren,a5
	lea	$fffff,a4
	bsr	load		; hiscorebild laden
	pea	hiscore		; text ausgeben
	bsr	hiprint
	addq.l	#4,sp
waitjoy:
	btst	#7,joystat
	beq	waitjoy
	bra	resettim

decspeed:	; speed	vermindern
	tst.w	rounds
	beq	decs1
	move.w	randtab2,d0
	cmp.w	getfak,d0	; schon	im stillstand?
	beq	decs2
	subq.w	#1,rounds
	addq.w	#1,getfak
	move.w	getfak,speed
	bsr	setmotor
	bsr	speedo
decs2:
	tst.w	speedfak
	beq	decs1
	subq.w	#1,speedfak
decs1:
	rts


;-------------------------------------------------------------------
.data
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

hiscr:
	.dc.b	13,13,13,13,13,13,13
	.dc.b	"    1st...Martin Backschat..0000",13,13
	.dc.b	"    2nd...(c) 1987 by     ..0000",13
	.dc.b	"    3rd...Prism PLC       ..0000",13
	.dc.b	"    4th...Conversion by   ..0000",13
	.dc.b	"    5th...Capital Software..0000",13
	.dc.b	"    6th...Developments Ltd..0000",0
hiend:
hiscore:
	.dc.b	13,13,13,13,13,13,13
	.dc.b	"    1st...Martin Backschat..0000",13,13
	.dc.b	"    2nd...(c) 1987 by     ..0000",13
	.dc.b	"    3rd...Prism PLC       ..0000",13
	.dc.b	"    4th...Conversion by   ..0000",13
	.dc.b	"    5th...Capital Software..0000",13
	.dc.b	"    6th...Developments Ltd..0000",0

hitab:	; offsets der namen innerhalb der lister von 1 beginnend
	.dc.w	17,51,84,117,150,183

clrcolor:
	.dc.w	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

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

mauscurs:
	.dc.b	$a,25,25
.even
mauson:
	.dc.b	8
.even
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

aespb:
	.dc.l	contrl,global,intin,intout,addrin,addrout
vdipb:
	.dc.l	contrl,intin,ptsin,intout,ptsout
.even
patptr:
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
playtab:
	.dc.l	bau1,bau2,bau3,bau4,bau5,bau6,bau7,bau8,bau9
	.dc.l	bau10,bau11,bau12,bau13,bau14,bau15,bau16,bau17,bau18

	;	      5	 1  6
	;	       \ | /		fÅr einfahrt und ausfahrt
	;	    4--	*** --2
	;	       / | \
	;	      8	 3  7

offs:	;     0	  1    2   3  4	 5   6	 7   8
	.dc.w 0, -18, 1, 18,-1,-19,-17,	19, 17

	;	ausf1 -	ausf2
bau1:
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

fakttab:	; anzahl der zeile-1  (normal =	0)   70	werte
	.dc.w	8,6,4,3,2,2,1,1,1,1
	.dc.w	1,1,0,0,0,0,0,0,0,0
	.dc.w	0,0,0,0,0,0,0,0,0,0
	.dc.w	0,0,0,0,0,0,0,0,0,0
	.dc.w	0,0,0,0,0,0,0,0,0,0

randtab:	; anzahl, wielang farbe	beibehalten werden soll	(in pixels)
	.dc.b	15,15,15,15,14,14,14,14,13,13
	.dc.b	13,13,12,12,12,12,11,11,11,11
	.dc.b	10,10,10,10, 9,	9, 9, 9, 8, 8
	.dc.b	 7, 7, 7, 7, 6,	6, 6, 6, 5, 5
	.dc.b	 5, 5, 4, 4, 4,	4, 3, 3, 3, 3
	.dc.b	 2, 2, 2, 2, 1,	1, 1, 1, 0, 0
	.dc.b	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
.even

joyon:
	.dc.b	$12,$14
.even
joyoff:
	.dc.b	$15,$08
.even
wiese:	; farbnr. 14
	.dc.l	$0000ffff,$ffffffff	; 16 pixels
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff
	.dc.l	$0000ffff,$ffffffff

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

initmtr:
	.dc.b	0,255,1,15,2,191,3,15,7,%011100,8,12,9,12,10,15
	.dc.b	-1,-1
.even

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

steertab:
	.dc.l	6880+96,6880+64,6880+32,6880
	.dc.l	128,96,64,32,0

signtab:	; startadr. der	schilderstarts
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

bitoffs:	; startadr. der	16 verschobenen	sceneries
	.dc.l	bitscene,bitscene+5120,bitscene+10240
	.dc.l	bitscene+15360,bitscene+20480,bitscene+25600
	.dc.l	bitscene+30720,bitscene+35840,bitscene+40960
	.dc.l	bitscene+46080,bitscene+51200,bitscene+56320
	.dc.l	bitscene+61440,bitscene+66560,bitscene+71680
	.dc.l	bitscene+76800

scenaddr:
	.dc.l	signscr2+16800,signscr2+26880,signscr2+21760

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

initsnd:
	.dc.b	0,0, 1,0, 2,0, 3,0, 4,0, 5,0, 6,0, 7,%111111
	.dc.b	8,0, 9,0,10,0,11,0,12,0,13,0,-1,-1
.even
initdat:    .dc.b	0,255,1,255,2,255,3,255,4,255,5,255,6,0,7,$3f
	    .dc.b	8,0,9,0,10,0,-1,0
.even
randsnd:
	.dc.b	4,55,5,9,6,20,10,16,11,80,12,0,13,12,-1,-1
.even

t1:
	.dc.b	0,0,0,0,0,-1
.even
t2:
	.dc.b	0,0,0,0,0,0, 1,1, 2,2, 3,3, 4,4, 5,5, 4,4, 3,3
	.dc.b	2,2, 1,1, 0,0, 2,2, 3,3, 2,2, 3,3, 4,4,	5,5, 4,4
	.dc.b	5,5, 4,4, 3,3, 2,2, 1,1, -1,0
.even
taktable:
	.dc.l	1,$16f5,0,0

taktabl2:
	.dc.l	4,3460,16280,31510,46595,61730,76870

prpal:		.dc.w $000,$445,$334,$223,$112,$666,$666,$666
		.dc.w $666,$444,$333,$222,$111,$666,$666,$666

nrlaps:
	.dc.w	1	; normal 1 laps
nrplayer:
	.dc.w	1

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

faktab:
	.dc.b	7 ,8 ,9	,11,13,18,24,30
	.dc.b	36,43,50,57,64,71,78,86
.even
faktab2:
	.dc.b	14,16,18,22,26,36,48,60
	.dc.b	72,86,100,114,128,142,156,172
.even

; ------------ nicht init. daten ------------------------------------
.bss
.even
contrl:
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

; -----
startcol:
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
screen:
	.ds.l	1
rez:
	.ds.w	1
pic:
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
playdat:
	.ds.b	200	; 18*11	daten fÅr spielfeld
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
joystat:
	.ds.b	1	; enthÑlt joystickdaten
.even
speed:
	.ds.w	1
getfak:
	.ds.w	1
xadd:
	.ds.w	1
speedfak:
	.ds.w	1
screen2:
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

scndscr:
	.ds.b	32000+256	; da auf 256 bytes geraden adr.	liegen muû
playseq:
	.ds.b	2000	; sollte eigentlich reichen
aktseq:
	.ds.b	6*6*162	      ;	sollte als akt.	streckendaten reichen
datascr1:
	.ds.b	32000
	.ds.b	$22		; fÅr ÅberflÅssige palette
signscr1:
	.ds.b	32000
	.ds.b	$22
signscr2:
	.ds.b	32000		; schilder und sceneries
filmpal:.ds.b	$22
film:
	.ds.b	32000
bitscene:
	.ds.b	81920		; 16 bitverschobene scenes
explsnd:
	.ds.b	$1700
digisnd:
	.ds.b	78000		; digital sound
