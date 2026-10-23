    ; Luke Groesbeck
    ; RCET3375
    ; EEPROM
    ; https://github.com/groeluke/Lab_9_EEPROM/tree/main/LAB_9_Part_3_EEPROM.X
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

  
#include <xc.inc>
  
   ee_address   EQU 0x70   ;EEPROM address to read or write
   ee_data      EQU 0x71   ;byte read back or to write
   KeyNow       EQU 0x73   ;key down now (ASCII, 0 = none)
   KeyLast      EQU 0x74   ;key down on the last scan
   KeyDone      EQU 0x75   ;key already counted
   DigitCount   EQU 0x76   ;digits typed (5 = too many)
   BuzzTimer    EQU 0x77   ;buzzer time left (10 ms units)
   LockTimer    EQU 0x78   ;solenoid time left (10 ms units)
   Temp         EQU 0x79   ;loop counter

; ---- Bank 0 (keep these 4 in a row) ----
   Entry0       EQU 0x22   ;typed digit 1
   Entry1       EQU 0x23   ;typed digit 2
   Entry2       EQU 0x24   ;typed digit 3
   Entry3       EQU 0x25   ;typed digit 4

; ---- Settings ----
   PinBase      EQU 0x10   ;EEPROM address of the first PIN digit
   BeepTicks    EQU 20     ;20 x 10 ms = 200 ms
   OpenTicks    EQU 100    ;100 x 10 ms = 1 second

PSECT resetVect,class=CODE,delta=2
ResetVector:
    GOTO Setup

PSECT isrVect,class=CODE,delta=2
InterruptVector:

PSECT code,class=CODE,delta=2

Setup:
    ;       Bank 0
    BANKSEL PORTA
    CLRF    PORTA              ;buzzer, solenoid and LED start OFF
    CLRF    PORTB              ;keypad rows start low
    CLRF    PORTC              ;display starts blank

    ;       Bank 3
    BANKSEL ANSEL
    CLRF    ANSEL              ;make every pin a normal digital pin
    CLRF    ANSELH

    ;       Bank 1
    BANKSEL TRISA
    CLRF    TRISA              ;PORTA all outputs (RA0 buzzer, RA1 solenoid + LED)
    CLRF    TRISC              ;PORTC all outputs (display)
    MOVLW   0b11110000
    MOVWF   TRISB              ;RB0-RB3 rows out, RB4-RB7 columns in
    MOVWF   WPUB               ;weak pull-ups on the column pins
    BCF     OPTION_REG,7       ;turn weak pull-ups on (RBPU = 0)
    MOVLW   249
    MOVWF   PR2                ;Timer2 period = 250 counts

    ;       Bank 0
    BANKSEL T2CON
    MOVLW   0b01001101         ;postscale 1:10, Timer2 ON, prescale 1:4 -> 10 ms
    MOVWF   T2CON

    CLRF    KeyNow             ;start with a clean slate after reset
    CLRF    KeyLast
    CLRF    KeyDone
    CLRF    DigitCount
    CLRF    BuzzTimer
    CLRF    LockTimer

    MOVLW   0x4C               ;'L'
    MOVWF   PORTC              ;show LOCKED

; MAIN LOOP - runs once every 10 ms
Main:
    BTFSS   PIR1,1             ;10 ms tick yet? (TMR2IF)
    GOTO    Main
    BCF     PIR1,1             ;clear the tick flag

    CALL    RunTimers          ;turn the buzzer / solenoid off when time is up
    CALL    ScanKeypad         ;look for a key
    CALL    KeyEvent           ;debounce - runs HandleKey once per real press
    GOTO    Main

; RunTimers - count down the buzzer and the solenoid output
RunTimers:
    MOVF    BuzzTimer,F        ;is the buzzer timer zero?
    BTFSC   STATUS,2
    GOTO    CheckLock          ;yes - buzzer is already off
    DECFSZ  BuzzTimer,F        ;count down one tick (skip next line at 0)
    GOTO    CheckLock
    BCF     PORTA,0            ;time is up - buzzer OFF

CheckLock:
    MOVF    LockTimer,F        ;is the solenoid timer zero?
    BTFSC   STATUS,2
    RETURN                     ;yes - nothing to do
    DECFSZ  LockTimer,F        ;count down one tick (skip next line at 0)
    RETURN
    BCF     PORTA,1            ;one second is up - solenoid and LED OFF
    MOVLW   0x4C               ;'L'
    MOVWF   PORTC              ;show LOCKED again
    RETURN

; ScanKeypad - pull one row low at a time. If a column reads low,
; that key is down, so its ASCII code goes in KeyNow.
; (MOVWF only runs when the column is low, because BTFSS skips it
;  when the column is high)
ScanKeypad:
    CLRF    KeyNow             ;assume no key is down

    BANKSEL TRISB              ;--- Row 1 (RB0 low) ---
    MOVLW   0b11111110
    MOVWF   TRISB
    BANKSEL PORTB
    MOVLW   0x31               ;'1'
    BTFSS   PORTB,4            ;column 1 low?
    MOVWF   KeyNow             ;yes - key 1 is down
    MOVLW   0x32               ;'2'
    BTFSS   PORTB,5
    MOVWF   KeyNow
    MOVLW   0x33               ;'3'
    BTFSS   PORTB,6
    MOVWF   KeyNow
    MOVLW   0x41               ;'A'
    BTFSS   PORTB,7
    MOVWF   KeyNow

    BANKSEL TRISB              ;--- Row 2 (RB1 low) ---
    MOVLW   0b11111101
    MOVWF   TRISB
    BANKSEL PORTB
    MOVLW   0x34               ;'4'
    BTFSS   PORTB,4
    MOVWF   KeyNow
    MOVLW   0x35               ;'5'
    BTFSS   PORTB,5
    MOVWF   KeyNow
    MOVLW   0x36               ;'6'
    BTFSS   PORTB,6
    MOVWF   KeyNow
    MOVLW   0x42               ;'B'
    BTFSS   PORTB,7
    MOVWF   KeyNow

    BANKSEL TRISB              ;--- Row 3 (RB2 low) ---
    MOVLW   0b11111011
    MOVWF   TRISB
    BANKSEL PORTB
    MOVLW   0x37               ;'7'
    BTFSS   PORTB,4
    MOVWF   KeyNow
    MOVLW   0x38               ;'8'
    BTFSS   PORTB,5
    MOVWF   KeyNow
    MOVLW   0x39               ;'9'
    BTFSS   PORTB,6
    MOVWF   KeyNow
    MOVLW   0x43               ;'C'
    BTFSS   PORTB,7
    MOVWF   KeyNow

    BANKSEL TRISB              ;--- Row 4 (RB3 low) ---
    MOVLW   0b11110111
    MOVWF   TRISB
    BANKSEL PORTB
    MOVLW   0x2A               ;'*'
    BTFSS   PORTB,4
    MOVWF   KeyNow
    MOVLW   0x30               ;'0'
    BTFSS   PORTB,5
    MOVWF   KeyNow
    MOVLW   0x23               ;'#'
    BTFSS   PORTB,6
    MOVWF   KeyNow
    MOVLW   0x44               ;'D'
    BTFSS   PORTB,7
    MOVWF   KeyNow
    RETURN                     ;we are back in bank 0

; KeyEvent - debounce. A key counts as ONE press only if:
; it is seen on two scans in a row (10 ms apart), and
; it is not the key we already counted (wait for release)
KeyEvent:
    MOVF    KeyNow,W
    BTFSC   STATUS,2           ;no key down?
    GOTO    NoKey
    XORWF   KeyLast,W          ;same key as the last scan?
    BTFSS   STATUS,2
    GOTO    NotSame            ;no - wait for the next scan
    MOVF    KeyNow,W
    XORWF   KeyDone,W          ;did we already count this press?
    BTFSC   STATUS,2
    RETURN                     ;yes - still held down, ignore it
    MOVF    KeyNow,W
    MOVWF   KeyDone            ;remember we counted it
    GOTO    HandleKey          ;a new key press!

NotSame:
    MOVF    KeyNow,W
    MOVWF   KeyLast            ;remember it, check again next scan
    RETURN

NoKey:
    CLRF    KeyLast            ;key was let go - ready for the next press
    CLRF    KeyDone
    RETURN

; HandleKey runs once per key press (the key is in KeyDone)
HandleKey:
    BSF     PORTA,0            ;buzzer ON for every key
    MOVLW   BeepTicks
    MOVWF   BuzzTimer          ;RunTimers turns it off after 200 ms

    MOVF    LockTimer,F        ;is the solenoid on right now?
    BTFSS   STATUS,2
    RETURN                     ;yes - beep only, ignore the key

    MOVF    KeyDone,W
    XORLW   0x23               ;is it '#'?
    BTFSC   STATUS,2
    GOTO    Submit

    MOVF    KeyDone,W
    XORLW   0x2A               ;is it '*'?
    BTFSC   STATUS,2
    GOTO    Cancel

    BTFSS   KeyDone,4          ;digits (0x30-0x39) have bit 4 set, A-D do not
    RETURN                     ;A-D: beep only, nothing else

    ;it is a digit
    BTFSC   DigitCount,2       ;already 4 digits? (counts 0-3 have bit 2 clear)
    GOTO    TooMany            ;yes - this is a fifth digit

    MOVLW   Entry0             ;address of the first digit
    ADDWF   DigitCount,W       ;plus digits so far = where this one goes
    MOVWF   FSR                ;FSR points at that spot
    MOVF    KeyDone,W
    ANDLW   0x0F               ;ASCII '5' (0x35) becomes the number 5
    MOVWF   INDF               ;save the digit
    INCF    DigitCount,F       ;one more digit typed

    MOVF    DigitCount,W
    IORLW   0x30               ;turn 1-4 into '1'-'4'
    MOVWF   PORTC              ;show how many digits typed
    RETURN

TooMany:
    MOVLW   5
    MOVWF   DigitCount         ;5 = too many (only # or * ends it)
    MOVLW   0x45               ;'E'
    MOVWF   PORTC
    RETURN

Cancel:                        ;* was pressed
    CLRF    DigitCount         ;forget the typed digits
    MOVLW   0x43               ;'C'
    MOVWF   PORTC
    RETURN

Submit:                        ;# was pressed
    MOVF    DigitCount,W
    XORLW   4                  ;exactly 4 digits typed?
    BTFSS   STATUS,2
    GOTO    Reject             ;no - too few, or a fifth digit was pressed

    MOVLW   Entry0
    MOVWF   FSR                ;FSR starts at the first typed digit
    MOVLW   PinBase
    MOVWF   ee_address         ;start at the first stored digit
    MOVLW   4
    MOVWF   Temp               ;check 4 digits

CompareLoop:
    CALL    EEPROMRead         ;get the stored digit (ee_data)
    MOVF    INDF,W             ;get the typed digit
    XORWF   ee_data,W          ;are they the same?
    BTFSS   STATUS,2
    GOTO    Reject             ;no - wrong PIN
    INCF    FSR,F              ;next typed digit
    INCF    ee_address,F       ;next stored digit
    DECFSZ  Temp,F             ;one digit done
    GOTO    CompareLoop

    ;all 4 digits matched
    CLRF    DigitCount         ;clear the entry
    BSF     PORTA,1            ;solenoid and LED ON
    MOVLW   OpenTicks
    MOVWF   LockTimer          ;RunTimers turns it off after 1 second
    MOVLW   0x4F               ;'O'
    MOVWF   PORTC
    RETURN

Reject:
    CLRF    DigitCount         ;clear the entry so a new try can start
    MOVLW   0x45               ;'E'
    MOVWF   PORTC
    RETURN

; EEPROMRead (Part 2 interface)
;   in : ee_address
;   out: ee_data
EEPROMRead:
    BANKSEL EEADR
    MOVF    ee_address,W
    MOVWF   EEADR              ;tell the EEPROM which address
    BANKSEL EECON1
    BCF     EECON1,7           ;read data EEPROM (not program memory)
    BSF     EECON1,0           ;start the read
    BANKSEL EEDATA
    MOVF    EEDATA,W           ;grab the byte
    BANKSEL PORTA              ;back to bank 0
    MOVWF   ee_data
    RETURN


    End