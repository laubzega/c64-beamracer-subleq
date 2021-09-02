
        .include "vlib/vasyl.s"

        jsr knock_knock
        jsr copy_and_activate_dlist
 
	rts

	.include "vlib/vlib.s"

; ?-? - DL
; ?+[0000-01ff] - tabela odejmowań (256x1 (take branch), 255x0 (skip branch))
; ?+[0200-ffff] - VMem

; : <addr-leq:16> <addr-pos==:+8> <addr1:16> <addr2:16>


	.segment "VASYL"

.export dl_start
.export dl_end

	;;	XXX this is wrong
	;;	instead of [b] <- [b]-[a]
	;;	we do		[b] <- [a]-[b]
	;;	correction: negate [a], not [b]


dl_start:
	; enable reading from both ports, we're in bank0, DL enabled
	MOV		VREG_CONTROL, %00011000	; this can be done from C64 setup
	; start of vm program
	MOV		VREG_ADR0, <vm_start	; this can be done from C64 setup
	MOV		VREG_ADR0+1, >vm_start
	; make DL restart at mainloop so that program continues in the new frame
	MOV		VREG_DLISTL, <mainloop
	MOV		VREG_DLISTH, >mainloop
mainloop:
	MOV		VREG_STEP0, 1
	MOV		VREG_STEP1, 2	;; skip 2 bytes - over next 2 instructions for all self-modifying writes

	MOV		VREG_ADR1, <(pcleq+1)
	MOV		VREG_ADR1+1, >(pcleq+1)
	XFER		VREG_PORT1, (0) ;; lo byte of new PC (if neq), branch after DECA taken
	XFER		VREG_PORT1, (0) ;; hi byte of new PC (if neq), branch after DECA taken

	MOV		VREG_ADR1, <(pcpos+1)
	MOV		VREG_ADR1+1, >(pcpos+1)
	XFER		VREG_PORT1, (0) ;; lo byte of new PC (if positive), branch after DECA not taken, just address of the next instruction
	XFER		VREG_PORT1, (0) ;; hi byte of new PC (if positive), branch after DECA not taken, just address of the next instruction

	;; copy address of [a] to place where [a] will be read
	MOV		VREG_ADR1, <(addr1+1)
	MOV		VREG_ADR1+1, >(addr1+1)
	XFER		VREG_PORT1, (0)	;; lo byte of [a]
	XFER		VREG_PORT1, (0) ;; hi byte of [a]

	;; copy address of [b] to two places: to read value to be negated and store result of [a]-[b]
	MOV		VREG_STEP0, 0
	MOV		VREG_STEP1, 0
	MOV		VREG_ADR1, <(addr2+1)
	MOV		VREG_ADR1+1, >(addr2+1)
	XFER		VREG_PORT1, (0)	;; lo byte of [b]
	MOV		VREG_ADR1, <(addr2_2+1)
	MOV		VREG_ADR1+1, >(addr2_2+1)
	MOV		VREG_STEP0, 1	; advance after next read
	XFER		VREG_PORT1, (0) ;; lo byte of [b]

	MOV		VREG_STEP0, 0
	MOV		VREG_ADR1, <(addr2+1+2)
	MOV		VREG_ADR1+1, >(addr2+1+2)
	XFER		VREG_PORT1, (0)	;; hi byte of @a2
	MOV		VREG_ADR1, <(addr2_2+1+2)
	MOV		VREG_ADR1+1, >(addr2_2+1+2)
	XFER		VREG_PORT1, (0) ;; hi byte of @a2

	BRA addr1	; skip over next BRA
mainback:
	BRA mainloop	; we need this intermediate trampoline to go back more than 127 bytes from the end of the code to the beginning


	;; read value from [a], put as step0 in two places, step0/1 set to 0, because we need this value twice
;	MOV		VREG_STEP0, 0	; step0 is already 0
;	MOV		VREG_STEP1, 0	; step1 is already 0
addr1:
	MOV		VREG_ADR0, 0	; this will be modified
	MOV		VREG_ADR0+1, 0	; this will be modified
	MOV		VREG_ADR1, <(addrval_a+1)
	MOV		VREG_ADR1+1, >(addrval_a+1)
	XFER		VREG_PORT1, (0)
	MOV		VREG_ADR1, <(addrval_a2+1)
	MOV		VREG_ADR1+1, >(addrval_a2+1)
	XFER		VREG_PORT1, (0)
addr2:
	;; read value from [b], put as step0, step0/1 don't matter (still 0)
	MOV		VREG_ADR0, 0	; this will be modified
	MOV		VREG_ADR0+1, 0	; this will be modifid
	MOV		VREG_ADR1, <(addrval_b+1)
	MOV		VREG_ADR1+1, >(addrval_b+1)
	XFER		VREG_PORT1, (0)

	;; first indexed read - what is -[b]? put it into addrval_bneg2 and addrval_bneg as step0 values
	MOV		VREG_ADR0,	<(negtable+$80)		; middle of the table, position of 0
	MOV		VREG_ADR0+1, >(negtable+$80)	; middle of the table, position of 0
	MOV		VREG_ADR1,	<(addrval_bneg+1)
	MOV		VREG_ADR1+1, >(addrval_bneg+1)
addrval_b:
	MOV		VREG_STEP0, 0		; this will be set to value from [b]
	XFER		VREG_PORT1, (0)		; read once and advance port0 by [b], but step1 is still 0
	MOV		VREG_STEP0, 0		; dont advance now, we need this value twice
	XFER		VREG_PORT1, (0)		; read -[b] and store at addrval_bneg
	MOV		VREG_ADR1, <(addrval_bneg2+1)
	MOV		VREG_ADR1+1, >(addrval_bneg2+1)
	XFER		VREG_PORT1, (0)		; read -[b] and store at addrval_bneg2

	;; is [a]-[b]>0?
	MOV		VREG_STEP1, 0	; PORT1 will be written thrice, we only want to know last value
	MOV		VREG_ADR0,   <(signtable+$100)	; middle of the table, position of '0'
	MOV		VREG_ADR0+1, >(signtable+$100)	; middle of the table, position of '0'
	MOV		VREG_ADR1, <(setaval+1)
	MOV		VREG_ADR1+1, >(setaval+1)
addrval_a:
	MOV		VREG_STEP0, 0		; step here will be [a] value (-128,127)
	XFER		VREG_PORT1, (0)		; read value at 0, move from 0 to [a] value
addrval_bneg:
	MOV		VREG_STEP0, 0		; step here will be -[b] value (-128,127)
	XFER		VREG_PORT1, (0)		; read value at [a], move from [a] to -[b] value
	XFER		VREG_PORT1, (0)		; finally read sign of subtraction result - 0 to skip BRA or <>0 to run BRA

	;; what is the actual value [a]-[b]?
	MOV		VREG_STEP1, 0	; PORT1 will be written thrice, we only want to know last value
	MOV		VREG_ADR0,   <(subtable+$100)	; middle of the table, position of '0'
	MOV		VREG_ADR0+1, >(subtable+$100)	; middle of the table, position of '0'
addr2_2:
	;; store result in b
	MOV		VREG_ADR1, 0		; this will be modified
	MOV		VREG_ADR1+1, 0		; this will be modified
addrval_a2:
	MOV		VREG_STEP0, 0		; step here will be [a] value (-128,127)
	XFER		VREG_PORT1, (0)		; read value at 0, move from 0 to [a] value
addrval_bneg2:
	MOV		VREG_STEP0, 0		; step here will be -[b] value (-128,127)
	XFER		VREG_PORT1, (0)		; read value at [a], move from [a] to -[b] value
	XFER		VREG_PORT1, (0)		; finally read subtraction result, store at addr2

setaval:
	SETA	0					; this will be modified
	DECA						; if A==0 branch will not be taken, when [a]>[b]
	BRA		pcleq				; branch if A<>0

pcpos:
	MOV		VREG_ADR0, 0		; branch not taken, take next instruction
	MOV		VREG_ADR0+1, 0
	BRA		mainback; loop

pcleq:
	MOV		VREG_ADR0, 0		; branch taken
	MOV		VREG_ADR0+1, 0
	BRA		mainback; loop

.export signtable
.export subtable
.export negtable
.export vm_start
.export isseven
.export three
.export five

signtable:
	.repeat 256	; negative numbers
	.byte 1
	.endrepeat
	.byte 1		; zero
	.repeat 255	; positive numbers
	.byte 0
	.endrepeat

subtable:
	.repeat 128
	.byte <(-128)	; negative overflow
	.endrepeat
	.repeat 256, I
	.byte <(-128+I)	; -128, -127, ..., 0, 1, 2, 3, ..., 127
	.endrepeat
	.repeat 128
	.byte 127	; positive overflow
	.endrepeat

negtable:
	.repeat 128, I
	.byte <(-I)
	.endrepeat
	; 127, 126, ..., 0 (@$80), -1, ..., -127, -128 ; (x :-> -x), but [$7f, ..., 0, $ff, $fe, ..., $80]?

vm_start:

zero:	.byte 0		; literal 0
seven:	.byte 7
three:	.byte 3

two:	.byte 2
five:	.byte 5
isseven:	.byte 0

	; subleq program starts here, addresses must be absolute, not relative to vm_start
	; <negative-jmp> <positive-jmp> <a> <b>; [b]<-[b]-[a]; if [b]-[a]<=0 then [negative-jmp] else [positive-jmp]

	.macro subleq addr_a, addr_b, jump_c
	.ifblank addr_a
		.error "SUBLEQ: first argument required for subleq macro"
	.endif
	.ifnblank jump_c
		.word jump_c	; where to jump if negative
	.else
		.word :+	; if ommited then point to the next instruction
	.endif
		.word :+	; link to next instruction (required for VASYL, not existing in pure Subleq)
		.word addr_a	; [a]
	.ifnblank addr_b
		.word addr_b	; [b], [b]<-[b]-[a]
	.else
		.word addr_a	; if 2nd argument is omitted reuse [a]
	.endif
	:
	.endmacro

	subleq three, seven		; 7-3=4, seven=4
	subleq two, isseven		; 0-2=-2, isseven=-2
	subleq isseven, five		; 5-(-2)=5+2=7, five=7
	subleq isseven			; zero-out location isseven
:	subleq zero, zero, :-		; infinite loop
:	.word :-, :-, zero, zero	; this is also infinite loop

dl_end:
dl_end_opcode:
	END

