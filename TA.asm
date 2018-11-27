;====================================================================
; Processor		: ATmega8515
; Compiler		: AVRASM
;====================================================================

;====================================================================
; DEFINITIONS
;====================================================================

.include "m8515def.inc"
.def flag_game_start = r15
.def temp = r16 ; temporary register
.def temp_1 = r17
.def number = r18 ; 
.def number_digit_0 = r19
.def number_digit_1 = r20
.def guess = r21

;====================================================================
; RESET and INTERRUPT VECTORS
;====================================================================

.org $00
rjmp MAIN
.org INT0
rjmp SET_GAME_START
; .org INT1
; rjmp ext_int1

;====================================================================
; CODE SEGMENT
;====================================================================
SET_GAME_START:
	ldi temp, 1
	mov flag_game_start, temp
	reti

MAIN:

INIT_STACK:
	ldi temp, low(RAMEND)
	ldi temp, high(RAMEND)
	out SPH, temp

INIT_LED:
	ser temp ; load $FF to temp
	out DDRC, temp ; Set PORTA to output

INIT_INTERRUPT:
	ldi temp, 0b00001010
	out MCUCR, temp
	ldi temp, 0b11000000
	out GICR, temp
	sei

INIT_GAME_DATA:
	ldi temp, 0
	mov flag_game_start, temp
	ldi number, 1
	ldi number_digit_0, 1
	ldi number_digit_1, 0
	ldi guess, 0

GENERATE_NUMBER:
	inc number
	inc number_digit_0

	cpi number_digit_0, 10
	brne CHECK_SECOND_DIGIT
	inc number_digit_1
	ldi number_digit_0, 0

	CHECK_SECOND_DIGIT:
	cpi number_digit_1, 10
	brne TEST_IF_GAME_START
	ldi number, 1
	ldi number_digit_0, 1
	ldi number_digit_1, 0

	TEST_IF_GAME_START:
	;tst flag_game_start
	;breq GENERATE_NUMBER

GAME_START:
	; Insert LED and LCD related things here
	; Codes below are dummy, for testing keypad only
	; Still problematic, keypad are being read too fast | Currently fixed by using 200ms delay
	INIT_KEYPAD:
		rcall DELAY_200ms
		ldi temp, 0x00
		out DDRC, temp

	TEST_KEY_PRESSED:
		; By sending 1s to all row lines, we can get which column is high
		ldi temp, 0b00001111
		out DDRC, temp ; Set Row Lines as Output
		out PORTC, temp ; Sending 1s to Row Lines
		nop
		in temp, PINC ; Read Column result
		cpi temp, 0b00001111
		brne KEY_PRESSED
		rjmp TEST_KEY_PRESSED

	KEY_PRESSED:
		; By sending 1s to all column lines, we can get which row as high
		ldi temp_1, 0b11110000
		out DDRC, temp_1 ; Set Column Lines as Output
		out PORTC, temp_1 ; Sending 1s to Column Lines
		nop
		in temp_1, PINC ; Read Row result
		and temp, temp_1 ; Combining the two, we can get which button is pressed

		cpi temp, 0b01000001
		breq KEY_0
		cpi temp, 0b10001000
		breq KEY_1
		cpi temp, 0b01001000
		breq KEY_2
		cpi temp, 0b00101000
		breq KEY_3
		cpi temp, 0b10000100
		breq KEY_4
		cpi temp, 0b01000100
		breq KEY_5
		cpi temp, 0b00100100
		breq KEY_6
		cpi temp, 0b10000010
		breq KEY_7
		cpi temp, 0b01000010
		breq KEY_8
		cpi temp, 0b00100010
		breq KEY_9
		rjmp INIT_KEYPAD

		KEY_0:
			mov temp, guess
			subi temp, 10
			brsh KEY_0_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			mov guess, temp
			KEY_0_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_1:
			mov temp, guess
			subi temp, 10
			brsh KEY_1_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -1
			mov guess, temp
			KEY_1_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_2:
			mov temp, guess
			subi temp, 10
			brsh KEY_2_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -2
			mov guess, temp
			KEY_2_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_3:
			mov temp, guess
			subi temp, 10
			brsh KEY_3_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -3
			mov guess, temp
			KEY_3_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_4:
			mov temp, guess
			subi temp, 10
			brsh KEY_4_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -4
			mov guess, temp
			KEY_4_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_5:
			mov temp, guess
			subi temp, 10
			brsh KEY_5_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -5
			mov guess, temp
			KEY_5_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_6:
			mov temp, guess
			subi temp, 10
			brsh KEY_6_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -6
			mov guess, temp
			KEY_6_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_7:
			mov temp, guess
			subi temp, 10
			brsh KEY_7_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -7
			mov guess, temp
			KEY_7_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_8:
			mov temp, guess
			subi temp, 10
			brsh KEY_8_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -8
			mov guess, temp
			KEY_8_BACK_TO_SCAN:
			rjmp INIT_KEYPAD
		KEY_9:
			mov temp, guess
			subi temp, 10
			brsh KEY_9_BACK_TO_SCAN
			rcall MULTIPLY_BY_TEN
			subi temp, -9
			mov guess, temp
			KEY_9_BACK_TO_SCAN:
			rjmp INIT_KEYPAD

;====================================================================
; CODE SEGMENT | SUBROUTINE
;====================================================================

; This subroutine will replace temp with guess * 10
; Will replace data in temp and temp_1
MULTIPLY_BY_TEN:
	mov temp, guess
	ldi temp_1, 10
	mul temp, temp_1
	mov temp, r0
	ret

DELAY_200ms:
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	rcall DELAY_20ms
	ret

DELAY_20ms:
	; Generated by delay loop calculator
	; at http://www.bretmulvey.com/avrdelay.html
	;
	; Delay 80 000 cycles
	; 20ms at 4 MHz

    	ldi  temp, 104
    	ldi  temp_1, 229
	L1: dec  temp_1
		brne L1
		dec  temp
		brne L1
