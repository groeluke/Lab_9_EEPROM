    ; Luke Groesbeck
    ; RCET3375
    ; EEPROM
    ; https://github.com/groeluke/Lab_8_UART/tree/main/LAB_9_Part_1_EEPROM.X
    ; Linker code = -Wl,-presetVect=0000h,-pisrVect=0004h,-pcode=0008h
; PIC16F883 Configuration Bit Settings
; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; config statements should precede project file includes.
#include <xc.inc>
  Pending     EQU 0x70    ;the letter being picked right now: 'A' (0x41) or 'B' (0x42)
  Display     EQU 0x71    ;the letter we are about to show
  DelayInner  EQU 0x72    ;counts down inside the 1 ms wait
  DelayOuter  EQU 0x73    ;counts down how many 1 ms waits are left
  
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    GOTO Setup

; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
   
; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2
 
Setup: 
    ;       Bank 3
    BANKSEL ANSEL
    CLRF    ANSEL         ;make every pin a normal digital pin
    CLRF    ANSELH        ;RB0 and RB1 can also be analog pins, so this matters
    ;       Bank 1
    BANKSEL OPTION_REG
    BCF     OPTION_REG,7  ;turn on the built-in pull-up resistors for PORTB
    MOVLW   0b00000011
    MOVWF   WPUB          ;use the pull-ups on RB0 and RB1 only
    BSF     TRISB,0       ;RB0 is an input (Select button)
    BSF     TRISB,1       ;RB1 is an input (Write button)
    BCF     TRISA,1       ;RA1 is an output (read marker)
    BCF     TRISA,2       ;RA2 is an output (write marker)
    CLRF    TRISC         ;all of PORTC is an output (the display)
    ;       Bank 0
    BANKSEL PORTA
    CLRF    PORTA         ;both markers start LOW
    CLRF    PORTC         ;display starts blank
    MOVLW   0x41
    MOVWF   Pending       ;the pick starts out as 'A'
    
; MAIN LOOP: read the stored letter and show it, over and over.
; If the Write button is pressed, go and pick a new letter instead.
Main:
    CALL    EepromRead    ;the stored value comes back in W
    MOVWF   Display
    XORLW   0x41          ;is it A
    BTFSC   STATUS,2
    GOTO    ShowStored    ;if yes show it
    MOVF    Display,W
    XORLW   0x42          ;is it B
    BTFSC   STATUS,2
    GOTO    ShowStored    ;if yes show it
    MOVLW   0x3F          ;it is neither, so show a question mark
    MOVWF   Display
ShowStored:
    MOVF    Display,W
    CALL    DisplayLetter ;put the letter on the display

    BTFSC   PORTB,1       ;is the Write button pressed? (LOW = pressed)
    GOTO    Main          ;if not keep reading
    CALL    Wait10ms      ;if yes then wait 10 ms to make sure it is not just bounce
    BTFSC   PORTB,1       ;verify that it is still pressed
    GOTO    Main          ;if not it was only bounce, so ignore it
;PICK A LETTER: we stay here while the Write button is held down.
;The display shows the pick. The EEPROM is NOT touched in here.
Selecting:
    MOVF    Pending,W
    CALL    DisplayLetter ;show the letter we are picking
    BTFSS   PORTB,1       ;has the Write button been let go? (HIGH = released)
    GOTO    CheckSelect   ;if not still held then look at the Select button
    CALL    Wait10ms      ;if it looks released then wait 10 ms to make sure
    BTFSC   PORTB,1       ;is it still released
    GOTO    SaveIt        ;yes, it is a real release, so save the letter
                          ;no, it bounced back down, so carry on picking
CheckSelect:
    BTFSC   PORTB,0       ;is the Select button pressed? (LOW = pressed)
    GOTO    Selecting     ;if no keep waiting
    CALL    Wait10ms      ;if yes then wait 10 ms to make sure it is not bounce
    BTFSC   PORTB,0       ;is it still pressed?
    GOTO    Selecting     ;if no then it was only bounce, so ignore it
    MOVLW   0x03
    XORWF   Pending,F     ;switch the pick: 'A' becomes 'B', 'B' becomes 'A'
    MOVF    Pending,W
    CALL    DisplayLetter ;show the new pick right away
WaitSelectUp:
    BTFSS   PORTB,0       ;wait here until the Select button is let go
    GOTO    WaitSelectUp
    CALL    Wait10ms      ;let any bounce on the release settle
    GOTO    Selecting
;SAVE: the Write button was pressed, then properly released.
;This is the ONLY place the EEPROM is ever written.
SaveIt:
    CALL    EepromWrite   ;store the pick, one time
    GOTO    Main          ;back to showing what is stored
;EepromRead: reads address 0 and hands the value back in W.
;RA1 goes HIGH only for the read itself, not for the display.
EepromRead:
    BSF     PORTA,1       ;read marker ON
    BANKSEL EEADR
    CLRF    EEADR         ;the address we want is 0
    BANKSEL EECON1
    BCF     EECON1,7      ;pick data EEPROM (not program memory)
    BSF     EECON1,0      ;start the read
    BANKSEL EEDATA
    MOVF    EEDATA,W      ;the value is ready, so copy it into W
    BANKSEL PORTA         ;go back to bank 0 (this does not change W)
    BCF     PORTA,1       ;read marker OFF
    RETURN
;EepromWrite: stores 'pending' at address 0 and waits until the chip
;says it is finished. RA2 is HIGH the whole time.
EepromWrite:
    BSF     PORTA,2       ;write marker ON
    BANKSEL EEADR
    CLRF    EEADR         ;the address to write is 0
    MOVF    Pending,W
    MOVWF   EEDATA        ;the letter to store
    BANKSEL EECON1
    BCF     EECON1,7      ;pick data EEPROM
    BSF     EECON1,2      ;allow writing
    BCF     INTCON,7      ;make sure no interrupt can get in the way of the next lines
    MOVLW   0x55          ;the chip needs this exact code, in this exact order,
    MOVWF   EECON2        ;with nothing in between, or it ignores the write
    MOVLW   0xAA
    MOVWF   EECON2
    BSF     EECON1,1      ;start the write
WaitWrite:
    BTFSC   EECON1,1      ;the chip clears this bit when it is finished
    GOTO    WaitWrite     ;if it is still writing then wait
    BCF     EECON1,2      ;turn writing off again so nothing can write by accident
    BANKSEL PIR2
    BCF     PIR2,4        ;clear the "write finished" flag
    BANKSEL PORTA
    BCF     PORTA,2       ;write marker OFF
    RETURN
;DisplayLetter: the letter to show is in W. Same idea as Lab 2:
;the display takes plain ASCII on PORTC, so we just write it there.
DisplayLetter:
    BANKSEL PORTC         ;make sure we are in bank 0 (W is not changed)
    MOVWF   PORTC         ;send the letter to the display
    RETURN
;Wait10ms: waits about 10 ms by doing the 1 ms wait 10 times.
Wait10ms:
    MOVLW   10
    MOVWF   DelayOuter    ;do the 1 ms wait 10 times
Wait10Loop:
    CALL    Wait1ms
    DECFSZ  DelayOuter,F  ;one fewer left, stop when it hits zero
    GOTO    Wait10Loop
    RETURN
Wait1ms:
    MOVLW   247
    MOVWF   DelayInner
Wait1Loop:
    NOP
    DECFSZ  DelayInner,F  ;count down to zero
    GOTO    Wait1Loop
    RETURN
    End