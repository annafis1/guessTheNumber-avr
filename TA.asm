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
.def timerLost = r25
.def keep_1 = r9
.def keep_2 = r10
.def tenths = r11
.def ones = r12
.def counter = r13
.def PB = r22 ; for PORTB


; Register for interrupt handler
.def handler1 = r6
.def handler2 = r5

; Register for games
.def score = r8
.def levelIndicator = r23
.def timerIndicator = r24

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
.org $01
rjmp SET_GAME_START
.org $02
rjmp NEXT_GAME
.org $07
rjmp ISR_TOV0

;====================================================================
; CODE SEGMENT
;====================================================================
SET_GAME_START:
	cp handler1, r1 
	brne DO_NONE
	inc handler1
	inc handler2
	ldi timerIndicator, 0x01
	ldi levelIndicator, 0x31
	ldi temp, 0x30
	mov score, temp
	rcall CLEAR_LCD
	rcall LEVEL_WRITE
	rcall POINT_WRITE
	rcall TIME_WRITE
	ldi temp, 1
	mov flag_game_start, temp
	reti

DO_NONE:
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

WELCOME:
	rcall CLEAR_LCD
	ldi ZH, high(startMessage * 2)
	ldi ZL, low(startMessage * 2)
	rcall LOADBYTE
	rcall GO_DOWN
	ldi ZH, high(byMessage * 2)
	ldi ZL, low(byMessage * 2)
	rcall LOADBYTE

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
			rcall CHECK_TIMELOSS
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
			rcall CHECK_NUM 
			rjmp SCANNING_KEYPAD
		KEY_CLEAR:
			ldi guess, 0
			rcall CLEAR_SECOND_ROW
			rcall LOADBYTE
			rjmp PRINT_GUESS
		KEY_0:
			tst guess
			breq SCANNING_KEYPAD_JUMPER
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

		SCANNING_KEYPAD_JUMPER:
			rjmp SCANNING_KEYPAD

		CHECK_TIMELOSS:
			cpi timerLost,0x01
			breq TEST
			ret

		CHECK_NUM:
			cp number,guess
			breq TEST
			brne TRY_AGAIN
			; ldi guess, 0
			; rcall CLEAR_SECOND_ROW
			; rcall LOADBYTE
			; rjmp PRINT_GUESS
			; ret

		TRY_AGAIN:
			cp guess, number
			brlt KURANG
			brge LEBIH_SAMA

		KURANG:
			ldi r27, 0b11000000
			out PORTA, r27
			rjmp CONTINUE

		LEBIH_SAMA:
			cp guess, number
			breq TEST
			; masih kelebihan
			ldi r27, 0b00001100
			out PORTA, r27
			rjmp CONTINUE

		CONTINUE:
			ldi guess, 0
			rcall CLEAR_SECOND_ROW
			rcall LOADBYTE
			rjmp PRINT_GUESS
			ret

		TEST:
			; guess correct led
			ldi r27, 0b00110000
			out PORTA, r27

			cpi levelIndicator, 0x39
			breq forever
			dec flag_game_start
			ldi timerIndicator, 0x00
			mov handler2, timerIndicator
			ldi guess, 0
			rcall CLEAR_SECOND_ROW
			rcall LOADBYTE
			rcall GO_DOWN
			rcall DECIDER
			rcall LOADBYTE
			rjmp GENERATE_NUMBER
		
		DECIDER:
			cpi timerLost, 0x01
			breq LOSE_LEVEL
			inc score
			rcall SCORE_WRITE
			cpi levelIndicator, 0x38
			breq PRINT_FINAL
			rcall READY_WRITE
			rcall LOADBYTE
			ret
			
		PRINT_FINAL:
			rcall FINAL_WRITE
			rcall LOADBYTE
			ret		

		LOSE_LEVEL:
			cpi levelIndicator,0x38
			breq PRINT_FINAL
			rcall NOOB_WRITE
			ret

		forever:
			rcall CLEAR_LCD
			rjmp forever

NEXT_GAME:
		ldi r27, 0b00000000
		out PORTA, r27
		cp handler2,r1
		brne DO_NOTHING
		inc handler2
		rcall CHANGE_LEVEL
		rcall CLEAR_SECOND_ROW
		rcall LOADBYTE
		rcall GO_DOWN
		ldi r26,0x01
		ldi timerIndicator,0x01
		ldi timerLost,0x00
		mov flag_game_start,r26
		reti

DO_NOTHING:
	reti
	

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

END_LCD:
	sei 
	ret

WRITE_TEXT:
	sbi PORTA, 1 ; SETB RS
	out PORTB, A
	sbi PORTA, 0 ; SETB EN
	cbi PORTA, 0 ; CLR EN
	ret

GO_DOWN:
	cbi PORTA, 1
	ldi PB, 0xC0
	out PORTB, PB
	sbi PORTA, 0
	cbi PORTA, 0
	ret

LEVEL_WRITE:
	ldi ZH, high(level * 2)
	ldi ZL, low(level * 2)
	rcall LOADBYTE
	ldi PB, 0x30
	mov A, PB
	rcall WRITE_TEXT
	mov A, levelIndicator
	rcall WRITE_TEXT
	rcall SEPARATOR_WRITE

	ret

SCORE_WRITE:
	cbi PORTA, 1
	ldi PB, 0x90
	out PORTB, PB
	sbi PORTA, 0
	cbi PORTA, 0
	mov PB,score
	mov A,PB
	rcall WRITE_TEXT
	ret

POINT_WRITE:
	ldi ZH, high(point * 2)
	ldi ZL, low(point * 2)
	rcall LOADBYTE
	ldi PB, 0x30
	mov A, PB
	rcall WRITE_TEXT
	ldi PB, 0x30
	mov A, PB
	rcall WRITE_TEXT
	rcall SEPARATOR_WRITE
	ret

TIME_WRITE:
	ldi ZH, high(time * 2)
	ldi ZL, low(time * 2)
	rcall LOADBYTE
	ret

CHANGE_LEVEL_LCD:
	subi levelIndicator, -1
	mov A, levelIndicator
	cbi PORTA, 1
	ldi PB, 0x88
	out PORTB, PB
	sbi PORTA, 0
	cbi PORTA, 0
	rcall WRITE_TEXT
	ret

SEPARATOR_WRITE:
	ldi ZH, high(pipe * 2)
	ldi ZL, low(pipe * 2)
	rcall LOADBYTE
	ret	

FINAL_WRITE:
	ldi ZH, high(final * 2)
	ldi ZL, low(final * 2)
	rcall LOADBYTE
	ret	

READY_WRITE:
	rcall GO_DOWN
	ldi ZH, high(ready * 2)
	ldi ZL, low(ready * 2)
	rcall LOADBYTE
	ret
	
NOOB_WRITE:
	ldi ZH, high(noob * 2)
	ldi ZL, low(noob * 2)
	rcall LOADBYTE
	ret

;=================================================
;CHANGE LEVEL
;=================================================
CHANGE_LEVEL:
		ldi temp, 0
		mov counter, temp
		ldi temp, 5
		mov tenths, temp
		ldi temp, 0x0A
		mov ones, temp
		rcall CHANGE_LEVEL_LCD
		ret

;=====================================================================
; TIMER INTERRUPT ON OVERFLOW SUBROUTINE
;=====================================================================
; A 1 second subroutine for The timer

ISR_TOV0:
	cpi timerIndicator, 0
	breq BACK
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
		ldi temp, 0
		mov counter, temp
		cbi PORTA, 1
		ldi PB, 0x98
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
		ldi temp, 0
		mov counter, temp
		ldi temp, 5
		mov tenths, temp
		ldi temp, 0x0A
		mov ones, temp
		ldi timerLost, 0x01
		rjmp RETURN_TIME_INTERRUPT
	
	RETURN_TIME_INTERRUPT:
		mov temp, keep_1
		mov temp_1, keep_2
		reti
	
	BACK:
		reti

;=====================================================================
; Data
;=====================================================================

startMessage:
.db "Welcome to Guess the Number!",0

byMessage:
.db "   By:Andre Cahya & Nafis",0

noob:
.db "    Noob...next level...",0

ready:
.db "      Nice... ready?",0

final:
.db "   OH NOES! Final Level !!!",0

level:
.db " Level:",0

point:
.db "Point:",0

time:
.db "Time:",0

pipe:
.db "|",0

timesUp:
.db "TIMES UP!",0 

higher:
.db "HIGHER!",0

lower:
.db "LOWER!",0

guess_text:
.db "GUESS:",0

clear_second_row_text:
.db "                             ", 0
