    ; Luke Groesbeck
    ; RCET3375
    ; EEPROM
    ; https://github.com/groeluke/Lab_9_EEPROM/tree/main/LAB_9_Part_4_EEPROM.X
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
; EEPROM routine variables
   ee_address     EQU 0x70   ;EEPROM address to read or write
   ee_data        EQU 0x71   ;byte read, or byte to write
   ee_status      EQU 0x72   ;status flags
   EEPROM_READ    EQU 0      ;bit 0 - a read is happening
   EEPROM_WRITE   EQU 1      ;bit 1 - a write started, not checked yet
   EEPROM_ERROR   EQU 2      ;bit 2 - the last write did not check out
   EE_GIE_SAVED   EQU 7      ;bit 7 - remembers GIE during a write
; Application variables
   KeyNow         EQU 0x73   ;key down now (ASCII, 0 = none)
   KeyLast        EQU 0x74   ;key down on the last scan
   KeyDone        EQU 0x75   ;key already counted
   Count          EQU 0x76   ;digits typed in this group (0-4)
   BuzzTimer      EQU 0x77   ;buzzer time left (10 ms units)
   LockTimer      EQU 0x78   ;solenoid time left (10 ms units)
   Temp           EQU 0x79   ;loop counter
   Mode           EQU 0x7A   ;which mode we are in (see below)
   Base           EQU 0x7B   ;0 = first group, 4 = second group
   Flags          EQU 0x7C   ;program flags (see below)
; Flags bits 
   PIN_UPDATE     EQU 0      ;1 = PINWrite is running
   PIN_ERROR      EQU 1      ;1 = save failed, locked until power cycle
; Modes
   MODE_NORMAL     EQU 0     ;normal locked mode
   MODE_NORMAL_C   EQU 1     ;normal mode, C was pressed, waiting for #
   MODE_INVALID    EQU 2     ;invalid PIN mode (set a new PIN)
   MODE_CHANGE_CUR EQU 3     ;PIN change: enter current PIN
   MODE_CHANGE_NEW EQU 4     ;PIN change: enter new PIN twice
; Bank 0 keep these 8 in a row
   Entry0         EQU 0x22   ;group 1, digit 1
   Entry1         EQU 0x23
   Entry2         EQU 0x24
   Entry3         EQU 0x25   ;group 1, digit 4
   Entry4         EQU 0x26   ;group 2, digit 1
   Entry5         EQU 0x27
   Entry6         EQU 0x28
   Entry7         EQU 0x29   ;group 2, digit 4

; Settings
   PinBase        EQU 0x10   ;EEPROM address of PIN digit 1
   MarkerAddr     EQU 0x14   ;EEPROM address of the valid marker
   MarkerValid    EQU 0xC4   ;marker value that means "PIN is valid"
   BeepTicks      EQU 20     ;20 x 10 ms = 200 ms
   OpenTicks      EQU 100    ;100 x 10 ms = 1 second

PSECT resetVect,class=CODE,delta=2
ResetVector:
    GOTO Setup

PSECT isrVect,class=CODE,delta=2
InterruptVector:

PSECT code,class=CODE,delta=2

Setup:
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
    BANKSEL PORTA
    CLRF    PORTA              ;buzzer, solenoid and LED start OFF
    CLRF    PORTB              ;keypad rows start low
    CLRF    PORTC              ;display starts blank
    BANKSEL T2CON
    MOVLW   0b01001101         ;postscale 1:10, Timer2 ON, prescale 1:4 -> 10 ms
    MOVWF   T2CON
    CLRF    KeyNow             ;start with a clean slate after reset
    CLRF    KeyLast
    CLRF    KeyDone
    CLRF    Count
    CLRF    Base
    CLRF    BuzzTimer
    CLRF    LockTimer
    CLRF    Flags
    CLRF    Mode
    CLRF    ee_status
    MOVLW   MarkerAddr
    MOVWF   ee_address
    CALL    EEPROMRead         ;marker -> ee_data
    MOVF    ee_data,W
    XORLW   MarkerValid        ;is it 0xC4?
    BTFSS   STATUS,2           ;read the valid marker to pick the starting mode
    GOTO    StartInvalid       ;no - PIN is not valid
    MOVLW   MODE_NORMAL        ;yes - normal locked mode
    MOVWF   Mode
    MOVLW   0x4C               ;'L'
    MOVWF   PORTC
    GOTO    Main
StartInvalid:
    MOVLW   MODE_INVALID       ;invalid PIN mode - ask for a new PIN
    MOVWF   Mode
    MOVLW   0x4E               ;'N'
    MOVWF   PORTC

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

    BANKSEL TRISB              ;Row 1
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

    BANKSEL TRISB              ;Row 2
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

    BANKSEL TRISB              ;Row 3
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

    BANKSEL TRISB              ;Row 4
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

    BTFSC   Flags,PIN_ERROR    ;save failed so ignore keys until power cycle
    RETURN
    BTFSC   Flags,PIN_UPDATE   ;PIN being saved so ignore keys
    RETURN
    MOVF    LockTimer,F        ;is the solenoid on right now?
    BTFSS   STATUS,2
    RETURN                     ;yes beep only so ignore the key
    
    MOVF    Mode,W
    BTFSC   STATUS,2           ;Mode 0
    GOTO    NormalKey
    XORLW   MODE_NORMAL_C
    BTFSC   STATUS,2
    GOTO    NormalCKey
    MOVF    Mode,W
    XORLW   MODE_INVALID
    BTFSC   STATUS,2
    GOTO    InvalidKey
    MOVF    Mode,W
    XORLW   MODE_CHANGE_CUR
    BTFSC   STATUS,2
    GOTO    ChangeCurKey
    GOTO    ChangeNewKey       ;must be MODE_CHANGE_NEW

; MODE: NORMAL LOCKED
NormalKey:
    MOVF    Count,F            ;no digits typed yet?
    BTFSS   STATUS,2
    GOTO    NormalDigits       ;already typing - not a C request
    MOVF    KeyDone,W
    XORLW   0x43               ;is the first key 'C'?
    BTFSS   STATUS,2
    GOTO    NormalDigits
    MOVLW   MODE_NORMAL_C
    MOVWF   Mode               ;C pressed - now wait for #
    RETURN

NormalDigits:
    CALL    CurrentPINMatch    ;0 = typing, 1 = PIN correct, 2 = rejected
    ADDLW   0
    BTFSC   STATUS,2
    RETURN                     ;still typing
    XORLW   1
    BTFSS   STATUS,2
    GOTO    RejectToNormal     ;wrong PIN or bad key

    CLRF    Count              ;PIN correct - unlock
    BSF     PORTA,1            ;solenoid and LED ON
    MOVLW   OpenTicks
    MOVWF   LockTimer          ;RunTimers turns it off after 1 second
    MOVLW   0x4F               ;'O'
    MOVWF   PORTC
    RETURN

NormalCKey:                    ;C was pressed, this key must be #
    MOVF    KeyDone,W
    XORLW   0x23               ;is it '#'?
    BTFSS   STATUS,2
    GOTO    BackToNormal       ;no - back to normal locked mode
    MOVLW   MODE_CHANGE_CUR    ;yes - start the PIN change
    MOVWF   Mode
    CLRF    Count
    CLRF    Base
    MOVLW   0x43               ;'C' = enter CURRENT PIN
    MOVWF   PORTC
    RETURN

; MODE: INVALID PIN (set a new PIN: dddd# dddd#)
InvalidKey:
    CALL    NewPINMatch        ;0 = typing, 1 = both entries match, 2 = rejected
    ADDLW   0
    BTFSC   STATUS,2
    RETURN
    XORLW   1
    BTFSS   STATUS,2
    GOTO    InvalidReject
    CALL    PINWrite           ;save the new PIN (blocks until done)
    RETURN

InvalidReject:                 ;clear the entry and start over
    CLRF    Count
    CLRF    Base
    MOVLW   0x45               ;'E'
    MOVWF   PORTC
    RETURN

; MODE: PIN CHANGE - step 1, enter the current PIN
ChangeCurKey:
    CALL    CurrentPINMatch
    ADDLW   0
    BTFSC   STATUS,2
    RETURN
    XORLW   1
    BTFSS   STATUS,2
    GOTO    RejectToNormal     ;wrong current PIN - cancel the change
    MOVLW   MODE_CHANGE_NEW    ;current PIN was right
    MOVWF   Mode
    CLRF    Count
    CLRF    Base
    MOVLW   0x4E               ;'N' = enter NEW PIN
    MOVWF   PORTC
    RETURN

; MODE: PIN CHANGE - step 2, enter the new PIN twice
ChangeNewKey:
    CALL    NewPINMatch
    ADDLW   0
    BTFSC   STATUS,2
    RETURN
    XORLW   1
    BTFSS   STATUS,2
    GOTO    RejectToNormal     ;entries did not match - cancel the change
    CALL    PINWrite           ;save the new PIN (blocks until done)
    RETURN

; Shared exits back to normal locked mode
RejectToNormal:                ;rejected - show E
    CLRF    Mode               ;MODE_NORMAL = 0
    CLRF    Count
    CLRF    Base
    MOVLW   0x45               ;'E'
    MOVWF   PORTC
    RETURN

BackToNormal:                  ;fine - show L
    CLRF    Mode
    CLRF    Count
    CLRF    Base
    MOVLW   0x4C               ;'L'
    MOVWF   PORTC
    RETURN

; PinCollect - takes ONE key (KeyDone) for a dddd# entry.
;   returns W = 0 still typing, 1 entry finished (dddd# done), 2 rejected
;   Digits go in Entry0 + Base + Count. # is never stored.
PinCollect:
    MOVF    KeyDone,W
    XORLW   0x23               ;is it '#'?
    BTFSC   STATUS,2
    GOTO    PinHash
    BTFSS   KeyDone,4          ;digits have bit 4 set - *, A-D do not
    RETLW   2                  ;* or A-D: reject
    BTFSC   Count,2            ;already 4 digits?
    RETLW   2                  ;a fifth digit: reject

    MOVLW   Entry0
    ADDWF   Base,W             ;+ 0 or 4 (which group)
    ADDWF   Count,W            ;+ digits so far
    MOVWF   FSR                ;FSR points at the spot for this digit
    MOVF    KeyDone,W
    ANDLW   0x0F               ;ASCII '5' (0x35) becomes 5
    MOVWF   INDF               ;save the digit
    INCF    Count,F            ;one more digit

    MOVF    Count,W
    IORLW   0x30               ;1-4 becomes '1'-'4'
    MOVWF   PORTC              ;show how many digits typed
    RETLW   0                  ;keep typing

PinHash:
    BTFSS   Count,2            ;exactly 4 digits typed?
    RETLW   2                  ;no - incomplete, reject
    RETLW   1                  ;yes - entry finished

; CurrentPINMatch - dddd# compared with the PIN stored in EEPROM.
;   returns W = 0 still typing, 1 matches the stored PIN, 2 rejected
CurrentPINMatch:
    CALL    PinCollect
    ADDLW   0
    BTFSC   STATUS,2
    RETURN                     ;still typing (W = 0)
    XORLW   1
    BTFSS   STATUS,2
    RETLW   2                  ;rejected

    MOVLW   Entry0
    MOVWF   FSR                ;first typed digit
    MOVLW   PinBase
    MOVWF   ee_address         ;first stored digit
    MOVLW   4
    MOVWF   Temp               ;compare 4 digits

CurLoop:
    CALL    EEPROMRead         ;stored digit -> ee_data
    MOVF    INDF,W             ;typed digit
    XORWF   ee_data,W          ;same?
    BTFSS   STATUS,2
    RETLW   2                  ;no - wrong PIN
    INCF    FSR,F
    INCF    ee_address,F
    DECFSZ  Temp,F
    GOTO    CurLoop
    RETLW   1                  ;all four match

; NewPINMatch - dddd#dddd#. Compares the two groups in RAM.
;   returns W = 0 still typing, 1 both groups match, 2 rejected
;   It does NOT write the EEPROM.
NewPINMatch:
    CALL    PinCollect
    ADDLW   0
    BTFSC   STATUS,2
    RETURN                     ;still typing (W = 0)
    XORLW   1
    BTFSS   STATUS,2
    RETLW   2                  ;rejected

    MOVF    Base,F             ;which group just finished?
    BTFSS   STATUS,2
    GOTO    CompareGroups      ;Base is 4 - the second group is done
    MOVLW   4
    MOVWF   Base               ;first group done - second goes in Entry4-7
    CLRF    Count
    MOVLW   0x52               ;'R' = re-enter the new PIN
    MOVWF   PORTC
    RETLW   0

CompareGroups:
    MOVF    Entry0,W
    XORWF   Entry4,W           ;digit 1 same?
    BTFSS   STATUS,2
    RETLW   2
    MOVF    Entry1,W
    XORWF   Entry5,W           ;digit 2 same?
    BTFSS   STATUS,2
    RETLW   2
    MOVF    Entry2,W
    XORWF   Entry6,W           ;digit 3 same?
    BTFSS   STATUS,2
    RETLW   2
    MOVF    Entry3,W
    XORWF   Entry7,W           ;digit 4 same?
    BTFSS   STATUS,2
    RETLW   2
    RETLW   1                  ;both groups match

; PINWrite - saves the new PIN (Entry0-Entry3) in six steps.
; Each step is finished and checked before the next one starts.
; Nothing else runs while this is going. An error stops the sequence.
PINWrite:
    BSF     Flags,PIN_UPDATE   ;PIN_UPDATE = 1

    MOVLW   MarkerAddr         ;step 1: marker = 0x00 (invalid)
    MOVWF   ee_address
    CLRF    ee_data
    CALL    WriteStep
    BTFSC   ee_status,EEPROM_ERROR
    GOTO    PinError

    MOVLW   PinBase            ;step 2: PIN digit 1
    MOVWF   ee_address
    MOVF    Entry0,W
    MOVWF   ee_data
    CALL    WriteStep
    BTFSC   ee_status,EEPROM_ERROR
    GOTO    PinError

    MOVLW   PinBase+1          ;step 3: PIN digit 2
    MOVWF   ee_address
    MOVF    Entry1,W
    MOVWF   ee_data
    CALL    WriteStep
    BTFSC   ee_status,EEPROM_ERROR
    GOTO    PinError

    MOVLW   PinBase+2          ;step 4: PIN digit 3
    MOVWF   ee_address
    MOVF    Entry2,W
    MOVWF   ee_data
    CALL    WriteStep
    BTFSC   ee_status,EEPROM_ERROR
    GOTO    PinError

    MOVLW   PinBase+3          ;step 5: PIN digit 4
    MOVWF   ee_address
    MOVF    Entry3,W
    MOVWF   ee_data
    CALL    WriteStep
    BTFSC   ee_status,EEPROM_ERROR
    GOTO    PinError

    MOVLW   MarkerAddr         ;step 6: marker = 0xC4 (valid)
    MOVWF   ee_address
    MOVLW   MarkerValid
    MOVWF   ee_data
    CALL    WriteStep
    BTFSC   ee_status,EEPROM_ERROR
    GOTO    PinError

    BCF     Flags,PIN_UPDATE   ;all six steps worked
    CALL    BackToNormal       ;normal locked mode with the new PIN
    MOVLW   0x53               ;'S' = saved
    MOVWF   PORTC
    RETURN

PinError:                      ;a step failed - stop here
    BCF     PORTA,1            ;solenoid OFF
    BSF     PORTA,2            ;PIN-error LED ON
    BSF     Flags,PIN_ERROR    ;ignore keys until power is cycled
    BCF     Flags,PIN_UPDATE
    MOVLW   0x46               ;'F' = failed
    MOVWF   PORTC
    RETURN

; WriteStep - one write, finished and checked.
;   in: ee_address, ee_data    out: ee_status has EEPROM_ERROR if it failed
WriteStep:
    CALL    EEPROMWrite        ;start the write (skips if already correct)
    BTFSS   ee_status,EEPROM_WRITE
    RETURN                     ;skipped - the byte was already correct
WaitWrite:
    BTFSS   PIR2,4             ;EEIF - has the write finished?
    GOTO    WaitWrite          ;no - wait (nothing else runs)
    CALL    EEPROMVerifyWrite  ;check what was stored
    RETURN

; THE THREE EEPROM ROUTINES (Part 2, interfaces unchanged)
; Most stack used: 5 levels (HandleKey path: Main > KeyEvent >
; InvalidKey > PINWrite > WriteStep > EEPROMWrite > EEReadByte is the
; deepest, counting the call from Main as level 1)

;EEReadByte: reads the byte at ee_address and returns it in W.
EEReadByte:
    BANKSEL EEADR
    MOVF    ee_address,W
    MOVWF   EEADR         ;which address to read
    BANKSEL EECON1
    BCF     EECON1,7      ;pick data EEPROM (not program memory)
    BSF     EECON1,0      ;start the read
    BANKSEL EEDATA
    MOVF    EEDATA,W      ;the value is ready, copy it into W
    BANKSEL PORTA         ;back to bank 0 (W is not changed)
    RETURN

;EEPROMRead: in = ee_address, out = ee_data.
EEPROMRead:
    BSF     ee_status,EEPROM_READ  ;read started
    CALL    EEReadByte    ;the byte comes back in W
    MOVWF   ee_data       ;save it in ee_data
    BCF     ee_status,EEPROM_READ  ;read finished
    RETURN

;EEPROMWrite: in = ee_address and ee_data. Starts the write and returns.
;Does nothing if a write is already going, or if the stored byte is
;already the same.
EEPROMWrite:
    BSF     PORTA,3       ;set diagnostic to see how often main runs
    BTFSC   ee_status,EEPROM_WRITE ;is a write already going?
    RETURN
    BANKSEL PIR2
    BTFSC   PIR2,4        ;is EEIF still set from an old write?
    RETURN
    CALL    EEReadByte    ;W = the byte stored right now
    XORWF   ee_data,W     ;zero if it is the same as what we want
    BTFSC   STATUS,2
    RETURN                ;same value, so do not write
    BSF     ee_status,EEPROM_WRITE ;a real write is starting
    BANKSEL EEADR
    MOVF    ee_address,W
    MOVWF   EEADR         ;the address to write
    MOVF    ee_data,W
    MOVWF   EEDATA        ;the byte to write
    ;MOVLW   1            ;TEST ONLY: remove the ; on these two lines to write
    ;ADDWF   EEDATA,F     ;the WRONG byte, so the check fails on purpose
    BANKSEL EECON1
    BCF     EECON1,7      ;pick data EEPROM
    BSF     EECON1,2      ;allow writing (WREN)

    BCF     ee_status,EE_GIE_SAVED ;assume interrupts were OFF
    BTFSC   INTCON,7      ;were they ON?
    BSF     ee_status,EE_GIE_SAVED ;yes, remember that
GieOff:
    BCF     INTCON,7      ;turn interrupts OFF
    BTFSC   INTCON,7      ;make sure they are really OFF
    GOTO    GieOff
    MOVLW   0x55          ;the unlock code, in this exact order
    MOVWF   EECON2
    MOVLW   0xAA
    MOVWF   EECON2
    BSF     EECON1,1      ;start the write (we do not wait)
    BTFSC   ee_status,EE_GIE_SAVED ;were interrupts ON when we came in?
    BSF     INTCON,7      ;yes, turn them back ON
    BCF     ee_status,EE_GIE_SAVED ;done with that memory bit
    BANKSEL PORTA         ;back to bank 0
    BCF     PORTA,3       ;clear 
    RETURN

;EEPROMVerifyWrite: call once after a write finishes. Does not change
;ee_data and never retries.
EEPROMVerifyWrite:
    CALL    EEReadByte    ;W = what is really stored
    XORWF   ee_data,W     ;zero if it matches what we wanted
    BTFSS   STATUS,2
    GOTO    VerifyBad
    CLRF    ee_status     ;good - clear all the flags
    GOTO    VerifyDone
VerifyBad:
    BCF     ee_status,EEPROM_WRITE ;the write is over
    BSF     ee_status,EEPROM_ERROR ;but it did not match
VerifyDone:
    BANKSEL PIR2
    BCF     PIR2,4        ;clear EEIF
    BANKSEL EECON1
    BCF     EECON1,2      ;turn writing OFF (WREN)
    BANKSEL PORTA         ;back to bank 0
    RETURN

    End