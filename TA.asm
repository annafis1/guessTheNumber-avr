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

; Registers for Timer
.def keep_1 = r9
.def keep_2 = r10
.def tenths = r11
.def ones = r12
.def counter = r13
.def PB = r22 ; for PORTB

; Register for LCD
.def A = r7

; CONSTANTS
.equ one_sec_overflow = 24
.equ location_of_guess_first_digit = 0xC6
.equ location_of_guess_second_digit = 0xC7

;====================================================================
; RESET and INTERRUPT VECTORS
;====================================================================

.org $00
rjmp MAIN
.org INT0
rjmp SET_GAME_START
.org $07
rjmp ISR_TOV0

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

INITIALIZER:
	ldi temp, 6
	mov tenths, temp
	ldi temp, 0
	mov ones, temp
	mov counter, temp

INIT_LCD:
	cbi PORTA,1 ; CLR RS
	ldi PB,0x38 ; MOV DATA,0x38 --> 8bit, 2line, 5x7
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$0E ; MOV DATA,0x0E --> disp ON, cursor ON, blink OFF
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	rcall CLEAR_LCD ; CLEAR LCD
	cbi PORTA,1 ; CLR RS
	ldi PB,$06 ; MOV DATA,0x06 --> increase cursor, display sroll OFF
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN

INIT_TIMER:
	ldi temp, (1<<CS01 | 1<<CS00)	; set timer control register, 1/8 of Ck
	out TCCR0, temp
	ldi temp, 1<<TOV0	; Set interrupt in timer 0 on overflow
	out TIFR, temp
	ldi temp, 1<<TOIE0	; Enable timer 0 overflow interrupt	; 
	out TIMSK, temp
	ser temp

INIT_INTERRUPT:
	ldi temp, 0b00001010
	out MCUCR, temp
	ldi temp, 0b11000000
	out GICR, temp
	sei

INIT_KEYPAD:
	ldi temp, 0x00
	mov last_key_pressed, temp

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
		tst flag_game_start
		breq GENERATE_NUMBER

GAME_START:
	; Insert LED and LCD related things here

	; Failsafe for broken SREG by timer interrupt
	tst flag_game_start
	breq GENERATE_NUMBER

	PRINT_GUESS:
		cbi PORTA, 1
		ldi PB, 0xC0
		out PORTB, PB
		sbi PORTA, 0
		cbi PORTA, 0
		ldi ZH, high(guess_text * 2)
		ldi ZL, low(guess_text * 2)
		rcall LOADBYTE

	SCANNING_KEYPAD:
		POWER_UP_ROW:
			; By powering all row lines, we can detect the column of pressed key
			ldi temp, 0b00001111
			out DDRC, temp ; Set row lines as output
			out PORTC, temp ; Powering row lines

		READ_COLUMN:
			rcall DELAY
			in temp, PINC ; Read the column
			cpi temp, 0b00001111 ; If all column is low, no key is pressed
			brne POWER_UP_COLUMN

		FALLING_EDGE_TRIGGER:
			; When nothing is pressed, we simulate falling edge trigger
			; Which mean key is only processed when user release the button
			mov temp, last_key_pressed
			cpi temp, 0x00
			brne KEY_CHECK
			rjmp READ_COLUMN

		POWER_UP_COLUMN:
			; By powering all column lines, we can detect the column of pressed key
			ldi temp_1, 0b11110000
			out DDRC, temp_1 ; Set row lines as output
			out PORTC, temp_1 ; Powering row lines

		READ_ROW:
			rcall DELAY
			in temp_1, PINC ; Read the row
			cpi temp, 0b11110000 ; Failsafe for fast key press
			breq POWER_UP_ROW
			and temp, temp_1 ; Combining the two, we can get which button is pressed
			
			mov temp_1, last_key_pressed	; We are not going to process the button
			cpi temp_1, 0x00				; If we're not yet processing the previous button
			brne POWER_UP_ROW

			mov last_key_pressed, temp ; Save the button to a register to simulate falling edge trigger
			rjmp POWER_UP_ROW

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
		rjmp SCANNING_KEYPAD

		; This means that the remaining possibilities are number keys
		; We check if the guess has in 2 digits (as our guess within 0 to 99)
		; If so, we go back to scanning keypad
		mov temp_1, guess
		subi temp_1, 10
		brsh SCANNING_KEYPAD

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
		rjmp SCANNING_KEYPAD

		KEY_ENTER:
			rjmp SCANNING_KEYPAD
		KEY_CLEAR:
			ldi guess, 0
			rcall CLEAR_SECOND_ROW
			rcall LOADBYTE
			rjmp PRINT_GUESS
		KEY_0:
			tst guess
			breq SCANNING_KEYPAD
			mov guess, temp_1
			ldi temp_1, 0x30
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_1:
			subi temp_1, -1
			mov guess, temp_1
			ldi temp_1, 0x31
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_2:
			subi temp_1, -2
			mov guess, temp_1
			ldi temp_1, 0x32
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_3:
			subi temp_1, -3
			mov guess, temp_1
			ldi temp_1, 0x33
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_4:
			subi temp_1, -4
			mov guess, temp_1
			ldi temp_1, 0x34
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_5:
			subi temp_1, -5
			mov guess, temp_1
			ldi temp_1, 0x35
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_6:
			subi temp_1, -6
			mov guess, temp_1
			ldi temp_1, 0x36
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_7:
			subi temp_1, -7
			mov guess, temp_1
			ldi temp_1, 0x37
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_8:
			subi temp_1, -8
			mov guess, temp_1
			ldi temp_1, 0x38
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD
		KEY_9:
			subi temp_1, -9
			mov guess, temp_1
			ldi temp_1, 0x39
			mov A, temp_1
			rcall PRINT_KEY
			rjmp SCANNING_KEYPAD

CLEAR_LCD:
	cbi PORTA,1 ; CLR RS
	ldi PB,$01 ; MOV DATA,0x01
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	ret

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

PRINT_KEY:
	mov A, temp_1
	mov temp_1, guess
	subi temp_1, 10
	brsh SET_SECOND_DIGIT

	SET_FIRST_DIGIT:
		cbi PORTA, 1
		ldi PB, location_of_guess_first_digit
		out PORTB, PB
		sbi PORTA, 0
		cbi PORTA, 0
		rjmp PRINT_THE_KEY
	SET_SECOND_DIGIT:
		cbi PORTA, 1
		ldi PB, location_of_guess_second_digit
		out PORTB, PB
		sbi PORTA, 0
		cbi PORTA, 0
		rjmp PRINT_THE_KEY
	
	PRINT_THE_KEY:
		rcall WRITE_TEXT
		ret

DELAY:
	nop
	ret

;==========================================================
; LCD WRITER FUNCTION
;==========================================================
;

CLEAR_SECOND_ROW:
	cbi PORTA, 1
	ldi PB, 0xC0
	out PORTB, PB
	sbi PORTA, 0
	cbi PORTA, 0
	ldi ZH, high(clear_second_row_text * 2)
	ldi ZL, low(clear_second_row_text * 2)
	ret

LOADBYTE:
	lpm ; Load byte from program memory into r0
	tst r0 ; Check if we've reached the end of the message
	breq END_LCD ; If so, quit
	mov A, r0 ; Put the character onto Port B
	rcall WRITE_TEXT
	adiw ZL,1 ; Increase Z registers
	rjmp LOADBYTE

WRITE_TEXT:
	sbi PORTA, 1 ; SETB RS
	out PORTB, A
	sbi PORTA, 0 ; SETB EN
	cbi PORTA, 0 ; CLR EN
	ret

END_LCD:
	sei 
	ret

;=====================================================================
; TIMER INTERRUPT ON OVERFLOW SUBROUTINE
;=====================================================================
; A 1 second subroutine for The timer

ISR_TOV0:
	mov keep_1, temp
	mov keep_2, temp_1
	ldi temp, one_sec_overflow
	inc counter
	cp counter, temp
	brne RETURN_TIME_INTERRUPT

	DECREASE_TIMER_DISPLAY:
		ldi temp, 0x00
		cp ones, temp
		brne NORMAL_DECREMENT
	
	CHECK_TIME_RUN_OUT:
		cp tenths, temp
		brne TENTHS_DECREMENT
		rjmp TIMER_RUN_OUT
	
	NORMAL_DECREMENT:
		dec ones
		rjmp PRINT_TIMER_DISPLAY
	
	TENTHS_DECREMENT:
		ldi temp, 9
		mov ones, temp
		dec tenths
		rjmp PRINT_TIMER_DISPLAY
	
	PRINT_TIMER_DISPLAY:
		mov temp, tenths
		mov temp_1, ones
		or temp, temp_1
		cpi temp, 0
		breq TIMER_RUN_OUT		

		ldi temp, 0
		mov counter, temp
		cbi PORTA, 1
		ldi PB, 0x80	; Move to DRAM 0, subject to change
		out PORTB, PB
		sbi PORTA, 0
		cbi PORTA, 0
		mov temp, tenths
		subi temp, -48
		mov A, temp
		rcall WRITE_TEXT
		mov temp, ones
		subi temp, -48
		mov A, temp
		rcall WRITE_TEXT
		rjmp RETURN_TIME_INTERRUPT

	TIMER_RUN_OUT:
		ldi temp, 6
		mov tenths, temp
		ldi temp, 0
		mov ones, temp
		mov counter, temp
		cbi PORTA, 1
		ldi PB, 0x80	; Move to DRAM 0, subject to change
		out PORTB, PB
		sbi PORTA, 0
		cbi PORTA, 0
		ldi ZH, high(2 * timesUp) ; Load high part of byte address into ZH
		ldi ZL, low(2 * timesUp) ; Load high part of byte address into ZH
		rcall LOADBYTE
		rjmp RETURN_TIME_INTERRUPT
	
	RETURN_TIME_INTERRUPT:
		mov temp, keep_1
		mov temp_1, keep_2
		reti

;=====================================================================
; Data
;=====================================================================

timesUp:
.db "TIMES UP!",0 

higher:
.db "HIGHER!",0

lower:
.db "LOWER!",0

guess_text:
.db "GUESS:", 0

clear_second_row_text:
.db "        ", 0
