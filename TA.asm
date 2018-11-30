;====================================================================
; Processor		: ATmega8515
; Compiler		: AVRASM
;====================================================================

;====================================================================
; DEFINITIONS
;====================================================================

.include "m8515def.inc"
.def last_key_pressed = r14
.def flag_game_start = r15
.def temp = r16 ; temporary register
.def temp_1 = r17
.def number = r18
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

INIT_KEYPAD:
	ldi temp, 0x00
	mov last_key_pressed, temp
	out DDRC, temp

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

	TEST_KEY_PRESSED:
		; Remember to clear the DDRC everytime we scan the keypad
		ldi temp, 0x00
		out DDRC, temp

		; By sending 1s to all row lines, we can get which column is high
		ldi temp, 0b00001111
		out DDRC, temp ; Set Row Lines as Output
		out PORTC, temp ; Sending 1s to Row Lines
		nop
		in temp, PINC ; Read Column result
		cpi temp, 0b00001111 ; All 0s on column means nothing is pressed
		brne KEY_PRESSED

		; When nothing is pressed, we simulate falling edge trigger
		; Which mean key is only processed when user release the button
		mov temp, last_key_pressed
		cpi temp, 0x00
		brne KEY_CHECK
		rjmp TEST_KEY_PRESSED

	KEY_PRESSED:
		; By sending 1s to all column lines, we can get which row as high
		ldi temp_1, 0b11110000
		out DDRC, temp_1 ; Set Column Lines as Output
		out PORTC, temp_1 ; Sending 1s to Column Lines
		nop
		in temp_1, PINC ; Read Row result
		and temp, temp_1 ; Combining the two, we can get which button is pressed
		mov last_key_pressed, temp ; Save the button to a register to simulate falling edge trigger
		rjmp TEST_KEY_PRESSED

	KEY_CHECK:
		; Clear last key pressed
		ldi temp_1, 0x00
		mov last_key_pressed, temp_1

		; Check for ENTER and CLEAR
		cpi temp, 0b00100001
		breq KEY_ENTER
		cpi temp, 0b10000001
		breq KEY_CLEAR

		; If last column is pressed (Left, Right, Up, Down), immediately goes back to scanning
		; We do not use those column
		sbrc temp, 4
		rjmp TEST_KEY_PRESSED

		; This means that the remaining possibilities are number keys
		; We check if the guess has in 2 digits (as our guess within 0 to 99)
		; If so, we go back to scanning keypad
		mov temp_1, guess
		subi temp_1, 10
		brsh TEST_KEY_PRESSED

		rcall MULTIPLY_BY_TEN ; All number key operation means the digit is shifted to left

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
		rjmp TEST_KEY_PRESSED

		KEY_ENTER:
			rjmp TEST_KEY_PRESSED
		KEY_CLEAR:
			rjmp TEST_KEY_PRESSED
		KEY_0:
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_1:
			subi temp_1, -1
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_2:
			subi temp_1, -2
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_3:
			subi temp_1, -3
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_4:
			subi temp_1, -4
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_5:
			subi temp_1, -5
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_6:
			subi temp_1, -6
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_7:
			subi temp_1, -7
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_8:
			subi temp_1, -8
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED
		KEY_9:
			subi temp_1, -9
			mov guess, temp_1
			rjmp TEST_KEY_PRESSED

;====================================================================
; CODE SEGMENT | SUBROUTINE
;====================================================================

; This subroutine will replace temp_1 with guess * 10
; Will replace data in temp_1
MULTIPLY_BY_TEN:
	ldi temp_1, 10
	mul guess, temp_1
	mov temp_1, r0
	ret
