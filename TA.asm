;====================================================================
; Processor		: ATmega8515
; Compiler		: AVRASM
;====================================================================

                                        
; _____ _____ _____ _____ _____          
;|   __|  |  |   __|   __|   __|         
;|  |  |  |  |   __|__   |__   |         
;|_____|_____|_____|_____|_____|         
;                                        
;                                        
; _____ _____ _____                      
;|_   _|  |  |   __|                     
;  | | |     |   __|                     
;  |_| |__|__|_____|                     
;                                        
;                                     __ 
; _____ _____ _____ _____ _____ _____|  |
;|   | |  |  |     | __  |   __| __  |  |
;| | | |  |  | | | | __ -|   __|    -|__|
;|_|___|_____|_|_|_|_____|_____|__|__|__|
;                                        
;
;
; BY: ANDRE,CAHYA AND NAFIS
;
;====================================================================
; DEFINITIONS
;====================================================================

.include "m8515def.inc"
.def last_key_pressed = r14
.def flag_game_start = r15
.def temp = r16
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
rjmp MAIN // Main game as a start function
.org $01
rjmp SET_GAME_START // Starts the game
.org $02
rjmp NEXT_GAME // Next level 
.org $07
rjmp ISR_TOV0 // Timer overflow subroutine

;====================================================================
; CODE SEGMENT
;====================================================================
SET_GAME_START: // As set game start is a subroutine, we need to anticipate suppose that 
	cp handler1, r1 //the user presses the start 2 or more times to be disabled so that the user does not break the program
	brne DO_NONE // DO NONE  ignores the sub routine
	inc handler1 // increments handler1 and 2
	inc handler2
	ldi timerIndicator, 0x01 // sets the timer
	ldi levelIndicator, 0x31 // sets the starting level
	ldi temp, 0x30 // score starts from 0
	mov score, temp
	rcall CLEAR_LCD // clears
	rcall LEVEL_WRITE // writes level point and write
	rcall POINT_WRITE
	rcall TIME_WRITE
	ldi temp, 1
	mov flag_game_start, temp // indicate game start
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

WELCOME: // Welcome message for the user
	rcall CLEAR_LCD
	ldi ZH, high(startMessage * 2)
	ldi ZL, low(startMessage * 2)
	rcall LOADBYTE
	rcall GO_DOWN
	ldi ZH, high(byMessage * 2)
	ldi ZL, low(byMessage * 2)
	rcall LOADBYTE

INIT_TIMER:
	ldi temp, (1<<CS01 | 1<<CS00)	; set timer control register, 1/64 of Ck
	out TCCR0, temp
	ldi temp, 1<<TOV0	; Set interrupt in timer 0 on overflow
	out TIFR, temp
	ldi temp, 1<<TOIE0	; Enable timer 0 overflow interrupt	; 
	out TIMSK, temp
	ser temp

INIT_INTERRUPT: // initialize global ecternal interrupt
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

GENERATE_NUMBER: // generate number function to create the number
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

		CHECK_TIMELOSS: // Function to check if the user has lost the level by time
			cpi timerLost,0x01 // when the time is over timerLost values becomes 0x01, hence indicates that the user has lost by time
			breq TEST// if it equals  goes to TEST
			ret

		CHECK_NUM:
			cp number,guess // check if the users number is the same as the number inside the register
			breq TEST// if so, goes to TEST
			brne TRY_AGAIN // if its not equal goes to try again

		TRY_AGAIN: // check if the value of the number generated with the user input
			cp guess, number
			brlt KURANG // if its less than, goes to KURANG
			brge LEBIH_SAMA // if its more, goes to LEBIH SAMA

		KURANG: // Indicates that the users input number value is too low
			rcall CLEAR_SECOND_ROW
			rcall LOWER_WRITE
			rcall LOADBYTE
			ldi r27, 0b11000000
			out PORTA, r27
			rcall DELAY_01 
			rjmp CONTINUE

		LEBIH_SAMA: // checks whether the number is more or equal
			cp guess, number // checks
			breq TEST// if its equal go to TEST
			; masih kelebihan
			rcall CLEAR_SECOND_ROW// else prints that the number is still to large
			rcall HIGHER_WRITE
			rcall LOADBYTE
			ldi r27, 0b00001100
			out PORTA, r27
			rcall DELAY_01
			rjmp CONTINUE

		CONTINUE:
			rcall DELAY_01 // multiple delay functions to indicate the users input the higher lower message so it doesnt be deleted directly
			rcall DELAY_01
			rcall DELAY_01
			rcall DELAY_01
			rcall DELAY_01
			ldi guess, 0 // resets guess
			rcall CLEAR_SECOND_ROW
			rcall LOADBYTE
			rjmp PRINT_GUESS // re prints guess
			ret

		TEST:
			; guess correct led
			ldi r27, 0b00110000
			out PORTA, r27
			cpi levelIndicator, 0x39 // check if its already on the last level
			breq forever // if so jumps to forever
			dec flag_game_start// if not  flag indicates to 0x00
			ldi timerIndicator, 0x00 // loads the timer Indicator as a resetter for the time
			mov handler2, timerIndicator // move to handler 2 to activate next button
			ldi guess, 0 // reset guess
			rcall CLEAR_SECOND_ROW // clears the second row
			rcall LOADBYTE
			rcall GO_DOWN//go down
			rcall DECIDER// check decider
			rcall LOADBYTE
			rjmp GENERATE_NUMBER
		
		DECIDER:// decider to check if the user has lost the level or not
			cpi timerLost, 0x01  // timer is over the time limit
			breq LOSE_LEVEL// jumps to the lose_level branch
			inc score// if user does not lose increments score
			rcall SCORE_WRITE// writes score
			cpi levelIndicator, 0x38// check if its on 1 level before the final
			breq PRINT_FINAL// if so prints oh noes message
			rcall READY_WRITE // if its not on the last level means the user is correct , prints noce ready message into the LCD
			rcall LOADBYTE 
			ret
			
		PRINT_FINAL: // Indicate and writes the final level message
			rcall CLEAR_SECOND_ROW 
			rcall GO_DOWN
			rcall FINAL_WRITE
			rcall LOADBYTE
			ret		

		LOSE_LEVEL: // writes if the user lost the current level
			cpi levelIndicator,0x38
			breq PRINT_FINAL
			rcall NOOB_WRITE
			ret

		forever: // forever function is a function before the game finishes where it shows the users final score and the thank you message
			rcall CLEAR_LCD
			rcall END_SCORE_WRITE
			mov A,score
			rcall WRITE_TEXT
			ldi temp,0x30
			mov A,temp
			rcall WRITE_TEXT
			rcall GO_DOWN
			rcall THANK_YOU_WRITE
			ldi timerIndicator,0x00	//disable timer
			rjmp eternal

		eternal: // eternal loop
			rjmp eternal

NEXT_GAME:
		ldi r27, 0b00000000 // suppose that the user has won/lost reprepare for the next level
		out PORTA, r27
		cp handler2,r1 // handler2 a flag register to make deactivate/activate the next button
		brne DO_NOTHING // if its equal to 0, do nothing (unpressable)
		inc handler2 // else increments
		rcall CHANGE_LEVEL // change level into the lcd
		rcall CLEAR_SECOND_ROW
		rcall LOADBYTE
		rcall GO_DOWN
		ldi r26,0x01
		ldi timerIndicator,0x01 // indicate timer 
		ldi timerLost,0x00		// reset timer lost
		mov flag_game_start,r26 //inidcate flag game
		reti

DO_NOTHING:
	reti // do nothing
	

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
	subi temp_1, 10			; If current guess is higher than 10
	brsh SET_SECOND_DIGIT	; that means the pressed key is on second digit

	SET_FIRST_DIGIT:		; else the pressed key is on first digit
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

DELAY:	; A single cycle delay that somehow makes the keypad works
	nop
	ret

;==========================================================
; LCD WRITER FUNCTION
;==========================================================
;

CLEAR_SECOND_ROW:	; Literally clearing the second row by printing spaces
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

GO_DOWN: // Function to go to bit address 64 (staring point of bottom)
	cbi PORTA, 1
	ldi PB, 0xC0
	out PORTB, PB
	sbi PORTA, 0
	cbi PORTA, 0
	ret

LEVEL_WRITE: // Function to word level on to the LCD
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

SCORE_WRITE: // Function to show the current score of the user
	cbi PORTA, 1
	ldi PB, 0x90
	out PORTB, PB
	sbi PORTA, 0
	cbi PORTA, 0
	mov PB,score
	mov A,PB
	rcall WRITE_TEXT
	ret

POINT_WRITE: // Function to write the point word into the LCD
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

TIME_WRITE: // Function to write the time word into the LCD
	ldi ZH, high(time * 2)
	ldi ZL, low(time * 2)
	rcall LOADBYTE
	ret

CHANGE_LEVEL_LCD: // A function to increment the level and writes it to the LCD
	subi levelIndicator, -1
	mov A, levelIndicator
	cbi PORTA, 1
	ldi PB, 0x88
	out PORTB, PB
	sbi PORTA, 0
	cbi PORTA, 0
	rcall WRITE_TEXT
	ret

SEPARATOR_WRITE: //writes separator
	ldi ZH, high(pipe * 2)
	ldi ZL, low(pipe * 2)
	rcall LOADBYTE
	ret	

FINAL_WRITE: // writes the oh noes final level word into the LCD
	ldi ZH, high(final * 2)
	ldi ZL, low(final * 2)
	rcall LOADBYTE
	ret	

END_SCORE_WRITE: // writes the you got: word into the LCD
	ldi ZH, high(endScore * 2)
	ldi ZL, low(endScore * 2)
	rcall LOADBYTE
	ret

THANK_YOU_WRITE: // writes thank you message into LCD
	ldi ZH, high(thankyou*2)
	ldi ZL,low(thankyou*2)
	rcall LOADBYTE
	ret

READY_WRITE: //writes if the user is ready for the next level or not onto the LCD
	rcall GO_DOWN
	ldi ZH, high(ready * 2)
	ldi ZL, low(ready * 2)
	rcall LOADBYTE
	ret

HIGHER_WRITE: // writes  if the user inputs a number higher than the number generated
	rcall GO_DOWN
	ldi ZH, high(higher * 2)
	ldi ZL, low(higher * 2)
	rcall LOADBYTE
	ret

LOWER_WRITE: // writes  if the user inputs a number lower than the number generated
	rcall GO_DOWN
	ldi ZH, high(lower * 2)
	ldi ZL, low(lower * 2)
	rcall LOADBYTE
	ret
	
NOOB_WRITE:// writes  if the user has lost the level
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

ISR_TOV0:	; One second of timer is approximately 24 times overflow on clock/64
	cpi timerIndicator, 0
	breq BACK
	mov keep_1, temp
	mov keep_2, temp_1
	ldi temp, one_sec_overflow
	inc counter					; Keep counting the number of overflow
	cp counter, temp			; until it reaches 24
	brne RETURN_TIME_INTERRUPT

	DECREASE_TIMER_DISPLAY:
		ldi temp, 0x00			; Checking the ones of the seconds
		cp ones, temp			; If it is 0, we got a slightly more complex case
		brne NORMAL_DECREMENT	; else it's a normal and easy decrement
	
	CHECK_TIME_RUN_OUT:			; If the ones is 0, then we have to check the tens
		cp tenths, temp			; If the tens is 0 too, the timer have reach 00 (End)
		brne TENTHS_DECREMENT	; else it just a decrement of tens (Like from 50 to 49)
		rjmp TIMER_RUN_OUT
	
	NORMAL_DECREMENT:			; On normal decrement, just decrease the ones and print the timer
		dec ones
		rjmp PRINT_TIMER_DISPLAY
	
	TENTHS_DECREMENT:			; On tenths decrement, we decrease the tenths and set ones to 9
		ldi temp, 9
		mov ones, temp
		dec tenths
		rjmp PRINT_TIMER_DISPLAY
	
	PRINT_TIMER_DISPLAY:		; Simple printing on a predetermined location
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

	TIMER_RUN_OUT:				; If the timer run out, well then the level is lost,here all time is resetted
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

DELAY_01:
	; Generated by delay loop calculator
	; at http://www.bretmulvey.com/avrdelay.html
	;
	; DELAY_CONTROL 40 000 cycles
	; 5ms at 8.0 MHz

	    ldi  r28, 52
	    ldi  r29, 242
	L1: dec  r29
	    brne L1
	    dec  r28
	    brne L1
	    nop
	ret

;=====================================================================
; Data
;=====================================================================

endScore:
.db "You got:",0

thankyou:
.db "Thank you for playing",0


startMessage:
.db "Welcome to Guess the Number!",0

byMessage:
.db "   By:Andre Cahya & Nafis",0

noob:
.db "    Ckck...next level...",0

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
.db "  Your number is too HIGH",0

lower:
.db "   Your number is too LOW",0

guess_text:
.db "GUESS:",0

clear_second_row_text:
.db "                              ", 0
