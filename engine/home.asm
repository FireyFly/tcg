; rst vectors
SECTION "rst00",ROM0[0]
	ret
SECTION "rst08",ROM0[8]
	ret
SECTION "rst10",ROM0[$10]
	ret
SECTION "rst18",ROM0[$18]
	jp RST18
SECTION "rst20",ROM0[$20]
	jp RST20
SECTION "rst28",ROM0[$28]
	jp RST28
SECTION "rst30",ROM0[$30]
	ret
SECTION "rst38",ROM0[$38]
	ret

; interrupts
SECTION "vblank",ROM0[$40]
	jp VBlankHandler
SECTION "lcdc",ROM0[$48]
	call $cacd
	reti
SECTION "timer",ROM0[$50]
	jp TimerHandler
SECTION "serial",ROM0[$58]
	jp SerialHandler
SECTION "joypad",ROM0[$60]
	reti

SECTION "romheader",ROM0[$100]
	nop
	jp Start

SECTION "start",ROM0[$150]
Start: ; 0150 (0:0150)
	di
	ld sp, $fffe
	push af
	xor a
	ld [rIF], a
	ld [rIE], a
	call ZeroRAM
	ld a, $1
	call BankswitchHome
	xor a
	call BankswitchRAM
	call BankswitchVRAM_0
	call DisableLCD
	pop af
	ld [wInitialA], a
	call DetectConsole
	ld a, $20
	ld [wTileMapFill], a
	call SetupVRAM
	call SetupLCD
	call SetupPalettes
	call SetupSound_T
	call SetupTimer
	call ResetSerial
	call CopyDMAFunction
	call SetupExtRAM
	ld a, BANK(Func_4000)
	call BankswitchHome
	ld sp, $e000
	jp Func_4000

VBlankHandler: ; 019b (0:019b)
	push af
	push bc
	push de
	push hl
	ld a, [hBankROM]
	push af
	ld hl, wReentrancyFlag
	bit 0, [hl]
	jr nz, .done
	set 0, [hl]
	ld a, [wVBlankOAMCopyToggle]
	or a
	jr z, .no_oam_copy
	call hDMAFunction    ; DMA-copy $ca00-$ca9f to OAM memory
	xor a
	ld [wVBlankOAMCopyToggle], a
.no_oam_copy
	; flush scaling/windowing parameters
	ld a, [hSCX]
	ld [rSCX], a
	ld a, [hSCY]
	ld [rSCY], a
	ld a, [hWX]
	ld [rWX], a
	ld a, [hWY]
	ld [rWY], a
	; flush LCDC
	ld a, [wLCDC]
	ld [rLCDC], a
	ei
	call $cad0
	call FlushPalettes
	ld hl, wVBlankCtr
	inc [hl]
	ld hl, wReentrancyFlag
	res 0, [hl]
.done
	pop af
	call BankswitchHome
	pop hl
	pop de
	pop bc
	pop af
	reti

TimerHandler: ; 01e6 (0:01e6)
	push af
	push hl
	push de
	push bc
	ei
	call SerialTimerHandler
	; only trigger every fourth interrupt ≈ 60.24 Hz
	ld hl, wCounterCtr
	ld a, [hl]
	inc [hl]
	and $3
	jr nz, .done
	; increment the 60-60-60-255-255 counter
	call IncrementCounter
	; check in-timer flag
	ld hl, wReentrancyFlag
	bit 1, [hl]
	jr nz, .done
	set 1, [hl]
	ld a, [hBankROM]
	push af
	ld a, BANK(SoundTimerHandler_Ext)
	call BankswitchHome
	call SoundTimerHandler_Ext
	pop af
	call BankswitchHome
	; clear in-timer flag
	ld hl, wReentrancyFlag
	res 1, [hl]
.done
	pop bc
	pop de
	pop hl
	pop af
	reti

; increment timer counter by a tick
IncrementCounter: ; 021c (0:021c)
	ld a, [wCounterEnable]
	or a
	ret z
	ld hl, wCounter
	inc [hl]
	ld a, [hl]
	cp 60
	ret c
	ld [hl], $0
	inc hl
	inc [hl]
	ld a, [hl]
	cp 60
	ret c
	ld [hl], $0
	inc hl
	inc [hl]
	ld a, [hl]
	cp 60
	ret c
	ld [hl], $0
	inc hl
	inc [hl]
	ret nz
	inc hl
	inc [hl]
	ret

; setup timer to 16384/68 ≈ 240.94 Hz
SetupTimer: ; 0241 (0:0241)
	ld b, $100 - 68
	; ld b, $bc
	call CheckForCGB
	jr c, .asm_250
	ld a, [rKEY1]
	and $80
	jr z, .asm_250
	ld b, $100 - 2*68
.asm_250
	ld a, b
	ld [rTMA], a
	ld a, rTAC_16384_HZ
	ld [rTAC], a
	ld a, $7
	ld [rTAC], a
	ret

; carry flag: 0 if CGB
CheckForCGB: ; 025c (0:025c)
	ld a, [wConsole]
	cp CONSOLE_CGB
	ret z
	scf
	ret

; wait for vblank
WaitForVBlank: ; 0264 (0:0264)
	push hl
	ld a, [wLCDC]
	bit 7, a
	jr z, .asm_275
	ld hl, wVBlankCtr
	ld a, [hl]
.asm_270
	halt
	cp [hl]
	jr z, .asm_270
.asm_275
	pop hl
	ret

; turn LCD on
EnableLCD: ; 0277 (0:0277)
	ld a, [wLCDC]    ;
	bit 7, a             ;
	ret nz               ; assert that LCD is off
	or $80               ;
	ld [wLCDC], a        ;
	ld [rLCDC], a        ; turn LCD on
	ld a, $c0
	ld [wFlushPaletteFlags], a
	ret

; wait for vblank, then turn LCD off
DisableLCD: ; 028a (0:028a)
	ld a, [rLCDC]        ;
	bit 7, a             ;
	ret z                ; assert that LCD is on
	ld a, [rIE]
	ld [wIE], a
	res 0, a             ;
	ld [rIE], a          ; disable vblank interrupt
.asm_298
	ld a, [rLY]          ;
	cp $91               ;
	jr nz, .asm_298      ; wait for vblank
	ld a, [rLCDC]        ;
	and $7f              ;
	ld [rLCDC], a        ;
	ld a, [wLCDC]        ;
	and $7f              ;
	ld [wLCDC], a        ; turn LCD off
	xor a
	ld [rBGP], a
	ld [rOBP0], a
	ld [rOBP1], a
	ld a, [wIE]
	ld [rIE], a
	ret

; set OBJ size: 8x8
Set_OBJ_8x8: ; 02b9 (0:02b9)
	ld a, [wLCDC]
	and $fb
	ld [wLCDC], a
	ret

; set OBJ size: 8x16
Set_OBJ_8x16: ; 02c2 (0:02c2)
	ld a, [wLCDC]
	or $4
	ld [wLCDC], a
	ret

; set Window Display on
Set_WD_on: ; 02cb (0:02cb)
	ld a, [wLCDC]
	or $20
	ld [wLCDC], a
	ret

; set Window Display off
Set_WD_off: ; 02d4 (0:02d4)
	ld a, [wLCDC]
	and $df
	ld [wLCDC], a
	ret

EnableInt_Timer: ; 02dd (0:02dd)
	ld a, [rIE]
	or $4
	ld [rIE], a
	ret

EnableInt_VBlank: ; 02e4 (0:02e4)
	ld a, [rIE]
	or $1
	ld [rIE], a
	ret

EnableInt_HBlank: ; 02eb (0:02eb)
	ld a, [rSTAT]
	or $8
	ld [rSTAT], a
	xor a
	ld [rIF], a
	ld a, [rIE]
	or $2
	ld [rIE], a
	ret

DisableInt_HBlank: ; 02fb (0:02fb)
	ld a, [rSTAT]
	and $f7
	ld [rSTAT], a
	xor a
	ld [rIF], a
	ld a, [rIE]
	and $fd
	ld [rIE], a
	ret

SetupLCD: ; 030b (0:030b)
	xor a
	ld [rSCY], a
	ld [rSCX], a
	ld [rWY], a
	ld [rWX], a
	ld [$cab0], a
	ld [$cab1], a
	ld [$cab2], a
	ld [hSCX], a
	ld [hSCY], a
	ld [hWX], a
	ld [hWY], a
	xor a
	ld [wReentrancyFlag], a
	ld a, $c3            ; $c3 = jp nn
	ld [$cacd], a
	ld [wVBlankFunctionTrampoline], a
	ld hl, wVBlankFunctionTrampoline + 1
	ld [hl], NopF & $ff  ;
	inc hl               ; load `jp NopF`
	ld [hl], NopF >> $8  ;
	ld a, $47
	ld [wLCDC], a
	ld a, $1
	ld [MBC3LatchClock], a
	ld a, $a
	ld [MBC3SRamEnable], a
NopF: ; 0348 (0:0348)
	ret

DetectConsole: ; 0349 (0:0349)
	ld b, CONSOLE_CGB
	cp GBC
	jr z, .asm_35b
	call DetectSGB
	ld b, CONSOLE_DMG
	jr nc, .asm_35b
	call InitSGB
	ld b, CONSOLE_SGB
.asm_35b
	ld a, b
	ld [wConsole], a
	cp CONSOLE_CGB
	ret nz
	ld a, CONSOLE_SGB
	ld [rSVBK], a
	call Func_07e7
	ret

; initialize the palettes (both monochrome and color)
SetupPalettes: ; 036a (0:036a)
	ld hl, wBGP
	ld a, $e4
	ld [rBGP], a
	ld [hli], a
	ld [rOBP0], a
	ld [rOBP1], a
	ld [hli], a
	ld [hl], a
	xor a
	ld [wFlushPaletteFlags], a
	ld a, [wConsole]
	cp CONSOLE_CGB
	ret nz
	ld de, wBufPalette
	ld c, $10
.asm_387
	ld hl, InitialPalette
	ld b, $8
.asm_38c
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .asm_38c
	dec c
	jr nz, .asm_387
	call FlushBothCGBPalettes
	ret

InitialPalette: ; 0399 (0:0399)
	RGB 28,28,24
	RGB 21,21,16
	RGB 10,10,08
	RGB 00,00,00

SetupVRAM: ; 03a1 (0:03a1)
	call FillTileMap
	call CheckForCGB
	jr c, .asm_3b2
	call BankswitchVRAM_1
	call .asm_3b2
	call BankswitchVRAM_0
.asm_3b2
	ld hl, $8000
	ld bc, $1800
.asm_3b8
	xor a
	ld [hli], a
	dec bc
	ld a, b
	or c
	jr nz, .asm_3b8
	ret

; fill VARM tile map banks with [wTileMapFill]
FillTileMap: ; 03c0 (0:03c0)
	call BankswitchVRAM_0
	ld hl, $9800
	ld bc, $0400
.asm_3c9
	ld a, [wTileMapFill]
	ld [hli], a
	dec bc
	ld a, c
	or b
	jr nz, .asm_3c9
	ld a, [wConsole]
	cp CONSOLE_CGB
	ret nz
	call BankswitchVRAM_1
	ld hl, $9800
	ld bc, $0400
.asm_3e1
	xor a
	ld [hli], a
	dec bc
	ld a, c
	or b
	jr nz, .asm_3e1
	call BankswitchVRAM_0
	ret

; zero work RAM & stack area ($C000-$EFFF, $FF80-$FF7F)
ZeroRAM: ; 03ec (0:03ec)
	ld hl, $c000
	ld bc, $2000
.asm_3f2
	xor a
	ld [hli], a
	dec bc
	ld a, c
	or b
	jr nz, .asm_3f2
	ld c, $80
	ld b, $70
	xor a
.asm_3fe
	ld [$ff00+c], a
	inc c
	dec b
	jr nz, .asm_3fe
	ret

Func_0404: ; 0404 (0:0404)
	ld a, $c0
	jr asm_411

Func_0408: ; 0408 (0:0408)
	or $80
	jr asm_411

Func_040c: ; 040c (0:040c)
	ld [wBGP], a
asm_40f
	ld a, $80
asm_411
	ld [wFlushPaletteFlags], a
	ld a, [wLCDC]
	rla
	ret c
	push hl
	push de
	push bc
	call FlushPalettes
	pop bc
	pop de
	pop hl
	ret

Set_OBP0: ; 0423 (0:0423)
	ld [wOBP0], a
	jr asm_40f

Set_OBP1: ; 0428 (0:0428)
	ld [wOBP1], a
	jr asm_40f

; flushes non-CGB palettes from [wBGP], [wOBP0], [wOBP1] as well as CGB
; palettes from [wBufPalette..wBufPalette+$1f] (BG palette) and
; [wBufPalette+$20..wBufPalette+$3f] (sprite palette).
;   only flushes if [wFlushPaletteFlags] is nonzero, and only flushes sprite
; palette if bit6 of that location is set.
FlushPalettes: ; 042d (0:042d)
	ld a, [wFlushPaletteFlags]
	or a
	ret z
	; flush grayscale (non-CGB) palettes
	ld hl, wBGP
	ld a, [hli]
	ld [rBGP], a
	ld a, [hli]
	ld [rOBP0], a
	ld a, [hl]
	ld [rOBP1], a
	ld a, [wConsole]
	cp CONSOLE_CGB
	jr z, flushPaletteCGB
flushPaletteDone
	xor a
	ld [wFlushPaletteFlags], a
	ret
flushPaletteCGB
	; flush BG palette (BGP)
	; if bit6 of [wFlushPaletteFlags] is set, flush OBP too
	ld a, [wFlushPaletteFlags]
	bit 6, a
	jr nz, FlushBothCGBPalettes
	ld b, $8
	call CopyPalette
	jr flushPaletteDone

FlushBothCGBPalettes: ; 0458 (0:0458)
	xor a
	ld b, $40
	; flush BGP $00-$1f
	call CopyPalette
	ld a, $8
	ld b, $40
	; flush OBP $00-$1f
	call CopyPalette
	jr flushPaletteDone

CopyPalette: ; 0467 (0:0467)
	add a
	add a
	add a
	ld e, a
	ld d, $0
	ld hl, $caf0
	add hl, de
	ld c, $68
	bit 6, a
	jr z, .asm_479
	ld c, $6a
.asm_479
	and $bf
	ld e, a
.asm_47c
	ld a, e
	ld [$ff00+c], a
	inc c
.asm_47f
	ld a, [rSTAT]
	and $2
	jr nz, .asm_47f
	ld a, [hl]
	ld [$ff00+c], a
	ld a, [$ff00+c]
	cp [hl]
	jr nz, .asm_47f
	inc hl
	dec c
	inc e
	dec b
	jr nz, .asm_47c
	ret

Func_0492: ; 0492 (0:0492)
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld c, a
	call Func_04cf
	jr .asm_49d
.asm_49b
	ld [de], a
	inc de
.asm_49d
	ld a, [hli]
	or a
	jr nz, .asm_49b
	ret

Func_04a2: ; 04a2 (0:04a2)
	call DisableLCD
	call FillTileMap
	xor a
	ld [$cac2], a
	ld a, [wConsole]
	cp CONSOLE_SGB
	ret nz
	call EnableLCD       ;
	ld hl, SGB_04bf      ; send SGB data
	call SendSGB         ;
	call DisableLCD      ;
	ret

SGB_04bf: ; 04bf (0:04bf)
INCBIN "baserom.gbc",$04bf,$04cf - $04bf

Func_04cf: ; 04cf (0:04cf)
	ld l, c
	ld h, $0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld c, b
	ld b, $98
	add hl, bc
	ld e, l
	ld d, h
	ret

; read joypad
ReadJoypad: ; 04de (0:04de)
	ld a, $20
	ld [rJOYP], a
	ld a, [rJOYP]
	ld a, [rJOYP]
	cpl
	and $f
	swap a
	ld b, a
	ld a, $10
	ld [rJOYP], a
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	cpl
	and $f
	or b
	ld c, a              ; joypad data
	cpl
	ld b, a
	ld a, [hButtonsHeld]
	xor c
	and b
	ld [hButtonsReleased], a
	ld a, [hButtonsHeld]
	xor c
	and c
	ld b, a
	ld [hButtonsPressed], a
	ld a, [hButtonsHeld]
	and $f
	cp $f
	jr nz, asm_522       ; handle reset
	call ResetSerial
Reset: ; 051b (0:051b)
	ld a, [wInitialA]
	di
	jp Start
asm_522
	ld a, c
	ld [hButtonsHeld], a
	ld a, $30
	ld [rJOYP], a
	ret

; clear joypad hmem data
ClearJoypad: ; 052a (0:052a)
	push hl
	ld hl, hDPadRepeat
	xor a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	pop hl
	ret

Func_0536: ; 0536 (0:0536)
.loop
	push af
	call Func_053f
	pop af
	dec a
	jr nz, .loop
	ret

Func_053f: ; 053f (0:053f)
	push af
	push hl
	push de
	push bc
	ld hl, $cad3
	call CallIndirect
	call WaitForVBlank
	call ReadJoypad
	call HandleDPadRepeat
	ld a, [$cad5]
	or a
	jr z, .asm_56d
	ld a, [hButtonsPressed]
	and $4
	jr z, .asm_56d
.asm_55e
	call WaitForVBlank
	call ReadJoypad
	call HandleDPadRepeat
	ld a, [hButtonsPressed]
	and $4
	jr z, .asm_55e
.asm_56d
	pop bc
	pop de
	pop hl
	pop af
	ret

; handle D-pad repeatcounter
HandleDPadRepeat: ; 0572 (0:0572)
	ld a, [hButtonsHeld]
	ld [hButtonsPressed2], a
	and $f0
	jr z, .asm_58c
	ld hl, hDPadRepeat
	ld a, [hButtonsPressed]
	and $f0
	jr z, .asm_586
	ld [hl], 24
	ret
.asm_586
	dec [hl]
	jr nz, .asm_58c
	ld [hl], 6
	ret
.asm_58c
	ld a, [hButtonsPressed]
	and $f
	ld [hButtonsPressed2], a
	ret

CopyDMAFunction: ; 0593 (0:0593)
	ld c, $83
	ld b, JumpToFunctionInTable - DMA
	ld hl, DMA
.asm_59a
	ld a, [hli]
	ld [$ff00+c], a
	inc c
	dec b
	jr nz, .asm_59a
	ret

; CopyDMAFunction copies this function to $ff83
DMA: ; 05a1 (0:05a1)
	ld a, $ca
	ld [rDMA], a
	ld a, $28
.asm_5a7
	dec a
	jr nz, .asm_5a7
	ret

; jumps to index a in pointer table hl
JumpToFunctionInTable: ; 05ab (0:05ab)
	add a
	add l
	ld l, a
	ld a, $0
	adc h
	ld h, a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp [hl]

; call function at [hl] if non-NULL
CallIndirect: ; 05b6 (0:05b6)
	push af
	ld a, [hli]
	or [hl]
	jr nz, .asm_5bd
	pop af
	ret
.asm_5bd
	ld a, [hld]
	ld l, [hl]
	ld h, a
	pop af
	; fallthrough
CallF: ; 05c1 (0:05c1)
	jp [hl]
; 0x5c2

INCBIN "baserom.gbc",$05c2,$0663 - $05c2

Func_0663: ; 0663 (0:0663)
	push bc
	ld bc, $d8f0
	call Func_0686
	ld bc, $fc18
	call Func_0686
	ld bc, $ff9c
	call Func_0686
	ld bc, $fff6
	call Func_0686
	ld bc, $ffff
	call Func_0686
	xor a
	ld [de], a
	pop bc
	ret

Func_0686: ; 0686 (0:0686)
	ld a, $2f
.asm_688
	inc a
	add hl, bc
	jr c, .asm_688
	ld [de], a
	inc de
	ld a, l
	sub c
	ld l, a
	ld a, h
	sbc b
	ld h, a
	ret
; 0x695

INCBIN "baserom.gbc",$0695,$06c3 - $0695

Func_06c3: ; 06c3 (0:06c3)
	push af
	ld a, [wLCDC]
	rla
	jr c, .asm_6d8
	pop af
	push hl
	push de
	push bc
	push af
	call Func_04cf
	pop af
	ld [de], a
	pop bc
	pop de
	pop hl
	ret
.asm_6d8
	pop af
	push hl
	push de
	push bc
	ld hl, $cac1
	push hl
	ld [hl], a
	call Func_04cf
	pop hl
	ld b, $1
	call MemcpyHLDE_hblank
	pop bc
	pop de
	pop hl
	ret
; 0x6ee

INCBIN "baserom.gbc",$06ee,$0709 - $06ee

Func_0709: ; 0709 (0:0709)
	jp MemcpyHLDE_hblank

CopyGfxData: ; 070c (0:070c)
	ld a, [wLCDC]
	rla
	jr nc, .asm_726
.asm_712
	push bc
	push hl
	push de
	ld b, c
	call Func_0709
	ld b, $0
	pop hl
	add hl, bc
	ld e, l
	ld d, h
	pop hl
	add hl, bc
	pop bc
	dec b
	jr nz, .asm_712
	ret
.asm_726
	push bc
.asm_727
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .asm_727
	pop bc
	dec b
	jr nz, .asm_726
	ret

CopyData_SaveRegisters: ; 0732 (0:0732)
	push hl
	push de
	push bc
	call CopyData
	pop bc
	pop de
	pop hl
	ret

; copies bc bytes from hl to de
CopyData: ; 073c (0:073c)
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, c
	or b
	jr nz, CopyData
	ret

; switch to rombank (A + top2 of h shifted down),
; set top2 of H to 01,
; return old rombank id on top-of-stack
BankpushHome: ; 0745 (0:0745)
	push hl
	push bc
	push af
	push de
	ld e, l
	ld d, h
	ld hl, [sp+$9]
	ld b, [hl]
	dec hl
	ld c, [hl]
	dec hl
	ld [hl], b
	dec hl
	ld [hl], c
	ld hl, [sp+$9]
	ld a, [hBankROM]
	ld [hld], a
	ld [hl], $0
	ld a, d
	rlca
	rlca
	and $3
	ld b, a
	res 7, d
	set 6, d
	ld l, e
	ld h, d
	pop de
	pop af
	add b
	call BankswitchHome
	pop bc
	ret
; 0x76f

INCBIN "baserom.gbc",$076f,$078e - $076f

; restore rombank from top-of-stack
BankpopHome: ; 078e (0:078e)
	push hl
	push de
	ld hl, [sp+$7]
	ld a, [hld]
	call BankswitchHome
	dec hl
	ld d, [hl]
	dec hl
	ld e, [hl]
	inc hl
	inc hl
	ld [hl], e
	inc hl
	ld [hl], d
	pop de
	pop hl
	pop af
	ret

; switch ROM bank
BankswitchHome: ; 07a3 (0:07a3)
	ld [hBankROM], a
	ld [MBC3RomBank], a
	ret

; switch RAM bank
BankswitchRAM: ; 07a9 (0:07a9)
	push af
	ld [hBankRAM], a
	ld [MBC3SRamBank], a
	ld a, $a
	ld [MBC3SRamEnable], a
	pop af
	ret

; enable external RAM
EnableExtRAM: ; 07b6 (0:07b6)
	push af
	ld a, $a
	ld [MBC3SRamEnable], a
	pop af
	ret

; disable external RAM
DisableExtRAM: ; 07be (0:07be)
	push af
	xor a
	ld [MBC3SRamEnable], a
	pop af
	ret

; set current dest VRAM bank to 0
BankswitchVRAM_0: ; 07c5 (0:07c5)
	push af
	xor a
	ld [hBankVRAM], a
	ld [rVBK], a
	pop af
	ret

; set current dest VRAM bank to 1
BankswitchVRAM_1: ; 07cd (0:07cd)
	push af
	ld a, $1
	ld [hBankVRAM], a
	ld [rVBK], a
	pop af
	ret

; set current dest VRAM bank
; a: value to write
BankswitchVRAM: ; 07d6 (0:07d6)
	ld [hBankVRAM], a
	ld [rVBK], a
	ret
; 0x7db

INCBIN "baserom.gbc",$07db,$07e7 - $07db

Func_07e7: ; 07e7 (0:07e7)
	call CheckForCGB
	ret c
	ld hl, rKEY1
	bit 7, [hl]
	ret nz
	ld a, [rIE]
	push af
	xor a
	ld [rIE], a
	set 0, [hl]
	xor a
	ld [rIF], a
	ld [rIE], a
	ld a, $30
	ld [rJOYP], a
	stop
	call SetupTimer
	pop af
	ld [rIE], a
	ret

SetupExtRAM: ; 080b (0:080b)
	xor a
	call BankswitchRAM
	ld hl, $a000
	ld bc, $1000
.asm_815
	ld a, [hli]
	cp $41
	jr nz, .asm_82f
	ld a, [hli]
	cp $93
	jr nz, .asm_82f
	dec bc
	ld a, c
	or b
	jr nz, .asm_815
	call Func_084d
	scf
	call Func_4050
	call DisableExtRAM
	ret
.asm_82f
	ld hl, $a000
	ld a, [hli]
	cp $4
	jr nz, .asm_842
	ld a, [hli]
	cp $21
	jr nz, .asm_842
	ld a, [hl]
	cp $5
	jr nz, .asm_842
	ret
.asm_842
	call Func_084d
	or a
	call Func_4050
	call DisableExtRAM
	ret

Func_084d: ; 084d (0:084d)
	ld a, $3
.asm_84f
	call ClearExtRAMBank
	dec a
	cp $ff
	jr nz, .asm_84f
	ld hl, $a000
	ld [hl], $4
	inc hl
	ld [hl], $21
	inc hl
	ld [hl], $5
	ret

ClearExtRAMBank: ; 0863 (0:0863)
	push af
	call BankswitchRAM
	call EnableExtRAM
	ld hl, $a000
	ld bc, $2000
.asm_870
	xor a
	ld [hli], a
	dec bc
	ld a, c
	or b
	jr nz, .asm_870
	pop af
	ret

Func_0879: ; 0879 (0:0879)
	push de
	ld a, h
	ld e, l
	ld d, $0
	ld l, d
	ld h, d
	jr .asm_887
.asm_882
	add hl, de
.asm_883
	sla e
	rl d
.asm_887
	srl a
	jr c, .asm_882
	jr nz, .asm_883
	pop de
	ret
; 0x88f

INCBIN "baserom.gbc",$088f,$089b - $088f

Func_089b: ; 089b (0:089b)
	push hl
	push de
	ld hl, $caca
	ld a, [hli]
	ld d, [hl]
	inc hl
	ld e, a
	ld a, d
	rlca
	rlca
	xor e
	rra
	push af
	ld a, d
	xor e
	ld d, a
	ld a, [hl]
	xor e
	ld e, a
	pop af
	rl e
	rl d
	ld a, d
	xor e
	inc [hl]
	dec hl
	ld [hl], d
	dec hl
	ld [hl], e
	pop de
	pop hl
	ret

Func_08bf: ; 08bf (0:08bf)
	ld hl, $cad6
	ld [hl], e
	inc hl
	ld [hl], d
	ld hl, $cad8
	ld [hl], $1
	inc hl
	xor a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], b
	inc hl
	ld [hli], a
	ld [hl], $ef
	ld h, b
	ld l, $0
	xor a
.asm_8d9
	ld [hl], a
	inc l
	jr nz, .asm_8d9
	ret

Func_08de: ; 08de (0:08de)
	push hl
	push de
.asm_8e0
	push bc
	call Func_08ef
	ld [de], a
	inc de
	pop bc
	dec bc
	ld a, c
	or b
	jr nz, .asm_8e0
	pop de
	pop hl
	ret

Func_08ef: ; 08ef (0:08ef)
	ld hl, $cadc
	ld a, [hl]
	or a
	jr z, .asm_902
	dec [hl]
	inc hl
.asm_8f8
	ld b, [hl]
	inc hl
	ld c, [hl]
	inc [hl]
	inc hl
	ld a, [bc]
	ld c, [hl]
	inc [hl]
	ld [bc], a
	ret
.asm_902
	ld hl, $cad6
	ld c, [hl]
	inc hl
	ld b, [hl]
	inc hl
	dec [hl]
	inc hl
	jr nz, .asm_914
	dec hl
	ld [hl], $8
	inc hl
	ld a, [bc]
	inc bc
	ld [hl], a
.asm_914
	rl [hl]
	ld a, [bc]
	inc bc
	jr nc, .asm_92a
	ld hl, $cad6
	ld [hl], c
	inc hl
	ld [hl], b
	ld hl, $cadd
	ld b, [hl]
	inc hl
	inc hl
	ld c, [hl]
	inc [hl]
	ld [bc], a
	ret
.asm_92a
	ld [$cade], a
	ld hl, $cada
	bit 0, [hl]
	jr nz, .asm_94a
	set 0, [hl]
	inc hl
	ld a, [bc]
	inc bc
	ld [hli], a
	swap a
.asm_93c
	and $f
	inc a
	ld [hli], a
	push hl
	ld hl, $cad6
	ld [hl], c
	inc hl
	ld [hl], b
	pop hl
	jr .asm_8f8
.asm_94a
	res 0, [hl]
	inc hl
	ld a, [hli]
	jr .asm_93c
; 0x950

INCBIN "baserom.gbc",$0950,$099c - $0950

Func_099c: ; 099c (0:099c)
	xor a
	ld [$cab5], a
	ld hl, $ca00
	ld c, $28
	xor a
.asm_9a6
	ld [hli], a
	ld [hli], a
	inc hl
	inc hl
	dec c
	jr nz, .asm_9a6
	ret

; this function affects the stack so that it returns
; to the pointer following the rst call
; similar to rst 28, except this always loads bank 1
RST18: ; 09ae (0:09ae)
	push hl
	push hl
	push hl
	push hl
	push de
	push af
	ld hl, [sp+$d]
	ld d, [hl]
	dec hl
	ld e, [hl]
	dec hl
	ld [hl], $0
	dec hl
	ld a, [hBankROM]
	ld [hld], a
	ld [hl], $9
	dec hl
	ld [hl], $dc
	dec hl
	inc de
	ld a, [de]
	ld [hld], a
	dec de
	ld a, [de]
	ld [hl], a
	ld a, $1
	; fallthrough
Func_09ce: ; 09ce (0:09ce)
	call BankswitchHome
	ld hl, [sp+$d]
	inc de
	inc de
	ld [hl], d
	dec hl
	ld [hl], e
	pop af
	pop de
	pop hl
	ret
; 0x9dc

INCBIN "baserom.gbc",$09dc,$09e9 - $09dc

; this function affects the stack so that it returns
; to the three byte pointer following the rst call
RST28: ; 09e9 (0:09e9)
	push hl
	push hl
	push hl
	push hl
	push de
	push af
	ld hl, [sp+$d]
	ld d, [hl]
	dec hl
	ld e, [hl]
	dec hl
	ld [hl], $0
	dec hl
	ld a, [hBankROM]
	ld [hld], a
	ld [hl], $9
	dec hl
	ld [hl], $dc
	dec hl
	inc de
	inc de
	ld a, [de]
	ld [hld], a
	dec de
	ld a, [de]
	ld [hl], a
	dec de
	ld a, [de]
	inc de
	jr Func_09ce

; setup SNES memory $810-$867 and palette
InitSGB: ; 0a0d (0:0a0d)
	ld hl, SGB_0ad0
	call SendSGB
	ld hl, SGB_0a50
	call SendSGB
	ld hl, SGB_0a60
	call SendSGB
	ld hl, SGB_0a70
	call SendSGB
	ld hl, SGB_0a80
	call SendSGB
	ld hl, SGB_0a90
	call SendSGB
	ld hl, SGB_0aa0
	call SendSGB
	ld hl, SGB_0ab0
	call SendSGB
	ld hl, SGB_0ac0
	call SendSGB
	ld hl, SGB_0af0
	call SendSGB
	ld hl, SGB_0ae0
	call SendSGB
	ret

SGB_0a50: ; 0a50 (0:0a50)
INCBIN "baserom.gbc",$0a50,$0a60 - $0a50

SGB_0a60: ; 0a60 (0:0a60)
INCBIN "baserom.gbc",$0a60,$0a70 - $0a60

SGB_0a70: ; 0a70 (0:0a70)
INCBIN "baserom.gbc",$0a70,$0a80 - $0a70

SGB_0a80: ; 0a80 (0:0a80)
INCBIN "baserom.gbc",$0a80,$0a90 - $0a80

SGB_0a90: ; 0a90 (0:0a90)
INCBIN "baserom.gbc",$0a90,$0aa0 - $0a90

SGB_0aa0: ; 0aa0 (0:0aa0)
INCBIN "baserom.gbc",$0aa0,$0ab0 - $0aa0

SGB_0ab0: ; 0ab0 (0:0ab0)
INCBIN "baserom.gbc",$0ab0,$0ac0 - $0ab0

SGB_0ac0: ; 0ac0 (0:0ac0)
INCBIN "baserom.gbc",$0ac0,$0ad0 - $0ac0

SGB_0ad0: ; 0ad0 (0:0ad0)
INCBIN "baserom.gbc",$0ad0,$0ae0 - $0ad0

SGB_0ae0: ; 0ae0 (0:0ae0)
INCBIN "baserom.gbc",$0ae0,$0af0 - $0ae0

SGB_0af0: ; 0af0 (0:0af0)
INCBIN "baserom.gbc",$0af0,$0b20 - $0af0

; send SGB command
SendSGB: ; 0b20 (0:0b20)
	ld a, [hl]
	and $7
	ret z
	ld b, a
	ld c, $0
.asm_b27
	push bc
	ld a, $0
	ld [$ff00+c], a
	ld a, $30
	ld [$ff00+c], a
	ld b, $10
.asm_b30
	ld e, $8
	ld a, [hli]
	ld d, a
.asm_b34
	bit 0, d
	ld a, $10
	jr nz, .asm_b3c
	ld a, $20
.asm_b3c
	ld [$ff00+c], a
	ld a, $30
	ld [$ff00+c], a
	rr d
	dec e
	jr nz, .asm_b34
	dec b
	jr nz, .asm_b30
	ld a, $20
	ld [$ff00+c], a
	ld a, $30
	ld [$ff00+c], a
	pop bc
	dec b
	jr nz, .asm_b27
	ld bc, 4
	call Wait
	ret

DetectSGB: ; 0b59 (0:0b59)
	ld bc, 60
	call Wait
	ld hl, SGB_MASK_EN_ON_0bbb
	call SendSGB
	ld a, [rJOYP]
	and $3
	cp $3
	jr nz, .asm_ba3
	ld a, $20
	ld [rJOYP], a
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, $30
	ld [rJOYP], a
	ld a, $10
	ld [rJOYP], a
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, $30
	ld [rJOYP], a
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	ld a, [rJOYP]
	and $3
	cp $3
	jr nz, .asm_ba3
	ld hl, SGB_MASK_EN_OFF_0bab
	call SendSGB
	or a
	ret
.asm_ba3
	ld hl, SGB_MASK_EN_OFF_0bab
	call SendSGB
	scf
	ret

SGB_MASK_EN_OFF_0bab: ; 0bab (0:0bab)
INCBIN "baserom.gbc",$0bab,$0bbb - $0bab

SGB_MASK_EN_ON_0bbb: ; 0bbb (0:0bbb)
INCBIN "baserom.gbc",$0bbb,$0c08 - $0bbb

; loops 63000 * bc cycles (~15 * bc ms)
Wait: ; 0c08 (0:0c08)
	ld de, 1750
.loop
	nop
	nop
	nop
	dec de
	ld a, d
	or e
	jr nz, .loop
	dec bc
	ld a, b
	or c
	jr nz, Wait
	ret

; memcpy(DE, HL, B), but only during hblank
MemcpyHLDE_hblank: ; 0c19 (0:0c19)
	push bc
.loop
	ei
	di
	ld a, [rSTAT]        ;
	and $3               ;
	jr nz, .loop         ; assert hblank
	ld a, [hl]
	ld [de], a
	ld a, [rSTAT]        ;
	and $3               ;
	jr nz, .loop         ; assert still in hblank
	ei
	inc hl
	inc de
	dec b
	jr nz, .loop
	pop bc
	ret

; memcpy(HL, DE, B), but only during hblank
MemcpyDEHL_hblank: ; 0c32 (0:0c32)
	push bc
.asm_c33
	ei
	di
	ld a, [rSTAT]
	and $3
	jr nz, .asm_c33
	ld a, [de]
	ld [hl], a
	ld a, [rSTAT]
	and $3
	jr nz, .asm_c33
	ei
	inc hl
	inc de
	dec c
	jr nz, .asm_c33
	pop bc
	ret
; 0xc4b

INCBIN "baserom.gbc",$0c4b,$0c91 - $0c4b

; called at roughly 240Hz by TimerHandler
SerialTimerHandler: ; 0c91 (0:0c91)
	ld a, [wSerialOp]
	cp $29
	jr z, .begin_transfer
	cp $12
	jr z, .check_for_timeout
	ret
.begin_transfer
	ld a, [rSC]          ;
	add a                ; make sure that no serial transfer is active
	ret c                ;
	ld a, $1
	ld [rSC], a          ; use internal clock
	ld a, $81
	ld [rSC], a          ; use internal clock, set transfer start flag
	ret
.check_for_timeout
	; sets bit7 of [wSerialFlags] if the serial interrupt hasn't triggered
	; within four timer interrupts (60Hz)
	ld a, [wSerialCounter]
	ld hl, wSerialCounter2
	cp [hl]
	ld [hl], a
	ld hl, wSerialTimeoutCounter
	jr nz, .clear_counter
	inc [hl]
	ld a, [hl]
	cp $4
	ret c
	ld hl, wSerialFlags
	set 7, [hl]
	ret
.clear_counter
	ld [hl], $0
	ret
; 0xcc5

INCBIN "baserom.gbc",$0cc5,$0d26 - $0cc5

SerialHandler: ; 0d26 (0:0d26)
	push af
	push hl
	push de
	push bc
	ld a, [$ce63]        ;
	or a                 ;
	jr z, .asm_d35       ; if [$ce63] nonzero:
	call Func_3189       ;   ?
	jr .done             ;   return
.asm_d35
	ld a, [wSerialOp]        ;
	or a                 ;
	jr z, .asm_d55       ; skip ahead if [$cb74] zero
	; send/receive a byte
	ld a, [rSB]
	call SerialHandleRecv
	call SerialHandleSend ; returns byte to actually send
	push af
.wait_for_completion
	ld a, [rSC]
	add a
	jr c, .wait_for_completion
	pop af
	; end send/receive
	ld [rSB], a          ; prepare sending byte (from Func_0dc8?)
	ld a, [wSerialOp]
	cp $29
	jr z, .done          ; if [$cb74] != $29, use external clock
	jr .asm_d6a          ; and prepare for next byte.  either way, return
.asm_d55
	ld a, $1
	ld [wSerialRecvCounter], a
	ld a, [rSB]
	ld [wSerialRecvBuf], a
	ld a, $ac
	ld [rSB], a
	ld a, [wSerialRecvBuf]
	cp $12               ; if [$cba5] != $12, use external clock
	jr z, .done          ; and prepare for next byte.  either way, return
.asm_d6a
	ld a, $80            ;
	ld [rSC], a          ; transfer start, use external clock
.done
	ld hl, wSerialCounter
	inc [hl]
	pop bc
	pop de
	pop hl
	pop af
	reti

; handles a byte read from serial transfer by decoding it and storing it into
; the receive buffer
SerialHandleRecv: ; 0d77 (0:0d77)
	ld hl, wSerialLastReadCA
	ld e, [hl]
	dec e
	jr z, .last_was_ca
	cp $ac
	ret z                ; return if read_data == $ac
	cp $ca
	jr z, .read_ca
	or a
	jr z, .read_00_or_ff
	cp $ff
	jr nz, .read_data
.read_00_or_ff
	ld hl, wSerialFlags
	set 6, [hl]
	ret
.read_ca
	inc [hl]             ; inc [wSerialLastReadCA]
	ret
.last_was_ca
	; if last byte read was $ca, flip all bits of data received
	ld [hl], $0
	cpl
	jr .handle_byte
.read_data
	; flip top2 bits of data received
	xor $c0
.handle_byte
	push af
	ld a, [wSerialRecvIndex]
	ld e, a
	ld a, [$cba3]
	dec a
	and $1f
	cp e
	jr z, .set_flag_and_return
	ld d, $0
	; store into receive buffer
	ld hl, wSerialRecvBuf
	add hl, de
	pop af
	ld [hl], a
	; increment buffer index (mod 32)
	ld a, e
	inc a
	and $1f
	ld [$cba4], a
	; increment received bytes counter & clear flags
	ld hl, wSerialRecvCounter
	inc [hl]
	xor a
	ld [wSerialFlags], a
	ret
.set_flag_and_return
	pop af
	ld hl, wSerialFlags
	set 0, [hl]
	ret

; prepares a byte to send over serial transfer, either from the send-save byte
; slot or the send buffer
SerialHandleSend: ; 0dc8 (0:0dc8)
	ld hl, wSerialSendSave
	ld a, [hl]
	or a
	jr nz, .send_saved
	ld hl, wSerialSendBufToggle
	ld a, [hl]
	or a
	jr nz, .send_buf
	; no more data--send $ac to indicate this
	ld a, $ac
	ret
.send_saved
	ld a, [hl]
	ld [hl], $0
	ret
.send_buf
	; grab byte to send from send buffer, increment buffer index
	; and decrement to-send length
	dec [hl]
	ld a, [wSerialSendBufIndex]
	ld e, a
	ld d, $0
	ld hl, wSerialSendBuf
	add hl, de
	inc a
	and $1f
	ld [wSerialSendBufIndex], a
	ld a, [hl]
	; flip top2 bits of sent data
	xor $c0
	cp $ac
	jr z, .send_escaped
	cp $ca
	jr z, .send_escaped
	cp $ff
	jr z, .send_escaped
	or a
	jr z, .send_escaped
	ret
.send_escaped
	; escape tricky data by prefixing it with $ca and flipping all bits
	; instead of just top2
	xor $c0
	cpl
	ld [wSerialSendSave], a
	ld a, $ca
	ret

; store data in sendbuf for sending?
Func_0e0a: ; 0e0a (0:0e0a)
	push hl
	push de
	push bc
	push af
.asm_e0e
	ld a, [$cb80]
	ld e, a
	ld a, [wSerialSendBufIndex]
	dec a
	and $1f
	cp e
	jr z, .asm_e0e
	ld d, $0
	ld a, e
	inc a
	and $1f
	ld [$cb80], a
	ld hl, wSerialSendBuf
	add hl, de
	pop af
	ld [hl], a
	ld hl, wSerialSendBufToggle
	inc [hl]
	pop bc
	pop de
	pop hl
	ret

; sets carry if [wSerialRecvCounter] nonzero
Func_0e32: ; 0e32 (0:0e32)
	ld a, [wSerialRecvCounter]
	or a
	ret z
	scf
	ret

Func_0e39: ; 0e39 (0:0e39)
	push hl
	ld hl, wSerialRecvCounter
	ld a, [hl]
	or a
	jr nz, .asm_e49
	pop hl
	ld a, [wSerialFlags]
	or a
	ret nz
	scf
	ret
.asm_e49
	push de
	dec [hl]
	ld a, [$cba3]
	ld e, a
	ld d, $0
	ld hl, wSerialRecvBuf
	add hl, de
	ld a, [hl]
	push af
	ld a, e
	inc a
	and $1f
	ld [$cba3], a
	pop af
	pop de
	pop hl
	or a
	ret

Func_0e63: ; 0e63 (0:0e63)
	ld b, c
.asm_e64
	ld a, b
	sub c
	jr c, .asm_e6c
	cp $1f
	jr nc, .asm_e75
.asm_e6c
	inc c
	dec c
	jr z, .asm_e75
	ld a, [hli]
	call $0e0a
	dec c
.asm_e75
	inc b
	dec b
	jr z, .asm_e81
	call $0e39
	jr c, .asm_e81
	ld [de], a
	inc de
	dec b
.asm_e81
	ld a, [wSerialFlags]
	or a
	jr nz, .asm_e8c
	ld a, c
	or b
	jr nz, .asm_e64
	ret
.asm_e8c
	scf
	ret

; go into slave mode (external clock) for serial transfer?
Func_0e8e: ; 0e8e (0:0e8e)
	call ClearSerialData
	ld a, $12
	ld [rSB], a          ; send $12
	ld a, $80
	ld [rSC], a          ; use external clock, set transfer start flag
	ld a, [rIF]
	and $f7
	ld [rIF], a          ; clear serial interrupt flag
	ld a, [rIE]
	or $8                ; enable serial interrupt
	ld [rIE], a
	ret

ResetSerial: ; 0ea6 (0:0ea6)
	ld a, [rIE]
	and $f7
	ld [rIE], a
	xor a
	ld [rSB], a
	ld [rSC], a
	; fallthrough
ClearSerialData: ; 0eb1 (0:0eb1)
	ld hl, wSerialOp
	ld bc, $0051
.loop
	xor a
	ld [hli], a
	dec bc
	ld a, c
	or b
	jr nz, .loop
	ret
; 0xebf

INCBIN "baserom.gbc",$0ebf,$1072 - $0ebf

; copies the deck pointed to by de to $c400 or $c480
CopyDeckData: ; 1072 (0:1072)
	ld hl, $c400
	ld a, [$ff97]
	cp $c2
	jr z, .asm_107e
	ld hl, $c480
.asm_107e
	; start by putting a terminator at the end of the deck
	push hl
	ld bc, 59
	add hl, bc
	ld [hl], $0
	pop hl
	push hl
.nextCard
	ld a, [de]
	inc de
	ld b, a
	or a
	jr z, .done
	ld a, [de]
	inc de
	ld c, a
.cardQuantityLoop
	ld [hl], c
	inc hl
	dec b
	jr nz, .cardQuantityLoop
	jr .nextCard
.done
	ld hl, $cce9
	ld a, [de]
	inc de
	ld [hli], a
	ld a, [de]
	ld [hl], a
	pop hl
	ld bc, 59
	add hl, bc
	ld a, [hl]
	or a
	ret nz
	rst $38
	scf
	ret
; 0x10aa

INCBIN "baserom.gbc",$10aa,$160b - $10aa

Func_160b: ; 160b (0:160b)
	ld l, a
	ld a, [$ff97]
	ld h, a
	ld a, [hl]
	ret

Func_1611: ; 1611 (0:1611)
	ld l, a
	ld a, [$ff97]
	ld h, $c3
	cp $c2
	jr z, .asm_161c
	ld h, $c2

.asm_161c
	ld a, [hl]
	ret
; 0x161e

INCBIN "baserom.gbc",$161e,$1c72 - $161e

Func_1c72: ; 1c72 (0:1c72)
	push af
	push hl
	call Func_1611
	ld a, h
	ld [$ff97], a
	pop hl
	pop af
	ret

Func_1c7d: ; 1c7d (0:1c7d)
	call EnableExtRAM
	ld hl, $a010
asm_1c83
	ld a, [hli]
	ld [de], a
	inc de
	or a
	jr nz, asm_1c83
	dec de
	call DisableExtRAM
	ret

Func_1c8e: ; 1c8e (0:1c8e)
	ld hl, $cc16
	ld a, [hli]
	or [hl]
	jr z, .asm_1c9b
	ld a, [hld]
	ld l, [hl]
	ld h, a
	jp Func_2e89
.asm_1c9b
	ld hl, $c500
	ld a, [hl]
	or a
	jr z, .asm_1ca4
	jr asm_1c83
.asm_1ca4
	ld hl, $0092
	jp Func_2e89
; 0x1caa

INCBIN "baserom.gbc",$1caa,$1dca - $1caa

; memcpy(HL, DE, C)
Memcpy: ; 1dca (0:1dca)
	ld a, [$cabb]        ;
	bit 7, a             ;
	jr nz, .asm_1dd8     ; assert that LCD is on
.asm_1dd1
	ld a, [de]
	inc de
	ld [hli], a
	dec c
	jr nz, .asm_1dd1
	ret
.asm_1dd8
	jp MemcpyDEHL_hblank

Func_1ddb: ; 1ddb (0:1ddb)
	ld l, e
	ld h, $0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld a, l
	add d
	ld l, a
	ld a, h
	adc $98
	ld h, a
	ret

Func_1deb: ; 1deb (0:1deb)
	push af
	ld a, [$ff92]
	rra
	rra
	rra
	and $1f
	add d
	ld d, a
	ld a, [$ff93]
	rra
	rra
	rra
	and $1f
	add e
	ld e, a
	pop af
	ret
; 0x1e00

INCBIN "baserom.gbc",$1e00,$1e7c - $1e00

Func_1e7c: ; 1e7c (0:1e7c)
	ld a, [wConsole]
	cp CONSOLE_CGB
	jr z, asm_1ec9
	cp CONSOLE_SGB
	jp z, Func_1f0f
Func_1e88: ; 1e88 (0:1e88)
	call Func_1ddb
	ld a, $1c
	ld de, $1819
	call Func_1ea5
	dec c
	dec c
.asm_1e95
	ld a, $0
	ld de, $1e1f
	call Func_1ea5
	dec c
	jr nz, .asm_1e95
	ld a, $1d
	ld de, $1a1b
Func_1ea5: ; 1ea5 (0:1ea5)
	add sp, $e0
	push hl
	push bc
	ld hl, [sp+$4]
	dec b
	dec b
	push hl
	ld [hl], d
	inc hl
.asm_1eb0
	ld [hli], a
	dec b
	jr nz, .asm_1eb0
	ld [hl], e
	pop de
	pop bc
	pop hl
	push hl
	push bc
	ld c, b
	ld b, $0
	call Memcpy
	pop bc
	pop de
	ld hl, $0020
	add hl, de
	add sp, $20
	ret
asm_1ec9
	call Func_1ddb
	ld a, $1c
	ld de, $1819
	call Func_1efb
	dec c
	dec c
.asm_1ed6
	ld a, $0
	ld de, $1e1f
	push hl
	call Func_1ea5
	pop hl
	call BankswitchVRAM_1
	ld a, [$ccf3]
	ld e, a
	ld d, a
	xor a
	call Func_1ea5
	call BankswitchVRAM_0
	dec c
	jr nz, .asm_1ed6
	ld a, $1d
	ld de, $1a1b
	call Func_1efb
	ret

Func_1efb: ; 1efb (0:1efb)
	push hl
	call Func_1ea5
	pop hl
	call BankswitchVRAM_1
	ld a, [$ccf3]
	ld e, a
	ld d, a
	call Func_1ea5
	call BankswitchVRAM_0
	ret

Func_1f0f: ; 1f0f (0:1f0f)
	push bc
	push de
	call Func_1e88
	pop de
	pop bc
	ld a, [$ccf3]
	or a
	ret z
	push bc
	push de
	ld hl, $cae0
	ld de, Unknown_1f4f
	ld c, $10
.asm_1f25
	ld a, [de]
	inc de
	ld [hli], a
	dec c
	jr nz, .asm_1f25
	pop de
	pop bc
	ld hl, $cae4
	ld [hl], d
	inc hl
	ld [hl], e
	inc hl
	ld a, d
	add b
	dec a
	ld [hli], a
	ld a, e
	add c
	dec a
	ld [hli], a
	ld a, [$ccf3]
	and $80
	jr z, .asm_1f48
	ld a, $2
	ld [$cae2], a
.asm_1f48
	ld hl, $cae0
	call SendSGB
	ret

Unknown_1f4f: ; 1f4f (0:1f4f)
INCBIN "baserom.gbc",$1f4f,$1f5f - $1f4f

Func_1f5f: ; 1f5f (0:1f5f)
	push de
	push af
	push hl
	add sp, $e0
	call Func_1ddb
.asm_1f67
	push hl
	push bc
	ld hl, [sp+$25]
	ld d, [hl]
	ld hl, [sp+$27]
	ld a, [hl]
	ld hl, [sp+$4]
	push hl
.asm_1f72
	ld [hli], a
	add d
	dec b
	jr nz, .asm_1f72
	pop de
	pop bc
	pop hl
	push hl
	push bc
	ld c, b
	ld b, $0
	call Memcpy
	ld hl, [sp+$24]
	ld a, [hl]
	ld hl, [sp+$27]
	add [hl]
	ld [hl], a
	pop bc
	pop de
	ld hl, $0020
	add hl, de
	dec c
	jr nz, .asm_1f67
	add sp, $24
	pop de
	ret
; 0x1f96

INCBIN "baserom.gbc",$1f96,$20b0 - $1f96

Func_20b0: ; 20b0 (0:20b0)
	ld hl, $2fe8
	ld a, [wConsole]
	cp CONSOLE_CGB
	jr nz, .asm_20bd
	ld hl, $37f8
.asm_20bd
	ld de, $8d00
	ld b, $30
	jr asm_2121

Func_20c4: ; 20c4 (0:20c4)
	ld hl, $3028
	ld a, [wConsole]
	cp CONSOLE_CGB
	jr nz, .asm_20d1
	ld hl, $3838
.asm_20d1
	ld de, $8d40
	ld b, $c
	jr asm_2121

Func_20d8: ; 20d8 (0:20d8)
	ld b, $10
	jr asm_20de

Func_20dc: ; 20dc (0:20dc)
	ld b, $24
asm_20de
	ld hl, $32e8
	ld a, [wConsole]
	cp CONSOLE_CGB
	jr nz, .asm_20eb
	ld hl, $3af8
.asm_20eb
	ld de, $8d00
	jr asm_2121

Func_20f0: ; 20f0 (0:20f0)
	ld hl, $4008
	ld de, $8a00
	ld b, $d
	call asm_2121
	ld hl, $3528
	ld a, [wConsole]
	cp CONSOLE_CGB
	jr nz, .asm_2108
	ld hl, $3d38
.asm_2108
	ld de, $8d00
	ld b, $30
	jr asm_2121

Func_210f: ; 210f (0:210f)
	ld hl, $40d8
	ld de, $9300
	ld b, $8
	jr asm_2121

Func_2119: ; 2119 (0:2119)
	ld hl, DuelGraphics - Fonts
	ld de, $9000 ; destination
	ld b, $38 ; number of tiles
asm_2121
	ld a, BANK(Fonts)
	call BankpushHome
	ld c, $10
	call CopyGfxData
	call BankpopHome
	ret
; 0x212f

INCBIN "baserom.gbc",$212f,$21c5 - $212f

Func_21c5: ; 21c5 (0:21c5)
	push de
	push bc
	call Func_2298
	jr .asm_21e8
.asm_21cc
	cp $5
	jr c, .asm_21d9
	cp $10
	jr nc, .asm_21d9
	call Func_21f2
	jr .asm_21e8
.asm_21d9
	ld e, a
	ld d, [hl]
	call Func_2546
	jr nc, .asm_21e1
	inc hl
.asm_21e1
	call Func_22ca
	xor a
	call Func_21f2
.asm_21e8
	ld a, [hli]
	or a
	jr nz, .asm_21cc
	call Func_230f
	pop bc
	pop de
	ret

Func_21f2: ; 21f2 (0:21f2)
	or a
	jr z, .asm_2241
	cp $e
	jr z, .asm_2221
	cp $f
	jr z, .asm_2221
	cp $a
	jr z, .asm_224d
	cp $5
	jr z, .asm_2225
	cp $6
	jr z, .asm_220f
	cp $7
	jr z, .asm_2215
	scf
	ret
.asm_220f
	ld a, $1
	ld [$cd0a], a
	ret
.asm_2215
	call Func_230f
	xor a
	ld [$cd0a], a
	ld a, $f
	ld [$ffaf], a
	ret
.asm_2221
	ld [$ffaf], a
	xor a
	ret
.asm_2225
	ld a, [$cd0a]
	push af
	ld a, $1
	ld [$cd0a], a
	call Func_230f
	pop af
	ld [$cd0a], a
	ld a, [$ffb0]
	or a
	jr nz, .asm_2240
	ld a, [hl]
	push hl
	call Func_22f2
	pop hl
.asm_2240
	inc hl
.asm_2241
	ld a, [$ffae]
	or a
	ret z
	ld b, a
	ld a, [$ffac]
	cp b
	jr z, .asm_224d
	xor a
	ret
.asm_224d
	call Func_230f
	ld a, [$cd08]
	or a
	call z, .asm_2257
.asm_2257
	xor a
	ld [$ffac], a
	ld a, [$ffad]
	add $20
	ld b, a
	ld a, [$ffaa]
	and $e0
	add b
	ld [$ffaa], a
	ld a, [$ffab]
	adc $0
	ld [$ffab], a
	ld a, [$cd09]
	inc a
	ld [$cd09], a
	xor a
	ret

Func_2275: ; 2275 (0:2275)
	ld a, d
	dec a
	ld [$cd04], a
	ld a, e
	ld [$ffa8], a
	call Func_2298
	xor a
	ld [$ffb0], a
	ld [$ffa9], a
	ld a, $88
	ld [$cd06], a
	ld a, $80
	ld [$cd07], a
	ld hl, $c600
.asm_2292
	xor a
	ld [hl], a
	inc l
	jr nz, .asm_2292
	ret

Func_2298: ; 2298 (0:2298)
	xor a
	ld [$cd0a], a
	ld [$ffac], a
	ld [$cd0b], a
	ld a, $f
	ld [$ffaf], a
	ret

Func_22a6: ; 22a6 (0:22a6)
	push af
	call Func_22ae
	pop af
	ld [$ffae], a
	ret

Func_22ae: ; 22ae (0:22ae)
	push hl
	ld a, d
	ld [$ffad], a
	xor a
	ld [$ffae], a
	ld [$cd09], a
	call Func_1ddb
	ld a, l
	ld [$ffaa], a
	ld a, h
	ld [$ffab], a
	call Func_2298
	xor a
	ld [$cd0b], a
	pop hl
	ret

Func_22ca: ; 22ca (0:22ca)
	push hl
	push de
	push bc
	ld a, [$ffb0]
	and $1
	jr nz, .asm_22ed
	call Func_2325
	jr c, .asm_22de
	or a
	jr nz, .asm_22e9
	call Func_24ac
.asm_22de
	ld a, [$ffb0]
	and $2
	jr nz, .asm_22e9
	ld a, [$ffa9]
	call Func_22f2
.asm_22e9
	pop bc
	pop de
	pop hl
	ret
.asm_22ed
	call Func_235e
	jr .asm_22e9

Func_22f2: ; 22f2 (0:22f2)
	ld [$cd05], a
	ld hl, $ffaa
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc de
	ld [hl], d
	dec hl
	ld [hl], e
	dec de
	ld l, e
	ld h, d
	ld de, $cd05
	ld c, $1
	call Memcpy
	ld hl, $ffac
	inc [hl]
	ret

Func_230f: ; 230f (0:230f)
	ld a, [$cd0a]
	or a
	ret z
	ld a, [$cd0b]
	or a
	ret z
	push hl
	push de
	push bc
	ld e, $20
	call Func_22ca
	pop bc
	pop de
	pop hl
	ret

Func_2325: ; 2325 (0:2325)
	call Func_235e
	ret c
	or a
	ret nz
	ld a, [$ffa8]
	ld hl, $cd04
	cp [hl]
	jr nz, .asm_2345
	ld a, [$ffa9]
	ld h, $c8
.asm_2337
	ld l, a
	ld a, [hl]
	or a
	jr nz, .asm_2337
	ld h, $c9
	ld c, [hl]
	ld b, $c8
	xor a
	ld [bc], a
	jr .asm_234a
.asm_2345
	inc [hl]
	jr nz, .asm_2349
	inc [hl]
.asm_2349
	ld l, [hl]
.asm_234a
	ld a, [$ffa9]
	ld c, a
	ld b, $c9
	ld a, l
	ld [$ffa9], a
	ld [bc], a
	ld h, $c8
	ld [hl], c
	ld h, $c6
	ld [hl], e
	inc h
	ld [hl], d
	ld b, l
	xor a
	ret

; search linked-list for letters e/d (regisers), if found hoist the result to
; head of list and return it.  carry flag denotes success.
Func_235e: ; 235e (0:235e)
	ld a, [$cd0a]        ;
	or a                 ;
	jr z, .asm_2376      ; if [$cd0a] nonzero:
	call Uppercase       ;   uppercase e
	ld a, [$cd0b]
	ld d, a
	or a
	jr nz, .asm_2376     ;   if [$cd0b] is zero:
	ld a, e              ;
	ld [$cd0b], a        ;     [$cd0b] ← e
	ld a, $1             ;
	or a                 ;     return a = 1
	ret
.asm_2376
	xor a
	ld [$cd0b], a        ; [$cd0b] ← 0
	ld a, [$ffa9]
	ld l, a              ; l ← [$ffa9]; index to to linked-list head
.asm_237d
	ld h, $c6                                     ;
	ld a, [hl]           ; a ← key1[l]            ;
	or a                                          ;
	ret z                ; if NULL, return a = 0  ;
	cp e                                          ; loop for e/d key in
	jr nz, .asm_238a     ;                        ; linked list
	inc h                ;                        ;
	ld a, [hl]           ; if key1[l] == e and    ;
	cp d                 ;    key2[l] == d:       ;
	jr z, .asm_238f      ;   break                ;
.asm_238a                                             ;
	ld h, $c8            ;                        ;
	ld l, [hl]           ; l ← next[l]            ;
	jr .asm_237d
.asm_238f
	ld a, [$ffa9]
	cp l
	jr z, .asm_23af      ; assert at least one iteration
	ld c, a
	ld b, $c9
	ld a, l
	ld [bc], a           ; prev[i0] ← i
	ld [$ffa9], a        ; [$ffa9] ← i  (update linked-list head)
	ld h, $c9
	ld b, [hl]
	ld [hl], $0          ; prev[i] ← 0
	ld h, $c8
	ld a, c
	ld c, [hl]
	ld [hl], a           ; next[i] ← i0
	ld l, b
	ld [hl], c           ; next[prev[i]] ← next[i]
	ld h, $c9
	inc c
	dec c
	jr z, .asm_23af      ; if next[i] != NULL:
	ld l, c              ;   l ← next[i]
	ld [hl], b           ;   prev[next[i]] ← prev[i]
.asm_23af
	scf                  ; set carry to indicate success
	ret                  ; (return new linked-list head in a)

; uppercases e if [wUppercaseFlag] is nonzero
Uppercase: ; 23b1 (0:23b1)
	ld a, [wUppercaseFlag]
	or a
	ret z
	ld a, e
	cp $60
	ret c
	cp $7b
	ret nc
	sub $20
	ld e, a
	ret

Func_23c1: ; 23c1 (0:23c1)
	ld a, [hl]
	cp $6
	jr nz, .asm_23cf
	call Func_23d3
	inc b
	srl b
	xor a
	sub b
	ret
.asm_23cf
	xor a
	ld [$cd0a], a
Func_23d3: ; 23d3 (0:23d3)
	push hl
	push de
	ld bc, $0000
.asm_23d8
	ld a, [hli]
	or a
	jr z, .asm_23f8
	inc c
	cp $5
	jr c, .asm_23ec
	cp $10
	jr nc, .asm_23ec
	cp $5
	jr nz, .asm_23d8
	inc b
	jr .asm_23f4
.asm_23ec
	ld e, a
	ld d, [hl]
	inc b
	call Func_2546
	jr nc, .asm_23d8
.asm_23f4
	inc c
	inc hl
	jr .asm_23d8
.asm_23f8
	xor a
	sub b
	pop de
	pop hl
	ret
; 0x23fd

INCBIN "baserom.gbc",$23fd,$245d - $23fd

Func_245d: ; 245d (0:245d)
	push de
	push bc
	ld de, $caa0
	push de
	ld bc, $d8f0
	call Func_2499
	ld bc, $fc18
	call Func_2499
	ld bc, $ff9c
	call Func_2499
	ld bc, $fff6
	call Func_2499
	ld bc, $ffff
	call Func_2499
	xor a
	ld [de], a
	pop hl
	ld e, $5
.asm_2486
	inc hl
	ld a, [hl]
	cp $20
	jr nz, .asm_2495
	ld [hl], $0
	inc hl
	dec e
	jr nz, .asm_2486
	dec hl
	ld [hl], $20
.asm_2495
	dec hl
	pop bc
	pop de
	ret

Func_2499: ; 2499 (0:2499)
	ld a, $5
	ld [de], a
	inc de
	ld a, $1f
.asm_249f
	inc a
	add hl, bc
	jr c, .asm_249f
	ld [de], a
	inc de
	ld a, l
	sub c
	ld l, a
	ld a, h
	sbc b
	ld h, a
	ret

Func_24ac: ; 24ac (0:24ac)
	push hl
	push de
	push bc
	ld a, [$cd0a]
	or a
	jr nz, .asm_24bf
	call Func_2510
	call Memcpy
.asm_24bb
	pop bc
	pop de
	pop hl
	ret
.asm_24bf
	call Func_24ca
	call Func_2518
	call Memcpy
	jr .asm_24bb

Func_24ca: ; 24ca (0:24ca)
	push bc
	ld a, [hBankROM]
	push af
	ld a, BANK(VWF)
	call BankswitchHome
	push de
	ld a, e
	ld de, $ccf4
	call Func_24fa
	pop de
	ld a, d
	ld de, $ccf5
	call Func_24fa
	ld hl, $ccf4
	ld b, $8
.asm_24e8
	ld a, [hli]
	swap a
	or [hl]
	dec hl
	ld [hli], a
	ld [hli], a
	dec b
	jr nz, .asm_24e8
	call BankpopHome
	pop bc
	ld de, $ccf4
	ret

Func_24fa: ; 24fa (0:24fa)
	sub $20
	ld l, a
	ld h, $0
	add hl, hl
	add hl, hl
	add hl, hl
	ld bc, VWF
	add hl, bc
	ld b, $8
.asm_2508
	ld a, [hli]
	ld [de], a
	inc de
	inc de
	dec b
	jr nz, .asm_2508
	ret

Func_2510: ; 2510 (0:2510)
	push bc
	call Func_256d
	call Func_252e
	pop bc
Func_2518: ; 2518 (0:2518)
	ld hl, $cd07
	ld a, b
	xor [hl]
	ld h, $0
	ld l, a
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld a, [$cd06]
	ld b, a
	ld c, $0
	add hl, bc
	ld c, $10
	ret

Func_252e: ; 252e (0:252e)
	ld a, $1d
	call BankpushHome
	ld de, $ccf4
	push de
	ld c, $8
.asm_2539
	ld a, [hli]
	ld [de], a
	inc de
	ld [de], a
	inc de
	dec c
	jr nz, .asm_2539
	pop de
	call BankpopHome
	ret

Func_2546: ; 2546 (0:2546)
	ld a, [$cd0a]
	or a
	jr nz, .asm_255f
	ld a, e
	cp $10
	jr c, .asm_2561
	cp $60
	jr nc, .asm_2565
	ld a, [$ffaf]
	cp $f
	jr nz, .asm_2565
	ld d, $f
	or a
	ret
.asm_255f
	or a
	ret
.asm_2561
	cp $5
	jr c, .asm_2569
.asm_2565
	ld d, $0
	or a
	ret
.asm_2569
	ld e, d
	ld d, a
	scf
	ret

Func_256d: ; 256d (0:256d)
	ld bc, $0280
	ld a, d
	cp $e
	jr z, .asm_2580
	cp $f
	jr nz, .asm_2582
	ld bc, $0000
	ld a, e
	sub $10
	ld e, a
.asm_2580
	ld d, $0
.asm_2582
	ld l, e
	ld h, d
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, bc
	ret
; 0x2589

INCBIN "baserom.gbc",$2589,$2636 - $2589

Func_2636: ; 2636 (0:2636)
	ld [$cd10], a
	ld [$ffb1], a
	ld de, $cd11
	ld b, $8
.asm_2640
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .asm_2640
	xor a
	ld [$cd0f], a
	ret

Func_264b: ; 264b (0:264b)
	xor a
	ld [$cd99], a
	ld a, [hButtonsPressed2]
	or a
	jr z, .asm_2685
	ld b, a
	ld a, [$cd14]
	ld c, a
	ld a, [$cd10]
	bit 6, b
	jr z, .asm_266b
	dec a
	bit 7, a
	jr z, .asm_2674
	ld a, [$cd14]
	dec a
	jr .asm_2674
.asm_266b
	bit 7, b
	jr z, .asm_2685
	inc a
	cp c
	jr c, .asm_2674
	xor a
.asm_2674
	push af
	ld a, $1
	ld [$cd99], a
	call Func_26e9
	pop af
	ld [$cd10], a
	xor a
	ld [$cd0f], a
.asm_2685
	ld a, [$cd10]
	ld [$ffb1], a
	ld hl, $cd17
	ld a, [hli]
	or [hl]
	jr z, .asm_26a9
	ld a, [hld]
	ld l, [hl]
	ld h, a
	ld a, [$ffb1]
	call CallF
	jr nc, asm_26d1
.asm_269b
	call Func_270b
	call Func_26c0
	ld a, [$cd10]
	ld e, a
	ld a, [$ffb1]
	scf
	ret
.asm_26a9
	ld a, [hButtonsPressed]
	and $3
	jr z, asm_26d1
	and $1
	jr nz, .asm_269b
	ld a, [$cd10]
	ld e, a
	ld a, $ff
	ld [$ffb1], a
	call Func_26c0
	scf
	ret

Func_26c0: ; 26c0 (0:26c0)
	push af
	ld a, [$ffb1]
	inc a
	jr z, .asm_26ca
	ld a, $2
	jr .asm_26cc
.asm_26ca
	ld a, $3
.asm_26cc
	call Func_3796
	pop af
	ret
asm_26d1
	ld a, [$cd99]
	or a
	jr z, Func_26da
	call Func_3796

Func_26da: ; 26da (0:26da)
	ld hl, $cd0f
	ld a, [hl]
	inc [hl]
	and $f
	ret nz
	ld a, [$cd15]
	bit 4, [hl]
	jr z, asm_26ec
Func_26e9: ; 26e9 (0:26e9)
	ld a, [$cd16]
asm_26ec
	ld c, a
	ld a, [$cd13]
	ld l, a
	ld a, [$cd10]
	ld h, a
	call Func_0879
	ld a, l
	ld hl, $cd11
	ld d, [hl]
	inc hl
	add [hl]
	ld e, a
	call Func_1deb
	ld a, c
	ld c, e
	ld b, d
	call Func_06c3
	or a
	ret

Func_270b: ; 270b (0:270b)
	ld a, [$cd15]
	jr asm_26ec
; 0x2710

INCBIN "baserom.gbc",$2710,$2a1a - $2710

Func_2a1a: ; 2a1a (0:2a1a)
	xor a
	ld hl, $cd10
	ld [hli], a
	ld [hl], d
	inc hl
	ld [hl], e
	inc hl
	ld [hl], $0
	inc hl
	ld [hl], $1
	inc hl
	ld [hl], b
	inc hl
	ld [hl], c
	ld [$cd0f], a
	ret
; 0x2a30

INCBIN "baserom.gbc",$2a30,$2a3e - $2a30

Func_2a3e: ; 2a3e (0:2a3e)
	push hl
	call Func_2a6f
	ld a, $b
	ld de, $010e
	call Func_1deb
	call Func_22a6
	pop hl
	ld a, l
	or h
	jp nz, Func_2e76
	ld hl, $c590
	jp Func_21c5

Func_2a59: ; 2a59 (0:2a59)
	push hl
	call Func_2a9e
	ld a, $13
	ld de, $010e
	call Func_1deb
	call Func_22a6
	call EnableLCD
	pop hl
	jp Func_2e41

Func_2a6f: ; 2a6f (0:2a6f)
	ld de, $000c
	ld bc, $0c06
	call Func_1deb
	call Func_1e7c
	ret
; 0x2a7c

INCBIN "baserom.gbc",$2a7c,$2a9e - $2a7c

Func_2a9e: ; 2a9e (0:2a9e)
	ld de, $000c
	ld bc, $1406
	call Func_1deb
	call Func_1e7c
	ret

Func_2aab: ; 2aab (0:2aab)
	call Func_2a59
	xor a
	ld hl, Unknown_2ac8
	call Func_2636
	call EnableLCD
.asm_2ab8
	call Func_053f
	call Func_26da
	ld a, [hButtonsPressed]
	and $3
	jr z, .asm_2ab8
	call Func_26e9
	ret

Unknown_2ac8: ; 2ac8 (0:2ac8)
INCBIN "baserom.gbc",$2ac8,$2af0 - $2ac8

Func_2af0: ; 2af0 (0:2af0)
	call Func_2a59
	ld de, $0710
	call Func_2b66
	ld de, $0610
	jr .asm_2b0a
	call Func_2a3e
	ld de, $0310
	call Func_2b66
	ld de, $0210
.asm_2b0a
	ld a, d
	ld [$cd98], a
	ld bc, $0f00
	call Func_2a1a
	ld a, [$cd9a]
	ld [$cd10], a
	call EnableLCD
	jr .asm_2b39
.asm_2b1f
	call Func_053f
	call Func_26da
	ld a, [hButtonsPressed]
	bit 0, a
	jr nz, .asm_2b50
	ld a, [hButtonsPressed2]
	and $30
	jr z, .asm_2b1f
	ld a, $1
	call Func_3796
	call Func_26e9
.asm_2b39
	ld a, [$cd98]
	ld c, a
	ld hl, $cd10
	ld a, [hl]
	xor $1
	ld [hl], a
	add a
	add a
	add c
	ld [$cd11], a
	xor a
	ld [$cd0f], a
	jr .asm_2b1f
.asm_2b50
	ld a, [$cd10]
	ld [$ffb1], a
	or a
	jr nz, .asm_2b5c
	ld [$cd9a], a
	ret
.asm_2b5c
	xor a
	ld [$cd9a], a
	ld a, $1
	ld [$ffb1], a
	scf
	ret

Func_2b66: ; 2b66 (0:2b66)
	call Func_1deb
	ld hl, $002f
	call Func_2c1b
	ret
; 0x2b70

INCBIN "baserom.gbc",$2b70,$2b78 - $2b70

Duel_LoadDecks: ; 2b78 (0:2b78)
	xor a
	ld [wIsPracticeDuel], a
	ld a, [wOpponentDeck]
	cp SAMS_NORMAL_DECK - 2
	jr z, .normalSamDuel
	or a ; cp SAMS_PRACTICE_DECK - 2
	jr nz, .notPracticeDuel

; only practice duels will display help messages, but
; any duel with Sam will force the PRACTICE_PLAYER_DECK
;.practiceSamDuel
	inc a
	ld [wIsPracticeDuel], a

.normalSamDuel
	xor a
	ld [wOpponentDeck], a
	call Func_1c72
	ld a, PRACTICE_PLAYER_DECK
	call LoadDeck
	call Func_1c72
	ld hl, $caca
	ld a, $57
	ld [hli], a
	ld [hli], a
	ld [hl], a
	xor a

.notPracticeDuel
	inc a
	inc a
	call LoadDeck
	ld a, [wOpponentDeck]
	cp NUMBER_OF_DECKS
	jr c, .validDeck
	ld a, PRACTICE_PLAYER_DECK - 2
	ld [wOpponentDeck], a

.validDeck
	ld a, $f1
	call Func_160b
	ld a, [wOpponentDeck]
	or $80
	ld [hl], a
	ret
; 0x2bbf

INCBIN "baserom.gbc",$2bbf,$2c08 - $2bbf

Func_2c08: ; 2c08 (0:2c08)
	ld d, [hl]
	inc hl
	bit 7, d
	ret nz
	ld e, [hl]
	inc hl
	call Func_22ae
	push hl
	call Func_2c23
	pop hl
	inc hl
	inc hl
	jr Func_2c08

Func_2c1b: ; 2c1b (0:2c1b)
	call Func_22ae
	jr Func_2c29

Func_2c20: ; 2c20 (0:2c20)
	call Func_22ae
Func_2c23: ; 2c23 (0:2c23)
	ld a, [hli]
	or [hl]
	ret z
	ld a, [hld]
	ld l, [hl]
	ld h, a
Func_2c29: ; 2c29 (0:2c29)
	ld a, [hBankROM]
	push af
	call ReadTextOffset
	call Func_21c5
	pop af
	call BankswitchHome
	ret
; 0x2c37

INCBIN "baserom.gbc",$2c37,$2cc8 - $2c37

Func_2cc8: ; 2cc8 (0:2cc8)
	xor a
	ld [$ce48], a
	ld [$ce49], a
	ld [$ce4a], a
	ld a, $f
	;ld [$ffaf], a
	db $ea, $af, $ff
Func_2cd7: ; 2cd7 (0:2cd7)
	push hl
	call Func_2d06
	pop bc
	;ld a, [$ffaf]
	db $fa, $af, $ff
	ld [hli], a
	ld a, [$cd0a]
	ld [hli], a
	ld a, [hBankROM]
	ld [hli], a
	ld [hl], c
	inc hl
	ld [hl], b
	ret

Func_2ceb: ; 2ceb (0:2ceb)
	call Func_2cd7
	ld hl, $ce48
	inc [hl]
	ret

Func_2cf3: ; 2cf3 (0:2cf3)
	call Func_2d06
	ld a, [hli]
	;ld [$ffaf], a
	db $ea, $af, $ff
	ld a, [hli]
	ld [$cd0a], a
	ld a, [hli]
	call BankswitchHome
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

Func_2d06: ; 2d06 (0:2d06)
	ld a, [$ce48]
	ld e, a
	add a
	add a
	add e
	ld e, a
	ld d, $0
	ld hl, $ce2b
	add hl, de
	ret
; 0x2d15

INCBIN "baserom.gbc",$2d15,$2d43 - $2d15

Func_2d43: ; 2d43 (0:2d43)
	call Func_2cf3
	ld a, [hli]
	or a
	jr z, .asm_2d79
	cp $5
	jr c, .asm_2d65
	cp $10
	jr nc, .asm_2d65
	call Func_21f2
	jr nc, .asm_2d74
	cp $9
	jr z, .asm_2dc8
	cp $b
	jr z, .asm_2d8a
	cp $c
	jr z, .asm_2db3
	jr .asm_2d74
.asm_2d65
	ld e, a
	ld d, [hl]
	call Func_2546
	jr nc, .asm_2d6d
	inc hl
.asm_2d6d
	call Func_22ca
	xor a
	call Func_21f2
.asm_2d74
	call Func_2cd7
	or a
	ret
.asm_2d79
	ld a, [$ce48]
	or a
	jr z, .asm_2d85
	dec a
	ld [$ce48], a
	jr Func_2d43
.asm_2d85
	call Func_230f
	scf
	ret
.asm_2d8a
	call Func_2ceb
	ld a, $f
	;ld [$ffaf], a
	db $ea, $af, $ff
	xor a
	ld [$cd0a], a
	ld de, $ce3f
	ld hl, $ce49
	call Func_2de0
	ld a, l
	or h
	jr z, .asm_2dab
	call ReadTextOffset
	call Func_2cd7
	jr Func_2d43
.asm_2dab
	ld hl, $c590
	call Func_2cd7
	jr Func_2d43
.asm_2db3
	call Func_2ceb
	ld de, $ce43
	ld hl, $ce4a
	call Func_2de0
	call Func_2e12
	call Func_2cd7
	jp Func_2d43
.asm_2dc8
	call Func_2ceb
	call Func_2e2c
	ld a, [$caa0]
	cp $6
	jr z, .asm_2dda
	ld a, $7
	call Func_21f2
.asm_2dda
	call Func_2cd7
	jp Func_2d43

Func_2de0: ; 2de0 (0:2de0)
	push de
	ld a, [hl]
	inc [hl]
	add a
	ld e, a
	ld d, $0
	pop hl
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; uses the two byte text id in hl to read the three byte text offset
; loads the correct bank for the specific text and returns the pointer in hl
ReadTextOffset: ; 2ded (0:2ded)
	push de
	ld e, l
	ld d, h
	add hl, hl
	add hl, de
	set 6, h ; hl = (hl * 3) + $4000
	ld a, BANK(TextOffsets)
	call BankswitchHome
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc hl
	ld a, [hl]
	ld h, d
	rl h
	rla
	rl h
	rla
	add BANK(TextOffsets)
	call BankswitchHome
	res 7, d
	set 6, d ; $4000 ≤ de ≤ $7fff
	ld l, e
	ld h, d
	pop de
	ret

Func_2e12: ; 2e12 (0:2e12)
	ld a, [$cd0a]
	or a
	jp z, Func_245d
	ld de, $caa0
	push de
	call Func_0663
	pop hl
	ld c, $4
.asm_2e23
	ld a, [hl]
	cp $30
	ret nz
	inc hl
	dec c
	jr nz, .asm_2e23
	ret

Func_2e2c: ; 2e2c (0:2e2c)
	ld de, $caa0
	push de
	ld a, [$ff97]
	cp $c3
	jp z, .asm_2e3c
	call Func_1c7d
	pop hl
	ret
.asm_2e3c
	call Func_1c8e
	pop hl
	ret

Func_2e41: ; 2e41 (0:2e41)
	ld a, l
	or h
	jr z, .asm_2e53
	ld a, [hBankROM]
	push af
	call ReadTextOffset
	call .asm_2e56
	pop af
	call BankswitchHome
	ret
.asm_2e53
	ld hl, $c590
.asm_2e56
	call Func_2cc8
.asm_2e59
	ld a, [$ff90]
	ld b, a
	ld a, [$ce47]
	inc a
	cp $3
	jr nc, .asm_2e6d
	bit 1, b
	jr nz, .asm_2e70
	jr .asm_2e6d
.asm_2e6a
	call Func_053f
.asm_2e6d
	dec a
	jr nz, .asm_2e6a
.asm_2e70
	call Func_2d43
	jr nc, .asm_2e59
	ret

Func_2e76: ; 2e76 (0:2e76)
	ld a, [hBankROM]
	push af
	call ReadTextOffset
	call Func_2cc8
.asm_2e7f
	call Func_2d43
	jr nc, .asm_2e7f
	pop af
	call BankswitchHome
	ret

Func_2e89: ; 2e89 (0:2e89)
	ld a, l
	or h
	jr z, .asm_2e9f
	ld a, [hBankROM]
	push af
	call ReadTextOffset
.asm_2e93
	ld a, [hli]
	ld [de], a
	inc de
	or a
	jr nz, .asm_2e93
	pop af
	call BankswitchHome
	dec de
	ret
.asm_2e9f
	ld a, [$ff97]
	cp $c3
	jp z, Func_1c8e
	jp Func_1c7d
; 0x2ea9

INCBIN "baserom.gbc",$2ea9,$2fa0 - $2ea9

LoadCardGfx: ; 2fa0 (0:2fa0)
	ld a, [hBankROM]
	push af
	push hl
	srl h
	srl h
	srl h
	ld a, BANK(GrassEnergyCardGfx)
	add h
	call BankswitchHome
	pop hl
	add hl, hl
	add hl, hl
	add hl, hl
	res 7, h
	set 6, h
	call CopyGfxData
	ld b, $8 ; length of palette
	ld de, $ce23
.copyCardPalette
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .copyCardPalette
	pop af
	call BankswitchHome
	ret
; 0x2fcb

INCBIN "baserom.gbc",$2fcb,$302c - $2fcb

; loads the deck id in a from DeckPointers
; sets carry flag if an invalid deck id is used
LoadDeck: ; 302c (0:302c)
	push hl
	ld l, a
	ld h, $0
	ld a, [hBankROM]
	push af
	ld a, BANK(DeckPointers)
	call BankswitchHome
	add hl, hl
	ld de, DeckPointers
	add hl, de
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld a, d
	or e
	jr z, .nullPointer
	call CopyDeckData
	pop af
	call BankswitchHome
	pop hl
	or a
	ret
.nullPointer
	pop af
	call BankswitchHome
	pop hl
	scf
	ret
; 0x3055

Func_3055: ; 3055 (0:3055)
	push hl
	ld hl, $ccb9
	add [hl]
	ld [hli], a
	ld a, $0
	adc [hl]
	ld [hl], a
	pop hl
	ret

Func_3061: ; 3061 (0:3061)
	push de
	push hl
	ld e, a
	ld hl, $ccb9
	ld a, [hl]
	sub e
	ld [hli], a
	ld a, [hl]
	sbc $0
	ld [hl], a
	pop hl
	pop de
	ret

Func_3071: ; 3071 (0:3071)
	push hl
	ld hl, $ce4e
	ld [hl], e
	inc hl
	ld [hl], d
	rst $18
	xor l
	ld [hl], c
	pop hl
	ret

Func_307d: ; 307d (0:307d)
	push hl
	ld hl, $ce4e
	ld [hl], e
	inc hl
	ld [hl], d
	ld a, $1
	rst $18
	xor l
	ld [hl], c
	ld hl, $cac2
	ld [hl], $0
	pop hl
	ret

Func_3090: ; 3090 (0:3090)
	ld a, d
	cp b
	ret nz
	ld a, e
	cp c
	ret

Func_3096: ; 3096 (0:3096)
	ld a, [hBankROM]
	push af
	ld a, $2
	call BankswitchHome
	call $4000
	pop af
	call BankswitchHome
	ret

Func_30a6: ; 30a6 (0:30a6)
	ld a, [hBankROM]
	push af
	ld a, $6
	call BankswitchHome
	ld a, $1
	ld [$ce60], a
	call $40d5
	pop bc
	ld a, b
	call BankswitchHome
	ret

Func_30bc: ; 30bc (0:30bc)
	ld a, h
	ld [$ce50], a
	ld a, l
	ld [$ce51], a
	ld a, [hBankROM]
	push af
	ld a, $2
	call BankswitchHome
	call $4211
	call Func_2a9e
	pop af
	call BankswitchHome
	ret

Func_30d7: ; 30d7 (0:30d7)
	ld a, [hBankROM]
	push af
	ld a, $2
	call BankswitchHome
	call $433c
	pop af
	call BankswitchHome
	ret

Func_30e7: ; 30e7 (0:30e7)
	ld a, [hBankROM]
	push af
	ld a, $2
	call BankswitchHome
	call $4764
	ld b, a
	pop af
	call BankswitchHome
	ld a, b
	ret

Func_30f9: ; 30f9 (0:30f9)
	ld b, a
	ld a, [hBankROM]
	push af
	ld a, $2
	call BankswitchHome
	call $4932
	pop af
	call BankswitchHome
	ret

Func_310a: ; 310a (0:310a)
	ld [$ce59], a
	ld a, [hBankROM]
	push af
	ld a, $2
	call BankswitchHome
	call $4aaa
	pop af
	call BankswitchHome
	ret

Func_311d: ; 311d (0:311d)
	ld a, [hBankROM]
	push af
	ld a, $2
	call BankswitchHome
	call $4b85
	pop af
	call BankswitchHome
	ret

Func_312d: ; 312d (0:312d)   ; serial transfer-related
	push hl
	ld hl, $ce64
	ld a, $88
	ld [hli], a          ; [$ce64] ← $88
	ld a, $33
	ld [hli], a          ; [$ce65] ← $33
	ld [hl], d           ; [$ce66] ← d
	inc hl
	ld [hl], e           ; [$ce67] ← e
	inc hl
	ld [hl], c           ; [$ce68] ← c
	inc hl
	ld [hl], b           ; [$ce69] ← b
	inc hl
	pop de
	ld [hl], e           ; [$ce6a] ← l
	inc hl
	ld [hl], d           ; [$ce6b] ← h
	inc hl
	ld de, $ff45
	ld [hl], e           ; [$ce6c] ← $45
	inc hl
	ld [hl], d           ; [$ce6d] ← $ff
	ld hl, $ce70
	ld [hl], $64         ; [$ce70] ← $64
	inc hl
	ld [hl], $ce         ; [$ce71] ← $ce
	call Func_0e8e
	ld a, $1
	ld [$ce63], a        ; [$ce63] ← 1
	call Func_31fc
.asm_315d
	call Func_053f
	ld a, [$ce63]
	or a
	jr nz, .asm_315d
	call ResetSerial
	ld bc, $05dc
.asm_316c
	dec bc
	ld a, b
	or c
	jr nz, .asm_316c
	ld a, [$ce6e]
	cp $81
	jr nz, .asm_3182
	ld a, [$ce6f]
	ld l, a
	and $f1
	ld a, l
	ret z
	scf
	ret
.asm_3182
	ld a, $ff
	ld [$ce6f], a
	scf
	ret

Func_3189: ; 3189 (0:3189)
	ld hl, PointerTable_3190
	dec a
	jp JumpToFunctionInTable

PointerTable_3190: ; 3190 (0:3190)
	dw Func_31a8
	dw Func_31a8
	dw Func_31a8
	dw Func_31a8
	dw Func_31a8
	dw Func_31b0
	dw Func_31ca
	dw Func_31dd
	dw Func_31e5
	dw Func_31ef
	dw Func_31ea
	dw Func_31f2

Func_31a8: ; 31a8 (0:31a8)
	call Func_31fc
Func_31ab: ; 31ab (0:31ab)
	ld hl, $ce63
	inc [hl]
	ret

Func_31b0: ; 31b0 (0:31b0)
	call Func_31ab
	ld hl, $ce68
	ld a, [hli]
	or [hl]
	jr nz, .asm_31bf
	call Func_31ab
	jr Func_31dd
.asm_31bf
	ld hl, $ce6a
	ld de, $ce70
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a

Func_31ca: ; 31ca (0:31ca)
	call Func_31fc
	ld hl, $ce68
	ld a, [hl]
	dec [hl]
	or a
	jr nz, .asm_31d8
	inc hl
	dec [hl]
	dec hl
.asm_31d8
	ld a, [hli]
	or [hl]
	jr z, Func_31ab
	ret

Func_31dd: ; 31dd (0:31dd)
	ld a, [$ce6c]
Func_31e0: ; 31e0 (0:31e0)
	call Func_3212
	jr Func_31ab

Func_31e5: ; 31e5 (0:31e5)
	ld a, [$ce6d]
	jr Func_31e0

Func_31ea: ; 31ea (0:31ea)
	ld a, [rSB]
	ld [$ce6e], a
Func_31ef: ; 31ef (0:31ef)
	xor a
	jr Func_31e0

Func_31f2: ; 31f2 (0:31f2)
	ld a, [rSB]
	ld [$ce6f], a
	xor a
	ld [$ce63], a
	ret

Func_31fc: ; 31fc (0:31fc)
	ld hl, $ce70
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld a, [de]
	inc de
	ld [hl], d
	dec hl
	ld [hl], e
	ld e, a
	ld hl, $ce6c
	add [hl]
	ld [hli], a
	ld a, $0
	adc [hl]
	ld [hl], a
	ld a, e
	; fallthrough
Func_3212: ; 3212 (0:3212)
	ld [rSB], a
	ld a, $1
	ld [rSC], a
	ld a, $81
	ld [rSC], a
	ret
; 0x321d

INCBIN "baserom.gbc",$321d,$377f - $321d

SetupSound_T: ; 377f (0:377f)
	farcall SetupSound_Ext
	ret

Func_3784: ; 3784 (0:3784)
	xor a
PlaySong: ; 3785 (0:3785)
	farcall Func_f4006
	ret

Func_378a: ; 378a (0:378a)
	farcall Func_f400f
	ret

Func_378f: ; 378f (0:378f)
	farcall Func_f4012
	ret

Func_3794: ; 3794 (0:3794)
	ld a, $04
Func_3796: ; 3796 (0:3796)
	farcall Func_f4009
	ret

Func_379b: ; 379b (0:379b)
	farcall Func_f401b
	ret

Func_37a0: ; 37a0 (0:37a0)
	farcall Func_f401e
	ret
; 0x37a5

INCBIN "baserom.gbc",$37a5,$380e - $37a5

Func_380e: ; 380e (0:380e)
	ld a, [$d0c1]
	bit 7, a
	ret nz
	ld a, [hBankROM]
	push af
	ld a, BANK(Func_c484)
	call BankswitchHome
	call Func_c484
	call Func_c554
	ld a, BANK(Func_1c610)
	call BankswitchHome
	call Func_1c610
	call Func_3cb4
	ld a, BANK(Func_804d8)
	call BankswitchHome
	call Func_804d8
	call Func_089b
	pop af
	call BankswitchHome
	ret

Func_383d: ; 383d (0:383d)
	ld a, $1
	ld [wCounterEnable], a
	ld a, [hBankROM]
	push af
.asm_3845
	call Func_3855
	jr nc, .asm_3850
	farcall LoadMap
	jr .asm_3845
.asm_3850
	pop af
	call BankswitchHome
	ret

Func_3855: ; 3855 (0:3855)
	ld a, [$d0b5]
	cp $7
	jr c, .asm_385e
	ld a, $6
.asm_385e
	ld hl, PointerTable_3864
	jp JumpToFunctionInTable

PointerTable_3864: ; 3864 (0:3864)
	dw Func_3874
	dw Func_38c0
	dw Func_38a3
	dw Func_3876
	dw Credits_3911
	dw Func_38fb
	dw Func_38db
	dw Func_3874

Func_3874: ; 3874 (0:3874)
	scf
	ret

Func_3876: ; 3876 (0:3876)
	ld a, [hBankROM]
	push af
	call Func_379b
	ld a, MUSIC_CARDPOP
	call PlaySong
	ld a, $3
	ld [$d0c2], a
	ld a, [$d10e]
	or $10
	ld [$d10e], a
	farcall Func_b177
	ld a, [$d10e]
	and $ef
	ld [$d10e], a
	call Func_37a0
	pop af
	call BankswitchHome
	scf
	ret

Func_38a3: ; 38a3 (0:38a3)
	ld a, $2
	ld [$d0c2], a
	xor a
	ld [$d112], a
	ld a, $ff
	ld [$d0c3], a
	ld a, $2
	ld [$cc1a], a
	ld a, MUSIC_CARDPOP
	call PlaySong
	bank1call Func_758f
	scf
	ret

Func_38c0: ; 38c0 (0:38c0)
	ld a, $1
	ld [$d0c2], a
	xor a
	ld [$d112], a
	call EnableExtRAM
	xor a
	ld [$ba44], a
	call DisableExtRAM
	call Func_3a3b
	bank1call Duel_Start
	scf
	ret

Func_38db: ; 38db (0:38db)
	ld a, $6
	ld [$d111], a
	call Func_39fc
	call EnableExtRAM
	xor a
	ld [$ba44], a
	call DisableExtRAM
asm_38ed
	farcall Func_131d3
	ld a, $9
	ld [$d111], a
	call Func_39fc
	scf
	ret

Func_38fb: ; 38fb (0:38fb)
	xor a
	ld [$d112], a
	bank1call Func_406f
	call EnableExtRAM
	ld a, [$ba44]
	call DisableExtRAM
	cp $ff
	jr z, asm_38ed
	scf
	ret

Credits_3911: ; 3911 (0:3911)
	farcall Credits_1d6ad
	or a
	ret
; 0x3917

INCBIN "baserom.gbc",$3917,$3927 - $3917

Func_3927: ; 3927 (0:3927)
	push hl
	call Func_3946
	ld a, [hl]
	pop hl
	ret
; 0x392e

INCBIN "baserom.gbc",$392e,$3946 - $392e

Func_3946: ; 3946 (0:3946)
	push bc
	srl b
	srl c
	swap c
	ld a, c
	and $f0
	or b
	ld c, a
	ld b, $0
	ld hl, $d133
	add hl, bc
	pop bc
	ret

Func_395a: ; 395a (0:395a)
	ld a, [hBankROM]
	push af
	ld a, [$d4c6]
	call BankswitchHome
	call CopyGfxData
	pop af
	call BankswitchHome
	ret

Unknown_396b: ; 396b (0:396b)
INCBIN "baserom.gbc",$396b,$3973 - $396b

Unknown_3973: ; 3973 (0:3973)
INCBIN "baserom.gbc",$3973,$397b - $3973

Unknown_397b: ; 397b (0:397b)
INCBIN "baserom.gbc",$397b,$3997 - $397b

Func_3997: ; 3997 (0:3997)
	ld a, [hBankROM]
	push af
	ld a, BANK(Func_1c056)
	call BankswitchHome
	call Func_1c056
	pop af
	call BankswitchHome
	ret
; 0x39a7

INCBIN "baserom.gbc",$39a7,$39ad - $39a7

Func_39ad: ; 39ad (0:39ad)
	push bc
	cp $8
	jr c, .asm_39b4
	rst $38
	xor a
.asm_39b4
	add a
	add a
	ld h, a
	add a
	add h
	add l
	ld l, a
	ld h, $0
	ld bc, $d34a
	add hl, bc
	pop bc
	ret

Func_39c3: ; 39c3 (0:39c3)
	push hl
	push bc
	push de
	xor a
	ld [$d3aa], a
	ld b, a
	ld c, $8
	ld de, $000c
	ld hl, $d34a
	ld a, [$d3ab]
.asm_39d6
	cp [hl]
	jr z, .asm_39e1
	add hl, de
	inc b
	dec c
	jr nz, .asm_39d6
	scf
	jr z, .asm_39e6
.asm_39e1
	ld a, b
	ld [$d3aa], a
	or a
.asm_39e6
	pop de
	pop bc
	pop hl
	ret
; 0x39ea

INCBIN "baserom.gbc",$39ea,$39fc - $39ea

Func_39fc: ; 39fc (0:39fc)
	push hl
	push bc
	call Func_378a
	or a
	push af
	call Func_3a1f
	ld c, a
	pop af
	jr z, .asm_3a11
	ld a, c
	ld hl, $d112
	cp [hl]
	jr z, .asm_3a1c
.asm_3a11
	ld a, c
	cp $1f
	jr nc, .asm_3a1c
	ld [$d112], a
	call PlaySong
.asm_3a1c
	pop bc
	pop hl
	ret

Func_3a1f: ; 3a1f (0:3a1f)
	ld a, [$d3b8]
	or a
	jr z, .asm_3a37
	ld a, [$d32e]
	cp $2
	jr z, .asm_3a37
	cp $b
	jr z, .asm_3a37
	cp $c
	jr z, .asm_3a37
	ld a, MUSIC_RONALD
	ret
.asm_3a37
	ld a, [$d111]
	ret

Func_3a3b: ; 3a3b (0:3a3b)
	farcall Func_1124d
	ret

Func_3a40: ; 3a40 (0:3a40)
	farcall Func_11430
	ret
; 0x3a45

INCBIN "baserom.gbc",$3a45,$3a5e - $3a45

Func_3a5e: ; 3a5e (0:3a5e)
	ld a, [hBankROM]
	push af
	ld l, $4
	call Func_3abd
	jr nc, .asm_3ab3
	ld a, BANK(Func_c653)
	call BankswitchHome
	call Func_c653
	ld a, $4
	call BankswitchHome
	ld a, [$d334]
	ld d, a
.asm_3a79
	ld a, [hli]
	bit 7, a
	jr nz, .asm_3ab3
	push bc
	push hl
	cp d
	jr nz, .asm_3aab
	ld a, [hli]
	cp b
	jr nz, .asm_3aab
	ld a, [hli]
	cp c
	jr nz, .asm_3aab
	ld a, [hli]
	ld [$d0c6], a
	ld a, [hli]
	ld [$d0c7], a
	ld a, [hli]
	ld [$d0ca], a
	ld a, [hli]
	ld [$d0cb], a
	ld a, [hli]
	ld [$d0c8], a
	ld a, [hli]
	ld [$d0c9], a
	pop hl
	pop bc
	pop af
	call BankswitchHome
	scf
	ret
.asm_3aab
	pop hl
	ld bc, $0008
	add hl, bc
	pop bc
	jr .asm_3a79
.asm_3ab3
	pop af
	call BankswitchHome
	ld l, $6
	call $49c2
	ret

Func_3abd: ; 3abd (0:3abd)
	push bc
	push hl
	ld a, [wCurMap]
	ld l, a
	ld h, $0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld bc, MapScripts
	add hl, bc
	pop bc
	ld b, $0
	add hl, bc
	ld a, [hBankROM]
	push af
	ld a, BANK(MapScripts)
	call BankswitchHome
	ld a, [hli]
	ld h, [hl]
	ld l, a
	pop af
	call BankswitchHome
	ld a, l
	or h
	jr nz, .asm_3ae5
	scf
.asm_3ae5
	ccf
	pop bc
	ret
; 0x3ae8

INCBIN "baserom.gbc",$3ae8,$3aed - $3ae8

Func_3aed: ; 3aed (0:3aed)
	ld hl, $d413
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, [hli]
	ld c, [hl]
	inc hl
	ld b, [hl]
	push bc
	rlca
	ld c, a
	ld b, $0
	ld hl, Unknown_1217b
	add hl, bc
	ld a, [hBankROM]
	push af
	ld a, BANK(Unknown_1217b)
	call BankswitchHome
	ld a, [hli]
	ld h, [hl]
	ld l, a
	pop af
	call BankswitchHome
	pop bc
	jp [hl]
; 0x3b11

INCBIN "baserom.gbc",$3b11,$3bd2 - $3b11

Func_3bd2: ; 3bd2 (0:3bd2)
	ld a, l
	ld [$cad3], a
	ld a, h
	ld [$cad4], a
	ret

Func_3bdb: ; 3bdb (0:3bdb)
	push hl
	ld hl, $0000
	call Func_3bd2
	pop hl
	ret
; 0x3be4

INCBIN "baserom.gbc",$3be4,$3bf5 - $3be4

Func_3bf5: ; 3bf5 (0:3bf5)
	ld a, [hBankROM]
	push af
	push hl
	ld a, [$d4c6]
	call BankswitchHome
	ld a, [$d4c4]
	ld l, a
	ld a, [$d4c5]
	ld h, a
	call CopyData_SaveRegisters
	pop hl
	pop af
	call BankswitchHome
	ret
; 0x3c10

INCBIN "baserom.gbc",$3c10,$3c45 - $3c10

Func_3c45: ; 3c45 (0:3c45)
	jp [hl]
; 0x3c46

INCBIN "baserom.gbc",$3c46,$3c48 - $3c46

Func_3c48: ; 3c48 (0:3c48)
	push af
	ld a, [rLCDC]
	bit 7, a
	jr z, .asm_3c58
	push bc
	push de
	push hl
	call Func_053f
	pop hl
	pop de
	pop bc
.asm_3c58
	pop af
	ret

Func_3c5a: ; 3c5a (0:3c5a)
	ld hl, $0000
	rl c
	rl b
	ld a, $10
.asm_3c63
	ld [$ffb6], a
	rl l
	rl h
	push hl
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ccf
	jr nc, .asm_3c78
	ld h, a
	add sp, $2
	scf
	jr .asm_3c79
.asm_3c78
	pop hl
.asm_3c79
	rl c
	rl b
	ld a, [$ffb6]
	dec a
	jr nz, .asm_3c63
	ret
; 0x3c83

INCBIN "baserom.gbc",$3c83,$3ca0 - $3c83

Func_3ca0: ; 3ca0 (0:3ca0)
	xor a
	ld [$d5d7], a
	ld a, [hBankROM]
	push af
	ld a, BANK(Func_1296e)
	call BankswitchHome
	call Func_1296e
	pop af
	call BankswitchHome
	ret

Func_3cb4: ; 3cb4 (0:3cb4)
	ld a, [hBankROM]
	push af
	ld a, BANK(Func_12a21)
	call BankswitchHome
	call Func_12a21
	pop af
	call BankswitchHome
	ret
; 0x3cc4

INCBIN "baserom.gbc",$3cc4,$3d72 - $3cc4

Func_3d72: ; 3d72 (0:3d72)
	ld a, [hBankROM]
	push af
	push hl
	push hl
	ld a, [$d4ca]
	cp $ff
	jr nz, .asm_3d84
	ld de, Unknown_80e5a
	xor a
	jr .asm_3da1
.asm_3d84
	ld a, [$d4c4]
	ld l, a
	ld a, [$d4c5]
	ld h, a
	ld a, [$d4c6]
	call BankswitchHome
	ld a, [hli]
	push af
	ld a, [$d4ca]
	rlca
	ld e, [hl]
	add e
	ld e, a
	inc hl
	ld a, [hl]
	adc $0
	ld d, a
	pop af
.asm_3da1
	add BANK(Unknown_80e5a)
	pop hl
	ld bc, $000b
	add hl, bc
	ld [hli], a
	call BankswitchHome
	ld a, [de]
	ld [hli], a
	inc de
	ld a, [de]
	ld [hl], a
	pop hl
	pop af
	call BankswitchHome
	ret

Func_3db7: ; 3db7 (0:3db7)
	push bc
	ld c, $0
	call Func_3dbf
	pop bc
	ret

Func_3dbf: ; 3dbf (0:3dbf)
	ld a, [$d4cf]
	cp $10
	jr c, .asm_3dc9
	rst $38
	ld a, $f
.asm_3dc9
	push bc
	swap a
	push af
	and $f
	ld b, a
	pop af
	and $f0
	or c
	ld c, a
	ld hl, $d4d0
	add hl, bc
	pop bc
	ret
; 0x3ddb

INCBIN "baserom.gbc",$3ddb,$3df3 - $3ddb

Func_3df3: ; 3df3 (0:3df3)
	push af
	ld a, [hBankROM]
	push af
	push hl
	ld a, BANK(Func_12c7f)
	call BankswitchHome
	ld hl, [sp+$5]
	ld a, [hl]
	call Func_12c7f
	call Func_0404
	pop hl
	pop af
	call BankswitchHome
	pop af
	ld a, [$d61b]
	ret
; 0x3e10

INCBIN "baserom.gbc",$3e10,$3e17 - $3e10

Func_3e17: ; 3e17 (0:3e17)
	ld [$d131], a
	ld a, [hBankROM]
	push af
	ld a, $4
	call BankswitchHome
	call $6fc6
	pop af
	call BankswitchHome
	ret

Func_3e2a: ; 3e2a (0:3e2a)
	ld [$d61e], a
	ld a, $63
	jr Func_3e17
; 0x3e31

INCBIN "baserom.gbc",$3e31,$3fe0 - $3e31

; jumps to 3f:hl
Bankswitch3dTo3f: ; 3fe0 (0:3fe0)
	push af
	ld a, $3f
	ld [hBankROM], a
	ld [MBC3RomBank], a
	pop af
	ld bc, Bankswitch3d
	push bc
	jp [hl]

Bankswitch3d: ; 3fe0 (0:3fe0)
	ld a, $3d
	ld [hBankROM], a
	ld [MBC3RomBank], a
	ret

rept $a
db $ff
endr
