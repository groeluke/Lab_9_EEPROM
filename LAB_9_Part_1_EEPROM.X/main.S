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
  DispChar    EQU 0x71    ;the letter we are about to show
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
    MOVWF   pending       ;the pick starts out as 'A'
    
Main:
    BTFSS   PIR1,4        ;check to see if the transmit register is empty
    GOTO    $-1           ;if not keep waiting
    MakeItRain:
    MOVLW   0x24          ;send the "$"
    MOVWF   TXREG         ;write the transmission
    GOTO    Main          ;Re-run the program
    End
    