INCBIN "baserom.gbc",$18000,$1996e - $18000

Func_1996e: ; 1996e (6:596e)
	call EnableExtRAM
	ld a, $c2
	ld [$ff97], a
	ld hl, $a100
	ld bc, $1607
.asm_1997b
	xor a
	ld [hli], a
	dec bc
	ld a, c
	or b
	jr nz, .asm_1997b
	ld a, $5
	ld hl, $a350
	call Func_199e0
	ld a, $7
	ld hl, $a3a4
	call Func_199e0
	ld a, $9
	ld hl, $a3f8
	call Func_199e0
	call EnableExtRAM
	ld hl, $a100
	ld a, $80
.asm_199a2
	ld [hl], a
	inc l
	jr nz, .asm_199a2
	ld hl, $bc00
	xor a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld hl, $bb00
	ld c, $10
.asm_199b2
	ld [hl], $0
	ld de, $0010
	add hl, de
	dec c
	jr nz, .asm_199b2
	ld a, $2
	ld [$a003], a
	ld a, $2
	ld [$a006], a
	ld [$ce47], a
	xor a
	ld [$a007], a
	ld [$a009], a
	ld [$a004], a
	ld [$a005], a
	ld [$a00a], a
	farcall Func_8cf9
	call DisableExtRAM
	ret

Func_199e0: ; 199e0 (6:59e0)
	push de
	push bc
	push hl
	call LoadDeck
	jr c, .asm_19a0e
	call Func_19a12
	pop hl
	call EnableExtRAM
	push hl
	ld de, $c590
.asm_199f3
	ld a, [de]
	inc de
	ld [hli], a
	or a
	jr nz, .asm_199f3
	pop hl
	push hl
	ld de, $0018
	add hl, de
	ld de, $c400
	ld c, $3c
.asm_19a04
	ld a, [de]
	inc de
	ld [hli], a
	dec c
	jr nz, .asm_19a04
	call DisableExtRAM
	or a
.asm_19a0e
	pop hl
	pop bc
	pop de
	ret

Func_19a12: ; 19a12 (6:5a12)
	ld hl, $cce9
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, $c590
	call Func_2e89
	ret
; 0x19a1f

INCBIN "baserom.gbc",$19a1f,$1a61f - $19a1f

Func_1a61f: ; 1a61f (6:661f)
	push af
	ld de, $389f
	call Func_2275
	pop af
	or a
	jr nz, .asm_1a640
	ld a, $40
	call $663b
	ld a, $5f
	call $663b
	ld a, $76
	call $663b
	ld a, $c1
	ld hl, $0191
	jr .asm_1a660
.asm_1a640
	ld hl, $018f
	cp $1e
	jr z, .asm_1a660
	cp $43
	jr z, .asm_1a660
	ld hl, $0192
	cp $64
	jr z, .asm_1a660
	ld hl, $0193
	cp $65
	jr z, .asm_1a660
	cp $66
	jr z, .asm_1a660
	ld hl, $0190
.asm_1a660
	push hl
	ld e, a
	ld d, $0
	call $2f10
	call Func_379b
	ld a, MUSIC_MEDAL
	call PlaySong
	ld hl, $cc27
	ld a, [hli]
	ld h, [hl]
	ld l, a
	bank1call $2ebb
	ld a, $c2
	ld [$ff97], a
	pop hl
	bank1call $5e5f
.asm_1a680
	call Func_378a
	or a
	jr nz, .asm_1a680
	call Func_37a0
	bank1call $5773
	ret
; 0x1a68d

INCBIN "baserom.gbc",$1a68d,$1a6cc - $1a68d

Func_1a6cc: ; 1a6cc (6:66cc)
	ret
; 0x1a6cd

INCBIN "baserom.gbc",$1a6cd,$1ad89 - $1a6cd

Func_1ad89: ; 1ad89 (6:6d89)
INCBIN "baserom.gbc",$1ad89,$1c000 - $1ad89
