;====================================================================
; Processor		: ATmega8515
; Compiler		: AVRASM
;====================================================================

;====================================================================
; DEFINITIONS
;====================================================================

.include "m8515def.inc"
.def game_start = r15
.def temp = r16 ; temporary register
.def number = r17 ; 

;====================================================================
; RESET and INTERRUPT VECTORS
;====================================================================

.org RESET
rjmp MAIN
.org INT0
rjmp SET_GAME_START
.org INT1
rjmp ext_int1


;====================================================================
; CODE SEGMENT
;====================================================================
SET_GAME_START:
	ldi temp, 1
	mov game_start, temp
	reti

MAIN:

INIT_STACK:
	ldi temp, low(RAMEND)
	ldi temp, high(RAMEND)
	out SPH, temp

INIT_LED:
	ser temp ; load $FF to temp
	out DDRC,temp ; Set PORTA to output

INIT_INTERRUPT:
	ldi temp,0b00001010
	out MCUCR,temp
	ldi temp,0b11000000
	out GICR,temp
	sei

INIT_GAME_DATA:
	ldi temp, 0
	mov game_start, temp
	ldi number, 0

GENERATE_NUMBER:
	inc number
	cpi number, 100
	brne TEST_START
	ldi number, 0

	TEST_START
	tst game_start
	breq GENERATE_NUMBER

GAME_START:
