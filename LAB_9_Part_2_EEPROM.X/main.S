    ; Luke Groesbeck
    ; RCET3375
    ; EEPROM
    ; https://github.com/groeluke/Lab_9_EEPROM/tree/main/LAB_9_Part_2_EEPROM.X
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
  ee_address     EQU 0x70    ;the EEPROM address to read or write
  ee_data        EQU 0x71    ;the byte we read, or the byte we want to write
  ee_status      EQU 0x72    ;the status flags below

; The bit numbers inside ee_status
  EEPROM_READ    EQU 0       ;bit 0 = a read is happening
  EEPROM_WRITE   EQU 1       ;bit 1 = a write started and has not been checked yet
  EEPROM_ERROR   EQU 2       ;bit 2 = the last write did not check out
  EE_GIE_SAVED   EQU 7       ;bit 7 = remembers if interrupts were on during a write
  EE_BUSY        EQU 0b00000011 ;the READ and WRITE bits together

; The rest of the program's variables
  CurrentAddress EQU 0x73    ;the EEPROM address the program uses (0x00)
  Pending        EQU 0x74    ;the letter being picked: 'A' (0x41) or 'B' (0x42)
  Display        EQU 0x75    ;the letter we are about to show
  Selecting      EQU 0x76    ;1 = picking a letter, 0 = normal
  TimeoutCount   EQU 0x77    ;10 ms ticks left before the pick times out
  SelectDown        EQU 0x78    ;1 = we already counted this Select press
  WriteDown         EQU 0x79    ;1 = we already counted this Write press
  DelayInner     EQU 0x7A    ;counts down inside the 1 ms wait
  DelayOuter     EQU 0x7B    ;counts down how many 1 ms waits are left

  
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
    CLRF    ANSELH
    ;       Bank 1
    BANKSEL OPTION_REG
    BCF     OPTION_REG,7  ;turn on the built-in pull-up resistors for PORTB
    MOVLW   0b00000011
    MOVWF   WPUB          ;use the pull-ups on RB0 and RB1 only
    BSF     TRISB,0       ;RB0 is an input (Select button)
    BSF     TRISB,1       ;RB1 is an input (Write button)
    BCF     TRISA,0       ;RA0 is an output (selection LED)
    BCF     TRISA,1       ;RA1 is an output (main loop marker)
    BCF     TRISA,2       ;RA2 is an output (error LED)
    CLRF    TRISC         ;all of PORTC is an output (the display)
    MOVLW   249
    MOVWF   PR2           ;Timer2 counts 250 steps (this makes 1 ms)
    ;       Bank 0
    BANKSEL PORTA
    CLRF    PORTA         ;all the markers and LEDs start OFF
    CLRF    PORTC         ;display starts blank
    CLRF    ee_status     ;no read, no write, no error
    CLRF    CurrentAddress ;use EEPROM address 0x00
    MOVLW   0x41
    MOVWF   Pending       ;the pick starts out as 'A'
    CLRF    Selecting
    CLRF    TimeoutCount
    CLRF    SelectDown
    CLRF    WriteDown
    BCF     PIR1,1        ;clear the Timer2 flag
    MOVLW   0b01001101    ;Timer2 on, the flag is set every 10 ms
    MOVWF   T2CON

; MAIN LOOP: this runs over and over and never waits for the EEPROM.
Main:
    BSF     PORTA,1       ;marker ON
    BCF     PORTA,1       ;marker OFF right away

; Is a write finished?
    BTFSS   ee_status,EEPROM_WRITE ;was a write started?
    GOTO    ErrorLed      ;no
    BTFSS   PIR2,4        ;EEIF: the chip sets this when the write is done
    GOTO    ErrorLed      ;not done yet, so keep running
    CALL    EEPROMVerifyWrite ;it is done, so check it one time

; The error LED always matches the error flag
ErrorLed:
    BTFSC   ee_status,EEPROM_ERROR ;is there an error?
    GOTO    ErrorOn
    BCF     PORTA,2       ;no error, LED OFF
    GOTO    CheckTimeout
ErrorOn:
    BSF     PORTA,2       ;error, LED ON

; Every 10 ms count down the selection timeout
CheckTimeout:
    BTFSS   PIR1,1        ;has 10 ms gone by?
    GOTO    CheckButtons  ;no
    BCF     PIR1,1        ;clear the flag for the next 10 ms
    BTFSS   Selecting,0   ;only count while picking a letter
    GOTO    CheckButtons
    DECFSZ  TimeoutCount,F ;one tick used up, is it zero?
    GOTO    CheckButtons  ;not yet
    CALL    ExitSelect    ;time is up, leave selection (no write)

; Ignore the buttons while a read or write is happening
CheckButtons:
    MOVLW   EE_BUSY
    ANDWF   ee_status,W   ;W = the READ and WRITE bits
    BTFSS   STATUS,2      ;zero means not busy
    GOTO    ShowLetter    ;busy, so skip the buttons

; Select button
    BTFSS   PORTB,0       ;is it pressed? LOW = pressed
    GOTO    SelectPressed ;yes
    BTFSS   SelectDown,0  ;it is released, did we count a press before?
    GOTO    CheckWrite    ;no, nothing to do
    CALL    Wait10ms      ;wait 10 ms to make sure it is really released
    BTFSC   PORTB,0       ;pressed again? skip the next line if yes
    CLRF    SelectDown    ;really released, so get ready for the next press
    GOTO    CheckWrite
SelectPressed:
    BTFSC   SelectDown,0  ;did we already count this press?
    GOTO    CheckWrite    ;yes, ignore it
    CALL    Wait10ms      ;wait 10 ms to make sure it is not bounce
    BTFSC   PORTB,0       ;still pressed? skip the next line if yes
    GOTO    CheckWrite    ;it was only bounce
    BSF     SelectDown,0  ;remember we counted this press
    BTFSC   Selecting,0   ;already picking a letter?
    GOTO    TogglePick    ;yes, switch the letter
    BSF     Selecting,0   ;no, this is the first press, so start picking
    MOVLW   0x41
    MOVWF   Pending       ;start with 'A'
    BSF     PORTA,0       ;selection LED ON
    GOTO    RestartTimeout
TogglePick:
    MOVLW   0x03
    XORWF   Pending,F     ;'A' becomes 'B', 'B' becomes 'A'
RestartTimeout:
    MOVLW   100
    MOVWF   TimeoutCount  ;a new full second (100 x 10 ms) starts now

;Write button
CheckWrite:
    BTFSS   PORTB,1       ;is it pressed? (LOW = pressed)
    GOTO    WritePressed  ;yes
    BTFSS   WriteDown,0   ;it is released, did we count a press before?
    GOTO    ShowLetter    ;no, nothing to do
    CALL    Wait10ms      ;wait 10 ms to make sure it is really released
    BTFSC   PORTB,1       ;pressed again? skip the next line if yes
    CLRF    WriteDown     ;really released, so get ready for the next press
    GOTO    ShowLetter
WritePressed:
    BTFSC   WriteDown,0   ;did we already count this press?
    GOTO    ShowLetter    ;yes, ignore it
    CALL    Wait10ms      ;wait 10 ms to make sure it is not bounce
    BTFSC   PORTB,1       ;still pressed? skip the next line if yes
    GOTO    ShowLetter    ;it was only bounce
    BSF     WriteDown,0   ;remember we counted this press
    BTFSS   Selecting,0   ;Write only counts while picking a letter
    GOTO    ShowLetter    ;not picking, so ignore it
    CALL    ExitSelect    ;stop the timer and turn the LED OFF
    MOVF    CurrentAddress,W
    MOVWF   ee_address    ;where to save
    MOVF    Pending,W
    MOVWF   ee_data       ;what to save
    CALL    EEPROMWrite   ;start the write (it does not wait)

;Update the display
ShowLetter:
    BTFSC   Selecting,0   ;picking a letter?
    GOTO    ShowPending   ;yes, show the pick
    BTFSC   ee_status,EEPROM_WRITE ;is a write happening?
    GOTO    Main          ;yes, leave the display alone, do not read the EEPROM
    MOVF    CurrentAddress,W
    MOVWF   ee_address
    CALL    EEPROMRead    ;the stored letter comes back in ee_data
    
    MOVF    ee_data,W
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
    GOTO    Main
ShowPending:
    MOVF    Pending,W
    CALL    DisplayLetter ;show the letter we are picking
    GOTO    Main

;ExitSelect: leave selection mode (used by the timeout and by Write).
ExitSelect:
    CLRF    Selecting     ;not picking anymore
    CLRF    TimeoutCount  ;stop the timer
    BCF     PORTA,0       ;selection LED OFF
    RETURN

;DisplayLetter: the letter to show is in W.
DisplayLetter:
    BANKSEL PORTC         ;make sure we are in bank 0 (W is not changed)
    MOVWF   PORTC         ;send the letter to the display
    RETURN

; THE THREE EEPROM ROUTINES. They only use ee_address, ee_data and
; ee_status, so they can be copied into another program.

;EEReadByte: a helper. Reads the byte at ee_address and returns it in W.
;It does not change ee_data or ee_status.
EEReadByte:
    BANKSEL EEADR
    MOVF    ee_address,W
    MOVWF   EEADR         ;which address to read
    BANKSEL EECON1
    BCF     EECON1,7      ;pick data EEPROM (not program memory)
    BSF     EECON1,0      ;start the read
    BANKSEL EEDATA
    MOVF    EEDATA,W      ;the value is ready, so copy it into W
    BANKSEL PORTA         ;go back to bank 0 (W is not changed)
    RETURN

;EEPROMRead: in = ee_address, out = ee_data.
;EEPROM_READ is ON while it runs.
EEPROMRead:
    BSF     ee_status,EEPROM_READ  ;read started
    CALL    EEReadByte    ;the byte comes back in W
    MOVWF   ee_data       ;save it in ee_data
    BCF     ee_status,EEPROM_READ  ;read finished
    RETURN

;EEPROMWrite: in ee_address and ee_data.
;It starts the write and returns. It does NOT wait.
;It does nothing if a write is already going, or if the stored byte
;is already the same this saves wear on the EEPROM.
EEPROMWrite:
    BTFSC   ee_status,EEPROM_WRITE ;is a write already going?
    RETURN                ;yes, leave everything alone
    BANKSEL PIR2
    BTFSC   PIR2,4        ;is EEIF still set from an old write?
    RETURN                ;yes, leave everything alone
    CALL    EEReadByte    ;W = the byte stored right now
    XORWF   ee_data,W     ;zero if it is the same as what we want to save
    BTFSC   STATUS,2
    RETURN                ;same value, so do not write

    BSF     ee_status,EEPROM_WRITE ;a real write is starting
    BANKSEL EEADR
    MOVF    ee_address,W
    MOVWF   EEADR         ;the address to write
    MOVF    ee_data,W
    MOVWF   EEDATA        ;the byte to write
    
    
    ;MOVLW   1             ;TEST ONLY: remove the ; on these two lines to write
    ;ADDWF   EEDATA,F      ;the WRONG byte, so the check fails on purpose
    
    
    BANKSEL EECON1
    BCF     EECON1,7      ;pick data EEPROM
    BSF     EECON1,2      ;allow writing

    BCF     ee_status,EE_GIE_SAVED ;start by assuming interrupts were OFF
    BTFSC   INTCON,7      ;were they ON?
    BSF     ee_status,EE_GIE_SAVED ;yes, remember that
GieOff:
    BCF     INTCON,7      ;turn interrupts OFF
    BTFSC   INTCON,7      ;make sure they are really OFF
    GOTO    GieOff

    MOVLW   0x55          ;the chip needs this exact code, in this exact order,
    MOVWF   EECON2        ;with nothing in between, or it ignores the write
    MOVLW   0xAA
    MOVWF   EECON2
    BSF     EECON1,1      ;start the write (we do not wait)

    BTFSC   ee_status,EE_GIE_SAVED ;were interrupts ON when we came in?
    BSF     INTCON,7      ;yes, turn them back ON
    BCF     ee_status,EE_GIE_SAVED ;we are done with that memory bit
    BANKSEL PORTA         ;back to bank 0
    RETURN

;EEPROMVerifyWrite: call this one time after a write finishes.
;It checks that the stored byte is the byte we wanted. It does not
;change ee_data and it never tries the write again.
EEPROMVerifyWrite:
    CALL    EEReadByte    ;W = what is really stored
    XORWF   ee_data,W     ;zero if it matches what we wanted
    BTFSS   STATUS,2
    GOTO    VerifyBad
    CLRF    ee_status     ;good, so clear all the flags (this clears an old error too)
    GOTO    VerifyDone
VerifyBad:
    BCF     ee_status,EEPROM_WRITE ;the write is over
    BSF     ee_status,EEPROM_ERROR ;but it did not match, so flag an error
VerifyDone:
    BANKSEL PIR2
    BCF     PIR2,4        ;clear the "write finished" flag (EEIF)
    BANKSEL EECON1
    BCF     EECON1,2      ;turn writing OFF (WREN)
    BANKSEL PORTA         ;back to bank 0
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