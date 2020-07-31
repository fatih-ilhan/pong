;///////////////////////////////////////////////////////////////////////////
; Authors	: Fatih Ilhan, Yunus Akdagli
; Description	: Multiplayer Pong Game 
;
; One of the earliest video games - PONG - is implemented in Assembly for a
; 8051 family microcontroller. This is a two-player game where each player
; controls the paddle using his/her hand. The distance between the hand and
; the ultrasonic sensor determines the position of the paddle. Game is being
; displayed on a 8x32 matrix where the half for game map and half for score
; displays. Gameflow can be interrupted via pushbuttons. Additional 
; informative messages about the game are on a LCD. 
;
; NOTES:
;
; 1) 8x32 LED Matrix interfaced with the microcontroller through three pins.
;	 The data is being sent through p3.5 (DIN) serially. The MAX7219's
;	 writes each 8-bit data to the relevant registers and then sends to the
;	 led matrices column by column.
;
; 2) ...
;
;
;***************************************************************************
;***************************************************************************

ORG 0H

MOV 38H,#04H				;constant for randomization


;///////////////////////////////////////////////////////////////////////////
;initialization of the game
;called once at the beginning of each match
;***************************************************************************

INIT:
MOV 36H,#0				;clear the score of the down paddle(p1) 
MOV 37H,#0				;clear the score of the up paddle(p2) 
MOV P1, #0				;make p1 output for LCD data
CLR RS					;make p3.0 output for LCD 
CLR RW					;make p3.1 output for LCD 
CLR E					;make p3.2 output for LCD 
SETB RST				;make p2.6 input for reset button
SETB PAUSE_START			;make p2.7 input for pause/start button
SETB 34H				;game state flag, if zero continue
ACALL CONFIGURE_LCD
CLR DIN					;make p3.5 output for serial data to led matrix
CLR LOAD				;make p3.6 output for load signal to led matrix
CLR CLK					;make p3.7 output for clock signal to led matrix
CLR TRIG_1				;make p3.0 output for trigger signal to sensor 1
SETB ECHO_1				;make p3.1 input for echo signal of sensor 1
CLR TRIG_2				;make p2.0 output for trigger signal to sensor 2
SETB ECHO_2				;make p2.1 input for echo signal of sensor 2
MOV TMOD, #21H 				;timer 0 in mode 1, timer 1 in mode 2
ACALL CONFIGURE_LEDM
ACALL CLEAR_LEDM
ACALL LCD_BEGINNING
ACALL SCORE_LEDM
CLR 36H					;flag for game state
SETB 37H				;flag for game state


;///////////////////////////////////////////////////////////////////////////
;sub-configuration of the match
;called once for each score event
;***************************************************************************

MAIN:
MOV R0,#00H
MOV R1,#00H
ACALL INITIALIZE_MAP
ACALL DRAW_MAP
ACALL DIRECTION_SET
MOV SP,#07H
MOV R1,#43H				;the adress of the column of the ball (40h->4Fh)
MOV 31H,#4CH 				;the adress of the left part of the up paddle
MOV 32H,#44H 				;the adress of the left part of the down paddle
MOV 33H,#04H				;the horizontal zone of the down(p1) paddle (1->7)
MOV 34H,#04H				;the horizontal zone of the up paddle(p2) (1->7)
MOV 35H,#00H				;parameter of the ball speed
CLR 33H					;ball is in map 2 (setb => map3)
CLR 35H					;flag for game state
SJMP LOOP


;///////////////////////////////////////////////////////////////////////////
;the essential loop of the game 
;called once for each game period
;game period depends on the periods of the ball, paddle movements and the 
;other processes
;most of the I/0 and the gameflow is controlled here
;***************************************************************************

CONTINUE5:
JNB 36H, LOOP
MOV A, #0C0H
ACALL SEND_COMMAND
MOV DPTR, #PAUSE_STRING
ACALL WRITE_STR
CLR 36H
LOOP:
ACALL RAND_GEN
JNB RST, INIT
JB PAUSE_START,CONTINUE
JNB 35H,CONTINUE
CPL 34H
CONTINUE:
MOV C,PAUSE_START
MOV 35H,C
JB 34H, CONTINUE5
JB 36H, CONTINUE4
MOV A, #0C0H
ACALL SEND_COMMAND
JB 37H, BEGINNING
MOV DPTR, #NEW_ROUND_STR
ACALL WRITE_STR
SETB 36H
BEGINNING:
MOV DPTR, #START_STRING
ACALL WRITE_STR
CLR 37H
CONTINUE4:
ACALL PADDLE_MOVEMENT_1
ACALL PADDLE_MOVEMENT_2
ACALL DRAW_MAP
ACALL DELAY_BALL
ACALL BALL_MOVEMENT
SJMP LOOP


;///////////////////////////////////////////////////////////////////////////
;subroutine for the movement of the p1 (down)
;builds a linear correlation between the hand's distance from the sensor and
;the zone of the paddle, controls availability for the movement, updates the
;display accordingly
;***************************************************************************


PADDLE_MOVEMENT_1:
PUSH 0
CLR A
MOV TL1, #245
MOV TH1, #245				;tr1 will count 11 times (gives ~0.2cm resolution)
SETB TRIG_1				;trig the sensor 1 with a 10us signal
ACALL DELAY_10US
CLR TRIG_1
JNB ECHO_1,$  				;waits here until echo starts
BACK_1: 
SETB TR1    				;starts the timer1
JNB TF1,$   				;loops here until timer overflows (11 count)
CLR TF1     				;clears timer flag 1
CLR TR1
INC A       				;increments A for every timer1 overflow (~0.2 cm)
CJNE A,#200,$+3
JNC NO_UPDATE_EXIT_1			;does not wait echo anymore if it is more than 1m
JB ECHO_1,BACK_1    			;jumps to BACK_1 if echo is continuing
MOV B,#15D
DIV AB					;each zone has 3 cm of range, A holds the new zone

;if the hand is closer than 3 cm or further than 27 cm, skips

CJNE A,#01H,RANGE_CONTROL_1
SJMP CASE_CONTROL_1
RANGE_CONTROL_1:
JC NO_UPDATE_EXIT_1
CJNE A,#08H,$+3
JNC NO_UPDATE_EXIT_1

;detects the direction of the movement and calls update and delay 
;subroutines

CASE_CONTROL_1:
PUSH ACC
CJNE A,33H,CASE_CONTROLX_1
SJMP EXIT_1
CASE_CONTROLX_1:
JC CASE1_1
CLR C
SUBB A,33H
MOV 63H,A
AGAIN1_1:
ACALL LEFT_1
ACALL DRAW_MAP
ACALL DELAY_PADDLE
DJNZ 63H, AGAIN1_1
SJMP EXIT_1
CASE1_1:
DEC 33H
DJNZ ACC,CASE1_1
AGAIN2_1:
ACALL RIGHT_1
ACALL DRAW_MAP
ACALL DELAY_PADDLE
DJNZ 33H, AGAIN2_1

EXIT_1:
POP 33H
POP 0
RET

NO_UPDATE_EXIT_1:
POP 0
RET

LEFT_1:
MOV R0,32H
DEC R0
DEC @R0
INC R0
INC R0
INC 32H
INC @R0
RET

RIGHT_1:
MOV R0, 32H
DEC R0
DEC R0
INC @R0
INC R0
INC R0
DEC @R0
DEC 32H
RET


;///////////////////////////////////////////////////////////////////////////
;subroutine for the movement of the p2 (up)
;builds a linear correlation between the hand's distance from the sensor and
;the zone of the paddle, controls availability for the movement, updates the
;display accordingly
;this is a bit different from PADDLE_MOVEMENT_1, because of minor 
;differences in control and movement conditions
;***************************************************************************

PADDLE_MOVEMENT_2:
PUSH 0
CLR A
MOV TL1, #245				;tr1 will count 11 times (gives ~0.2cm resolution)
MOV TH1, #245				;trig the sensor 1 with a 10us signal
SETB TRIG_2
ACALL DELAY_10US
CLR TRIG_2
JNB ECHO_2,$  				;waits here until echo starts
BACK_2: 
SETB TR1    				;starts the timer1
JNB TF1,$   				;loops here until timer overflows (11 count)
CLR TF1     				;clears timer flag 1
CLR TR1
INC A       				;increments A for every timer1 overflow (~0.2 cm)
CJNE A,#200,$+3
JNC NO_UPDATE_EXIT_2			;does not wait echo anymore if it is more than 1m
JB ECHO_2,BACK_2    			;jumps to BACK_1 if echo is continuing
MOV B,#15d
DIV AB					;each zone has 3 cm of range, A holds the new zone

;if the hand is closer than 3 cm or further than 27 cm, skips

CJNE A,#01H,RANGE_CONTROL_2
SJMP CASE_CONTROL_2
RANGE_CONTROL_2:
JC NO_UPDATE_EXIT_2
CJNE A,#08H,$+3
JNC NO_UPDATE_EXIT_2

;detects the direction of the movement and calls update and delay 
;subroutines

CASE_CONTROL_2:
PUSH ACC
CJNE A,34H,CASE_CONTROLX_2
SJMP EXIT_2
CASE_CONTROLX_2:
JC CASE1_2 ;CASE1 -> A<34H
CLR C
SUBB A,34H
MOV 64H,A
AGAIN1_2:
ACALL RIGHT_2
ACALL DRAW_MAP
ACALL DELAY_PADDLE
DJNZ 64H, AGAIN1_2
SJMP EXIT_2
CASE1_2:
DEC 34H
DJNZ ACC,CASE1_2
AGAIN2_2:
ACALL LEFT_2
ACALL DRAW_MAP
ACALL DELAY_PADDLE
DJNZ 34H, AGAIN2_2

EXIT_2:
POP 34H
POP 0
RET

NO_UPDATE_EXIT_2:
POP 0
RET

LEFT_2:
MOV R0,31H
DEC R0
MOV A,@R0
ANL A,#7FH
MOV @R0,A
INC R0
INC R0
MOV A,@R0
ORL A,#80H
MOV @R0,A
INC 31H
RET

RIGHT_2:
MOV R0,31H
MOV A,@R0
ANL A,#7FH
MOV @R0,A
DEC R0
DEC R0
MOV A,@R0
ORL A,#80H
MOV @R0,A
DEC 31H
RET


;///////////////////////////////////////////////////////////////////////////////
;subroutine for the ball movement
;sends to relevant directives after controlling the direction flags
;*******************************************************************************

BALL_MOVEMENT:
START:
JNB 70H,SKIP1				;if direction flag points upright, enter upright control	
LJMP URC

SKIP1:
JNB 71H,SKIP2				;if direction flag points downright, enter downright control
LJMP DRC

SKIP2:
JNB 72H,SKIP3				;if direction flag points upleft, enter upleft control
LJMP ULC

SKIP3:
JNB 73H,START				;if direction flag points downleft, enter downleft control
LJMP DLC

FINISH:
RET


;///////////////////////////////////////////////////////////////////////////////
;controls the availability of upright movement of the ball
;if it passes, makes the movement in UPRIGHT; if it can not, updates the flags 
;accordingly and jumps back to the main flag control
;*******************************************************************************

URC:
JB 33H, Ca
SJMP URC1				;map 2
Ca:
LJMP URC2				;map 3


URC1:
CJNE R1,#40H,GO2a1 			;if ball hits the right wall
CLR 70H					;clear upright flag
SETB 72H     				;set upleft flag
ACALL A2b_10MS
LJMP START				;returns to the flag control
GO2a1:
SJMP UPRIGHT1				;passed the control

UPRIGHT1:
MOV A,@R1
JNB ACC.7,CONT1a
SETB 33H
ANL A,#01H
MOV @R1,A
MOV A,R1
ADD A,#07
MOV R1,A
INC @R1
LJMP FINISH
CONT1a:
ANL A,#0FEH 
RL A
DEC R1
ORL A,@R1
MOV @R1,A
INC R1
MOV A,@R1
ANL A,#01H
MOV @R1,A
DEC R1
LJMP FINISH

URC2:
PUSH 31H
CJNE R1,#48H,GO1a2 			;if ball hits the right wall
CLR 70H					;clear upright flag
SETB 72H     				;set upleft flag
ACALL A2b_10MS
SJMP GO5a2				;return to flag control
GO1a2:					;else
MOV A,@R1
JNB ACC.6,GO2a2				;if ball is about the hit the upper paddle or drop into upper space
DEC 31H
MOV A,R1
CJNE A,31H,GO3a2			;if ball hits the right part of the upper paddle
CLR 70H					;clear upright flag
SETB 71H				;set downright flag
ACALL A2b_10MS
SJMP GO5a2				;return to flag control
GO3a2:
INC 31H
CJNE A,31H,GO4a2			;if ball hits the left part of the upper paddle
CLR 70H					;clear upright flag
SETB 71H				;set downright flag
ACALL A2b_10MS
SJMP GO5a2				;return to flag control
GO4a2:
INC 31H
CJNE A,31H,GO6a2			;if ball hits the left corner of the upper paddle
CLR 70H					;clear upright flag
SETB 73H				;set downleft control
ACALL A2b_10MS
SJMP GO5a2

;score for down player, initialize map, update scores etc.
GO6a2:
INC 36H
ACALL UPDATE_SCORE
POP 31H
LJMP MAIN
GO5a2:					;returns back the adress of the left part of the upper paddle
POP 31H
LJMP START				;returns to the flag control
GO2a2:
POP 31H 
SJMP UPRIGHT2				;passed the control

UPRIGHT2:
MOV A,@R1
ANL A,#7FH 
RL A
DEC R1
ORL A,@R1
MOV @R1,A
INC R1
MOV A,@R1
ANL A,#80H
MOV @R1,A
DEC R1
LJMP FINISH

;///////////////////////////////////////////////////////////////////////////////
;controls the availability of upleft movement of the ball
;if it passes makes the movement in UPLEFT; if it can not, updates the flags 
;accordingly and jumps back to the main flag control
;*******************************************************************************

ULC:
JB 33H, Cb
SJMP ULC1				;map 2
Cb:
LJMP ULC2				;map 3

ULC1:
CJNE R1,#47H,GO2b1 			;if ball hits the left wall
CLR 72H					;clear upleft flag
SETB 70H     				;set upright flag
ACALL A2b_10MS
LJMP START				;returns to the flag control
GO2b1:
SJMP UPLEFT1				;passed the control

UPLEFT1:
MOV A,@R1
JNB ACC.7,CONT1b
SETB 33H
ANL A,#01H
MOV @R1,A
MOV A,R1
ADD A,#09
MOV R1,A
INC @R1
LJMP FINISH
CONT1b:
ANL A,#0FEH 
RL A
INC R1
ORL A,@R1
MOV @R1,A
DEC R1
MOV A,@R1
ANL A,#01H
MOV @R1,A
INC R1
LJMP FINISH

ULC2:
PUSH 31H
CJNE R1,#4FH,GO1b2 			;if ball hits the left wall
CLR 72H					;clear upleft flag
SETB 70H     				;set upright flag
ACALL A2b_10MS
SJMP GO5b2				;return to flag control
GO1b2:					;else
MOV A,@R1
JNB ACC.6,GO2b2				;if ball is about the hit the upper paddle or drop into upper space
MOV A,R1
CJNE A,31H,GO3b2			;if ball hits the left part of the upper paddle
CLR 72H					;clear upleft flag
SETB 73H				;set downleft flag
ACALL A2b_10MS
SJMP GO5b2				;return to flag control
GO3b2:
DEC 31H
CJNE A,31H,GO4b2			;if ball hits the right part of the upper paddle
CLR 72H					;clear upleft flag
SETB 73H				;set downleft flag
ACALL A2b_10MS
SJMP GO5b2				;return to flag control
GO4b2:
DEC 31H
CJNE A,31H,GO6b2			;if ball hits the right corner of the upper paddle
CLR 72H					;clear upleft flag
SETB 71H				;set downright control
ACALL A2b_10MS
SJMP GO5b2

;score for down player, initialize map, update scores etc.
GO6b2:
INC 36H
ACALL UPDATE_SCORE
POP 31H
LJMP MAIN
GO5b2:
POP 31H
LJMP START				;returns to the flag control
GO2b2: 
POP 31H
SJMP UPLEFT2				;passed the control

UPLEFT2:
MOV A,@R1
ANL A,#7FH 
RL A
INC R1
ORL A,@R1
MOV @R1,A
DEC R1
MOV A,@R1
ANL A,#80H
MOV @R1,A
INC R1
LJMP FINISH


;///////////////////////////////////////////////////////////////////////////////
;controls the availability of downright movement of the ball
;if it passes makes the movement in DOWNRIGHT; if it can not, updates the flags 
;accordingly and jumps back to the main flag control
;*******************************************************************************

DRC:
JB 33H, Cc
SJMP DRC1				;map 2
Cc:
LJMP DRC2				;map 3

DRC1:
PUSH 32H
CJNE R1,#40H,GO1c1 			;if ball hits the right wall
CLR 71H					;clear downright flag
SETB 73H     				;set downleft flag
ACALL A2b_10MS
SJMP GO5c1				;return to flag control
GO1c1:					;else
MOV A,@R1
JNB ACC.1,GO2c1				;if ball is about the hit the lower paddle or drop into lower space
MOV A,R1
DEC 32H
CJNE A,32H,GO3c1			;if ball hits the right part of the lower paddle
CLR 71H					;clear downright flag
SETB 70H				;set upright flag
ACALL A2b_10MS
SJMP GO5c1				;return to flag control
GO3c1:
INC 32H
CJNE A,32H,GO4c1			;if ball hits the left part of the lower paddle
CLR 71H					;clear downright flag
SETB 70H				;set upright flag
ACALL A2b_10MS
SJMP GO5c1				;return to flag control
GO4c1:
INC 32H
CJNE A,32H,GO6c1			;if ball hits the left corner of the lower paddle
CLR 71H					;clear downright flag
SETB 72H				;set upleft flag
ACALL A2b_10MS
SJMP GO5c1

;score for up player, initialize map, update scores etc.
GO6c1:
INC 37H
ACALL UPDATE_SCORE
POP 32H
LJMP MAIN
GO5c1:
POP 32H					;returns back the adress of the left part of the upper paddle
LJMP START				;returns to the flag control
GO2c1:
POP 32H
SJMP DOWNRIGHT1				;passed the control

DOWNRIGHT1:
MOV A,@R1
ANL A,#0FEH
RR A
DEC R1
ORL A,@R1
MOV @R1,A
INC R1
MOV A,@R1
ANL A,#01H
MOV @R1,A
DEC R1
LJMP FINISH

DRC2:
CJNE R1,#48H,GO2c2 			;if ball hits the right wall
CLR 71H					;clear  downright flag
SETB 73H     				;set downleft flag
ACALL A2b_10MS
LJMP START				;returns to the flag control
GO2c2:
SJMP DOWNRIGHT2				;passed the control

DOWNRIGHT2:
MOV A,@R1
JNB ACC.0,CONT2c
CLR 33H
ANL A,#80H
MOV @R1,A
MOV A,R1
CLR C
SUBB A,#09
MOV R1,A
MOV A,@R1
ORL A,#80H
MOV @R1,A
LJMP FINISH
CONT2c:
ANL A,#7FH
RR A
DEC R1
ORL A,@R1
MOV @R1,A
INC R1
MOV A,@R1
ANL A,#80H
MOV @R1,A
DEC R1
LJMP FINISH


;///////////////////////////////////////////////////////////////////////////////
;controls the availability of downleft movement of the ball
;if it passes makes the movement in DOWNLEFT; if it can not, updates the flags 
;accordingly and jumps back to the main flag control
;*******************************************************************************

DLC:
JB 33H, Cd
SJMP DLC1				;map 2
Cd:
LJMP DLC2				;map 3

DLC1:
PUSH 32H
CJNE R1,#47H,GO1d1 			;if ball hits the left wall
CLR 73H					;clear downleft flag
SETB 71H     				;set downright flag
ACALL A2b_10MS
SJMP GO5d1				;return to flag control
GO1d1:					;else
MOV A,@R1
JNB ACC.1,GO2d1				;if ball is about the hit the lower paddle or  drop into lower space
MOV A,R1
CJNE A,32H,GO3d1			;if ball hits the left part of the upper paddle
CLR 73H					;clear downleft flag
SETB 72H				;set upleft flag
ACALL A2b_10MS
SJMP GO5d1				;return to flag control
GO3d1:
DEC 32H
CJNE A,32H,GO4d1			;if ball hits the right part of the upper paddle
CLR 73H					;clear downleft flag
SETB 72H				;set upleft flag
ACALL A2b_10MS
SJMP GO5d1				;return to flag control
GO4d1:
DEC 32H
CJNE A,32H,GO6d1			;if ball hits the right corner of the upper paddle
CLR 73H					;clear downleft flag
SETB 70H				;set upright control
ACALL A2b_10MS
SJMP GO5d1

;score for down player, initialize map, update scores etc.
GO6d1:
INC 37H
ACALL UPDATE_SCORE
POP 32H
LJMP MAIN
GO5d1:
POP 32H					;returns back the adress of the left part of the upper paddle
LJMP START				;returns to the flag control
GO2d1:
POP 32H
SJMP DOWNLEFT1				;passed the control

DOWNLEFT1:
MOV A,@R1
ANL A,#0FEH 
RR A
INC R1
ORL A,@R1
MOV @R1,A
DEC R1
MOV A,@R1
ANL A,#01H
MOV @R1,A
INC R1
LJMP FINISH

DLC2:
CJNE R1,#4FH,GO2d2 			;if ball hits the left wall
CLR 73H					;clear downleft flag
SETB 71H     				;set downright flag
ACALL A2b_10MS
LJMP START				;returns to the flag control
GO2d2:
SJMP DOWNLEFT2

DOWNLEFT2:
MOV A,@R1
JNB ACC.0,CONT2d
CLR 33H
ANL A,#80H
MOV @R1,A
MOV A,R1
CLR C
SUBB A,#07h
MOV R1,A
MOV A,@R1
ORL A,#80H
MOV @R1,A
LJMP FINISH
CONT2d:
ANL A,#7FH
RR A
INC R1
ORL A,@R1
MOV @R1,A
DEC R1
MOV A,@R1
ANL A,#80H
MOV @R1,A
INC R1
LJMP FINISH


;///////////////////////////////////////////////////////////////////////////////
;configures max7219 once at the beginning
;*******************************************************************************

CONFIGURE_LEDM:
MOV A,#REG_DECODE
MOV B,#00H				;no-decode mode
ACALL WRITE0
MOV A,#REG_INTENSITY
MOV B,#07H				;brightness is medium
ACALL WRITE0
MOV A,#REG_SCAN_LIMIT
MOV B,#07H				;scan all columns
ACALL WRITE0
MOV A,#REG_SHUTDOWN
MOV B,#01H				;enable
ACALL WRITE0
MOV A,#REG_DISPLAY_TEST
MOV B,#00H				;enable
ACALL WRITE0
RET


;///////////////////////////////////////////////////////////////////////////////
;clears all columns of the led matrix
;*******************************************************************************

CLEAR_LEDM:
MOV R0,#01H
MOV R7,#08H
BACK5:
MOV A,R0
MOV B,#00H
ACALL WRITE0
INC R0
DJNZ R7,BACK5
RET


;///////////////////////////////////////////////////////////////////////////////
;sends two bytes serially (register address + data)
;information is sent when the load is high
;0 -> all maps
;1,2,3,4 -> matrix selection
;*******************************************************************************

;all maps
WRITE0:
SETB LOAD
ACALL SEND_BYTE
MOV A,B
ACALL SEND_BYTE
CLR LOAD
SETB LOAD
RET

;3 NOOP + MAP1
WRITE1:
SETB LOAD
ACALL NOOP
ACALL NOOP
ACALL NOOP
ACALL SEND_BYTE
MOV A,B
ACALL SEND_BYTE
CLR LOAD
SETB LOAD
RET

;2 NOOP + MAP2 + NOOP
WRITE2:
SETB LOAD
ACALL NOOP
ACALL NOOP
ACALL SEND_BYTE
MOV A,B
ACALL SEND_BYTE
ACALL NOOP
CLR LOAD
SETB LOAD
RET

;NOOP + MAP3 + 2NOOP
WRITE3:
SETB LOAD
ACALL NOOP
ACALL SEND_BYTE
MOV A,B
ACALL SEND_BYTE
ACALL NOOP
ACALL NOOP
CLR LOAD
SETB LOAD
RET

;MAP4 + 3NOOP
WRITE4:
SETB LOAD
ACALL SEND_BYTE
MOV A,B
ACALL SEND_BYTE
ACALL NOOP
ACALL NOOP
ACALL NOOP
CLR LOAD
SETB LOAD
RET


;///////////////////////////////////////////////////////////////////////////////
;sends 8 bits serially 
;each bit is latched in max7219 in the rising edges of CLK
;*******************************************************************************

SEND_BYTE:
CLR C
MOV 30H,#08H
AGAIN:
RLC A
CLR CLK
MOV DIN,C
SETB CLK
DJNZ 30H,AGAIN
RET


;///////////////////////////////////////////////////////////////////////////////
;delays in different amount of times
;*******************************************************************************

DELAY_1S:
MOV R3,#7
B1: MOV R4,#00
B2: MOV R5,#00
DJNZ R5,$
DJNZ R4,B2
DJNZ R3,B1
RET

DELAY_500MS:
MOV R3,#7
B3: MOV R4,#128
B4: MOV R5,#00
DJNZ R5,$
DJNZ R4,B4
DJNZ R3,B3
RET

DELAY_100MS:
MOV R3,#7
B5: MOV R4,#51
B6: MOV R5,#128
DJNZ R5,$
DJNZ R4,B6
DJNZ R3,B5
RET

DELAY_10US:
NOP
NOP
NOP
NOP
NOP
NOP
NOP
RET

;delay for ball movement 
;speed increases gradually (~140ms -> ~20ms)
DELAY_BALL: 
MOV R5,35H
HERE1:MOV R4,#0
DJNZ R4,$
DJNZ R5,HERE1
MOV A,35H
CJNE A,#40D,CONT3
SJMP SKIP4
CONT3:
DEC 35H
SKIP4:
RET

;delay for paddle movement (~5.5ms)
DELAY_PADDLE: ;5.5MS
MOV R5,#10 
HERE2:MOV R4,#0
DJNZ R4,$
DJNZ R5,HERE2
RET


;///////////////////////////////////////////////////////////////////////////////
;draws game maps one by one (2-3)
;*******************************************************************************

DRAW_MAP:
ACALL DRAW_MAP_2
ACALL DRAW_MAP_3
RET

;///////////////////////////////////////////////////////////////////////////////
;draws 8 columns of map 1 one by one (57h -> 50h)
;*******************************************************************************

DRAW_MAP_1:
MOV R0,#57H
MOV R7,#08H
MOV R6,#08H
BACK6:
MOV A,R6
MOV B,@R0
ACALL WRITE1
DEC R0
DEC R6
DJNZ R7,BACK6
RET

;///////////////////////////////////////////////////////////////////////////////
;draws 8 columns of map 2 one by one (47h -> 40h)
;*******************************************************************************

DRAW_MAP_2:
MOV R0,#47H
MOV R7,#08H
MOV R6,#08H
BACK3:
MOV A,R6
MOV B,@R0
ACALL WRITE2
DEC R0
DEC R6
DJNZ R7,BACK3
RET


;///////////////////////////////////////////////////////////////////////////////
;draws 8 columns of map 3 one by one (4Fh -> 48h)
;*******************************************************************************

DRAW_MAP_3:
MOV R0,#4FH
MOV R7,#08H
MOV R6,#08H
BACK4:
MOV A,R6
MOV B,@R0
ACALL WRITE3
DEC R0
DEC R6
DJNZ R7,BACK4
RET


;///////////////////////////////////////////////////////////////////////////////
;draws 8 columns of map 4 one by one (5Fh -> 58h)
;*******************************************************************************

DRAW_MAP_4:
MOV R0,#5FH
MOV R7,#08H
MOV R6,#08H
BACK7:
MOV A,R6
MOV B,@R0
ACALL WRITE4
DEC R0
DEC R6
DJNZ R7,BACK7
RET


;///////////////////////////////////////////////////////////////////////////////
;initializes LCD 
;*******************************************************************************

LCD_BEGINNING:
MOV A, #80H				;cursor position for the first line
ACALL SEND_COMMAND
MOV DPTR, #BEGIN_SCORE
ACALL WRITE_STR
MOV DPTR, #BEGIN_STR
MOV A, #0C0H				;cursor position for the second line
ACALL SEND_COMMAND
ACALL WRITE_STR
RET


;///////////////////////////////////////////////////////////////////////////////
;configures LCD 
;*******************************************************************************

CONFIGURE_LCD:				;this subroutine sends the initialization commands to the lcd
MOV A,#38H				;two lines, 5x7 matrix
ACALL SEND_COMMAND
MOV A,#0FH				;display on, cursor blinking
ACALL SEND_COMMAND
MOV A,#06H				;increment cursor (shift cursor to right)
ACALL SEND_COMMAND
MOV A,#01H				;clear display screen
ACALL SEND_COMMAND
MOV A,#80H				;force cursor to beginning of the first line
ACALL SEND_COMMAND
RET

SEND_COMMAND:				;this  subroutine is for sending the commands to lcd
MOV P1,A				;the command is stored in a, send it to lcd
CLR RS				;rs=0 before sending command
CLR RW				;r/w=0 to write
SETB E				;send a high to low signal to enable pin
ACALL DELAY
CLR E
RET

SEND_DATA:				;this  subroutine is for sending the data to be displayed
MOV P1,A				;send the data stored in a to lcd
SETB RS				;rs=1 before sending data
CLR RW				;r/w=0 to write
SETB E				;send a high to low signal to enable pin
ACALL DELAY
CLR E
RET

DELAY:					;a short delay subroutine for lcd
PUSH 0
PUSH 1
MOV R0,#50
DELAY_OUTER_LOOP:
MOV R1,#255
DJNZ R1,$
DJNZ R0,DELAY_OUTER_LOOP
POP 1
POP 0
RET


;///////////////////////////////////////////////////////////////////////////////
;shows the score and messages on LCD
;*******************************************************************************

UPDATE_SCORE:
ACALL FAIL_BEEP
ACALL SCORE_LEDM

MOV A, #85H				;position of the cursor at the first line
ACALL SEND_COMMAND

MOV A, 36H              		;score of player 1
MOV B,#10
DIV AB
ADD A, #30H
ACALL SEND_DATA
MOV A,B
ADD A, #30H
ACALL SEND_DATA
MOV A, #':'
ACALL SEND_DATA
MOV A, 37H				;score of player 2
MOV B,#10
DIV AB
ADD A, #30H
ACALL SEND_DATA
MOV A,B
ADD A, #30H
ACALL SEND_DATA

MOV A, #0C0H				;cursor position for the second line
ACALL SEND_COMMAND

JB 33H, P1_SCORES
MOV DPTR,#P2_STRING
HERE:
CLR A
MOVC A, @A+DPTR
JZ NEW_ROUND
ACALL SEND_DATA
INC DPTR
SJMP HERE

P1_SCORES:
MOV DPTR,#P1_STRING
HERE_3:
CLR A
MOVC A, @A+DPTR
JZ NEW_ROUND
ACALL SEND_DATA
INC DPTR
SJMP HERE_3

NEW_ROUND:
ACALL DELAY_1S
MOV A, #0C0H				;cursor position for the second line
ACALL SEND_COMMAND
MOV A, 36H
CLR C
SUBB A, #11
JNZ CONTINUE2
CPL 34H
MOV DPTR, #GAMEOVER_STR
ACALL WRITE_STR
ACALL ENDING_WHISTLE
MOV DPTR, #P1_WON
MOV A, #0C0H				;cursor position for the second line
ACALL SEND_COMMAND
ACALL WRITE_STR
ACALL DELAY_1S
ACALL DELAY_1S
LJMP INIT
CONTINUE2:
MOV A, 37H
CLR C
SUBB A,#11
JNZ CONTINUE3
CPL 34H
MOV DPTR, #GAMEOVER_STR
ACALL WRITE_STR
ACALL ENDING_WHISTLE
MOV DPTR, #P2_WON
MOV A, #0C0H				;cursor position for the second line
ACALL SEND_COMMAND
ACALL WRITE_STR
ACALL DELAY_1S
ACALL DELAY_1S
LJMP INIT
CONTINUE3:
MOV DPTR,#NEW_ROUND_STR
ACALL WRITE_STR
RET

;sends each char of the string one by one to LCD
WRITE_STR:
CLR A
MOVC A, @A+DPTR
JZ DONE
ACALL SEND_DATA
INC DPTR
SJMP WRITE_STR
DONE:
RET


;///////////////////////////////////////////////////////////////////////////////
;subroutine for scores on led matrices
;*******************************************************************************

SCORE_LEDM:
ACALL SCORE_LEDM1
ACALL SCORE_LEDM2
RET


;///////////////////////////////////////////////////////////////////////////////
;subroutine for P1 score on led matrix 1
;*******************************************************************************

SCORE_LEDM1:
MOV DPTR,#SCORE_DATA
MOV A,36H
MOV R0,#57H
MOV R7,#08
JZ SKIP9
BACK8:
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
DJNZ ACC,BACK8
SKIP9:
CLR A
MOVC A,@A+DPTR
MOV @R0,A
INC DPTR
DEC R0
DJNZ R7,SKIP9
ACALL DRAW_MAP_1
RET


;///////////////////////////////////////////////////////////////////////////////
;subroutine for P2 score on led matrix 4
;*******************************************************************************

SCORE_LEDM2:
MOV DPTR,#SCORE_DATA
MOV A,37H
MOV R0,#5FH
MOV R7,#08
JZ SKIP10
BACK9:
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
INC DPTR
DJNZ ACC,BACK9
SKIP10:
CLR A
MOVC A,@A+DPTR
MOV @R0,A
INC DPTR
DEC R0
DJNZ R7,SKIP10
ACALL DRAW_MAP_4
RET


;///////////////////////////////////////////////////////////////////////////////
;the data for columns are in 4Fh-40h
;the place of ball and paddles can be updated by modifying these values
;*******************************************************************************

INITIALIZE_MAP:

;map 4
MOV 5FH,#00H
MOV 5EH,#00H
MOV 5DH,#00H
MOV 5CH,#00H
MOV 5BH,#00H
MOV 5AH,#00H
MOV 59H,#00H
MOV 58H,#00H

;map 3
MOV 4FH,#00H
MOV 4EH,#00H
MOV 4DH,#00H
MOV 4CH,#80H
MOV 4BH,#80H
MOV 4AH,#00H
MOV 49H,#00H
MOV 48H,#00H

;map 2
MOV 47H,#00H
MOV 46H,#00H
MOV 45H,#00H
MOV 44H,#01H
MOV 43H,#81H
MOV 42H,#00H
MOV 41H,#00H
MOV 40H,#00H
RET

;map 1
MOV 57H,#00H
MOV 56H,#00H
MOV 55H,#00H
MOV 54H,#00H
MOV 53H,#00H
MOV 52H,#00H
MOV 51H,#00H
MOV 50H,#00H
RET


;///////////////////////////////////////////////////////////////////////////////
;command for module selection
;each noop disables the led matrix
;*******************************************************************************

NOOP:
PUSH ACC
MOV A,#00
ACALL SEND_BYTE
ACALL SEND_BYTE
POP ACC
RET


;///////////////////////////////////////////////////////////////////////////////
;random number generator between 1 and 4
;the value of at 38h when the loop is interrupted will determine the initial
;direction of the ball
;*******************************************************************************

RAND_GEN:
DJNZ 38H,CONT4
MOV 38H,#04H
CONT4:
RET


;///////////////////////////////////////////////////////////////////////////////
;sets the initial direction of the ball depending on the value at 38h
;*******************************************************************************

DIRECTION_SET:
MOV A,38H
CJNE A,#01,SKIP5
SETB 70H 				;ball is going upright direction
CLR 71H
CLR 72H
CLR 73H
RET
SKIP5:
CJNE A,#02,SKIP6
CLR 70H
SETB 71H				;ball is going downright direction
CLR 72H
CLR 73H
RET
SKIP6:
CJNE A,#03,SKIP7
CLR 70H
CLR 71H
SETB 72H				;ball is going upleft direction
CLR 73H
RET
SKIP7:
CJNE A,#04,SKIP8
CLR 70H
CLR 71H
CLR 72H
SETB 73H				;ball is going downleft direction
SKIP8:
RET


;///////////////////////////////////////////////////////////////////////////////
;500 ms of C5 note
;it will be played sequentially when match ends
;*******************************************************************************

C5_500MS:
SETB BUZZER
MOV R4, #2
A2:
MOV R5, #0
A1:
MOV TH0, #HIGH C5_COUNT
MOV TL0, #LOW C5_COUNT
SETB TR0
JNB TF0,$
CLR TR0
CLR TF0
CPL BUZZER
DJNZ R5,A1
DJNZ R4,A2
CLR BUZZER
RET


;///////////////////////////////////////////////////////////////////////////////
;100 ms of C4 note
;it will be played twice when the ball drops
;*******************************************************************************

C4_100MS:
SETB BUZZER
MOV R4, #2
A4:
MOV R5, #51
A3:
MOV TH0, #HIGH C4_COUNT
MOV TL0, #LOW C4_COUNT
SETB TR0
JNB TF0,$
CLR TR0
CLR TF0
CPL BUZZER
DJNZ R5,A3
DJNZ R4,A4
CLR BUZZER
RET


;///////////////////////////////////////////////////////////////////////////////
;10 ms of A2b note
;it will be played once per each ball contact (wall, paddle)
;*******************************************************************************

A2b_10MS:
SETB BUZZER
MOV R4, #2
A6:
MOV R5, #5
A5:
MOV TH0, #HIGH A2b_COUNT
MOV TL0, #LOW A2b_COUNT
SETB TR0
JNB TF0,$
CLR TR0
CLR TF0
CPL BUZZER
DJNZ R5,A5
DJNZ R4,A6
CLR BUZZER
RET


;///////////////////////////////////////////////////////////////////////////////
;ending whistle sound (-.-.---)
;*******************************************************************************

ENDING_WHISTLE:
ACALL C5_500MS
ACALL DELAY_500MS
ACALL C5_500MS
ACALL DELAY_500MS
ACALL C5_500MS
ACALL C5_500MS
ACALL C5_500MS
RET


;///////////////////////////////////////////////////////////////////////////////
;ball drop sound (-.-)
;*******************************************************************************

FAIL_BEEP:
ACALL C4_100MS
ACALL DELAY_100MS
ACALL C4_100MS
RET


;///////////////////////////////////////////////////////////////////////////////
;ball bounce sound 
;*******************************************************************************

BOUNCE_BEEP:
ACALL A2b_10MS
RET

;/////////////////////////////////////////////////////////////
;constants
;*************************************************************

REG_DECODE		EQU 09H		;"DECODE MODE" REGISTER
REG_INTENSITY 		EQU 0AH    	;"INTENSITY" REGISTER
REG_SCAN_LIMIT 		EQU 0BH    	;"SCAN LIMIT" REGISTER
REG_SHUTDOWN 	 	EQU 0CH    	;"SHUTDOWN" REGISTER
REG_DISPLAY_TEST 	EQU 0FH    	;"DISPLAY TEST" REGISTER

BUZZER			EQU P2.5
RST			EQU P2.6
PAUSE_START		EQU P2.7
RS			EQU P3.0
RW			EQU P3.1
E			EQU P3.2
TRIG_1			EQU P3.3
ECHO_1			EQU P3.4
TRIG_2			EQU P2.0
ECHO_2			EQU P2.1
DIN	 		EQU P3.5
LOAD 			EQU P3.6
CLK 			EQU P3.7
C5_COUNT		EQU 64655
C4_COUNT		EQU 63774
A2b_COUNT		EQU 61098

P1_STRING:		DB 'PLAYER1 SCORES! ',0
P1_WON:			DB '  PLAYER1 WON!  ',0
P2_WON:			DB '  PLAYER2 WON!  ',0
P2_STRING:		DB 'PLAYER2 SCORES! ',0
NEW_ROUND_STR:		DB ' GAME GOES ON...',0
GAMEOVER_STR:		DB '   GAME OVER!   ',0
START_STRING:		DB '   GAME STARTS  ',0
PAUSE_STRING: 		DB '   GAME PAUSED  ',0
BEGIN_STR:		DB '  PRESS START   ',0
BEGIN_SCORE:		DB '     00:00      ',0
SCORE_DATA:		DB 00H,00H,7CH,44H,7CH,00H,00H,00H	;0
			DB 00H,00H,00H,20H,7CH,00H,00H,00H	;1
			DB 00H,00H,5CH,54H,74H,00H,00H,00H	;2
			DB 00H,00H,54H,54H,7CH,00H,00H,00H	;3
			DB 00H,00H,70H,10H,7CH,00H,00H,00H	;4
			DB 00H,00H,74H,54H,5CH,00H,00H,00H	;5
			DB 00H,00H,7CH,54H,5CH,00H,00H,00H	;6
			DB 00H,00H,40H,40H,7CH,00H,00H,00H	;7
			DB 00H,00H,7CH,54H,7CH,00H,00H,00H	;8
			DB 00H,00H,74H,54H,7CH,00H,00H,00H	;9
			DB 00H,00H,7CH,00H,7CH,44H,7CH,00H	;10
			DB 00H,00H,7CH,00H,7CH,00H,00H,00H	;11
END
