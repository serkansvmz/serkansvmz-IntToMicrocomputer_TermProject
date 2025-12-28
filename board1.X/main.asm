;=============================================================================
; Author:Serkan Sevmez
; PROJECT: BOARD #1 - HOME AC SYSTEM (PIC16F877A)
; NOTES:
; - ADCON1 fixed to read correct analog value (prevents constant 255).
; - UART SET commands update display variables.
; - Keypad save logic corrected (stores user input properly).
;=============================================================================

#include <p16f877a.inc>

    __CONFIG _FOSC_XT & _WDTE_OFF & _PWRTE_OFF & _BOREN_OFF & _LVP_OFF & _CP_OFF

;----------------------------- RAM MAP (CBLOCK) ------------------------------
    CBLOCK 0x20
        ; Display / keypad
        D1, D2, D3, D4
        T1, T2, T3, T4
        ENTRY_MODE
        KEY_VAL

        ; System
        ADC_L, ADC_H
        TEMP_VAL
        TARGET_TEMP
        RPM_VAL

        ; Conversions / display cache
        TEMP_100, TEMP_10, TEMP_1
        USER_D1, USER_D2, USER_D3, USER_D4
        DISP_ACTIVE

        ; Counters / timing
        LOOP_COUNT
        DELAY_VAR
        KEY_DELAY
        SAMPLE_TIME
        TEMP_CALC

        ; UART data registers (protocol)
        DESIRED_TEMP_FRAC
        DESIRED_TEMP_INT
        AMBIENT_TEMP_FRAC
        AMBIENT_TEMP_INT
        FAN_SPEED
        UART_TEMP
    ENDC

    ORG 0x00
    GOTO START

;-------------------------- 7-SEGMENT LOOKUP TABLE --------------------------
GET_SEG:
    ADDWF   PCL, F
    RETLW   B'00111111' ; 0
    RETLW   B'00000110' ; 1
    RETLW   B'01011011' ; 2
    RETLW   B'01001111' ; 3
    RETLW   B'01100110' ; 4
    RETLW   B'01101101' ; 5
    RETLW   B'01111101' ; 6
    RETLW   B'00000111' ; 7
    RETLW   B'01111111' ; 8
    RETLW   B'01101111' ; 9
    RETLW   B'01110111' ; A
    RETLW   B'01111100' ; B
    RETLW   B'00111001' ; C
    RETLW   B'01011110' ; D
    RETLW   B'00001000' ; '_' (degree placeholder)
    RETLW   B'01110001' ; F (fan mode)

;=============================================================================
; INIT
;=============================================================================
START:
    ; Bank 1: I/O directions and peripherals
    BSF     STATUS, RP0

    CLRF    TRISD           ; 7-seg segments output (PORTD)

    MOVLW   B'00010000'     ; RA4 input (tach), others output (digit selects)
    MOVWF   TRISA

    BSF     TRISE, 0        ; RE0 input (AN5)

    BCF     TRISC, 0        ; Heater LED output
    BCF     TRISC, 1        ; Cooler/Fan LED output

    BCF     TRISC, 6        ; TX output
    BSF     TRISC, 7        ; RX input

    MOVLW   0xF0            ; Keypad: RB4..RB7 input, RB0..RB3 output
    MOVWF   TRISB

    MOVLW   B'00101000'     ; TMR0 counter mode configuration
    MOVWF   OPTION_REG

    MOVLW   B'10000000'     ; ADFM=1, PCFG=0000 (all analog)
    MOVWF   ADCON1

    ; UART 9600 @ 4MHz
    MOVLW   D'25'
    MOVWF   SPBRG
    BCF     TXSTA, SYNC
    BSF     TXSTA, BRGH
    BSF     TXSTA, TXEN

    ; Back to Bank 0
    BCF     STATUS, RP0

    ; ADC: Fosc/32, CH5 (AN5/RE0), ADON=1
    MOVLW   B'10101001'
    MOVWF   ADCON0

    ; UART RX enable
    BSF     RCSTA, SPEN
    BSF     RCSTA, CREN

    ; Init variables
    CLRF    PORTC
    CLRF    D1
    CLRF    D2
    CLRF    D3
    CLRF    D4
    CLRF    ENTRY_MODE
    CLRF    DISP_ACTIVE

    CLRF    DESIRED_TEMP_INT
    CLRF    DESIRED_TEMP_FRAC
    CLRF    AMBIENT_TEMP_INT
    CLRF    AMBIENT_TEMP_FRAC
    CLRF    FAN_SPEED

    CALL    WAIT_KEY_RELEASE

;=============================================================================
; MAIN LOOP
;=============================================================================
MAIN_LOOP:
    CALL    SHOW_DISPLAY
    CALL    UART_Check

    CALL    SCAN_KEYPAD
    MOVWF   KEY_VAL

    XORLW   0xFF
    BTFSC   STATUS, Z
    GOTO    MAIN_LOOP

    MOVLW   D'50'
    MOVWF   LOOP_COUNT
DEBOUNCE:
    CALL    SHOW_DISPLAY
    DECFSZ  LOOP_COUNT, F
    GOTO    DEBOUNCE

    ; Key 'A' enters input mode
    MOVF    KEY_VAL, W
    XORLW   0x0A
    BTFSS   STATUS, Z
    GOTO    CHECK_HASH

    BSF     DISP_ACTIVE, 0
    MOVLW   1
    MOVWF   ENTRY_MODE
    CLRF    T1
    CLRF    T2
    CLRF    T3
    CLRF    T4
    CLRF    PORTC
    GOTO    RELEASE_WAIT

CHECK_HASH:
    ; Key '#': validate and save
    MOVF    KEY_VAL, W
    XORLW   0x0F
    BTFSS   STATUS, Z
    GOTO    CHECK_NUM

    BTFSS   ENTRY_MODE, 0
    GOTO    RELEASE_WAIT

    ; Range check: 10.0 .. 50.0
    MOVF    T1, F
    BTFSC   STATUS, Z
    GOTO    TURN_OFF_SCREEN

    MOVLW   D'6'
    SUBWF   T1, W
    BTFSC   STATUS, C
    GOTO    TURN_OFF_SCREEN

    MOVLW   D'5'
    SUBWF   T1, W
    BTFSS   STATUS, Z
    GOTO    SAVE_DATA_CORRECTED

    MOVF    T2, F
    BTFSS   STATUS, Z
    GOTO    TURN_OFF_SCREEN

    MOVF    T4, F
    BTFSS   STATUS, Z
    GOTO    TURN_OFF_SCREEN

SAVE_DATA_CORRECTED:
    MOVF    T1, W
    MOVWF   USER_D1
    MOVF    T2, W
    MOVWF   USER_D2
    MOVF    T3, W
    MOVWF   USER_D3
    MOVF    T4, W
    MOVWF   USER_D4

    MOVF    T4, W
    MOVWF   DESIRED_TEMP_FRAC

    CLRF    DESIRED_TEMP_INT

    MOVF    T1, W
    BTFSC   STATUS, Z
    GOTO    ADD_ONES

    MOVWF   LOOP_COUNT
MULT_LOOP:
    MOVLW   D'10'
    ADDWF   DESIRED_TEMP_INT, F
    DECFSZ  LOOP_COUNT, F
    GOTO    MULT_LOOP

ADD_ONES:
    MOVF    T2, W
    ADDWF   DESIRED_TEMP_INT, F

    CLRF    ENTRY_MODE
    GOTO    ALTERNATE_LOOP

TURN_OFF_SCREEN:
    CLRF    DISP_ACTIVE
    CLRF    ENTRY_MODE
    CLRF    PORTD
    GOTO    MAIN_LOOP

CHECK_NUM:
    BTFSS   ENTRY_MODE, 0
    GOTO    RELEASE_WAIT

    ; Key '*' acts as a shift/decimal entry
    MOVF    KEY_VAL, W
    XORLW   0x0E
    BTFSC   STATUS, Z
    GOTO    DO_SHIFT

    ; Only accept 0..9
    MOVLW   0x0A
    SUBWF   KEY_VAL, W
    BTFSC   STATUS, C
    GOTO    RELEASE_WAIT

DO_SHIFT:
    MOVF    T2, W
    MOVWF   T1
    MOVF    T3, W
    MOVWF   T2
    MOVF    T4, W
    MOVWF   T3
    MOVF    KEY_VAL, W
    MOVWF   T4

    MOVF    T1, W
    MOVWF   D1
    MOVF    T2, W
    MOVWF   D2
    MOVF    T3, W
    MOVWF   D3
    MOVF    T4, W
    MOVWF   D4

RELEASE_WAIT:
    CALL    SHOW_DISPLAY
    CALL    UART_Check
    CALL    SCAN_KEYPAD
    XORLW   0xFF
    BTFSS   STATUS, Z
    GOTO    RELEASE_WAIT
    GOTO    MAIN_LOOP

;=============================================================================
; ALTERNATE DISPLAY / CONTROL LOOP
;=============================================================================
ALTERNATE_LOOP:
    ; 1) Show user setpoint
    MOVF    USER_D1, W
    MOVWF   D1
    MOVF    USER_D2, W
    MOVWF   D2
    MOVF    USER_D3, W
    MOVWF   D3
    MOVF    USER_D4, W
    MOVWF   D4
    CALL    DELAY_CHECK_A_2SEC

    ; 2) Read ambient temperature + control outputs
    CALL    READ_TEMP_SAFE
    CALL    CONTROL_LEDS
    CALL    DELAY_CHECK_A_2SEC

    ; 3) Read fan speed and show
    CALL    READ_RPM_AND_DISPLAY
    GOTO    ALTERNATE_LOOP

;=============================================================================
; SUBROUTINES
;=============================================================================

READ_RPM_AND_DISPLAY:
    CLRF    TMR0

    MOVLW   D'15'
    MOVWF   D1
    CLRF    D2
    CLRF    D3
    CLRF    D4

    MOVLW   D'2'
    MOVWF   ADC_H
RPM_LOOP_OUT:
    MOVLW   D'200'
    MOVWF   SAMPLE_TIME
RPM_LOOP_IN:
    CALL    SHOW_DISPLAY
    CALL    UART_Check
    DECFSZ  SAMPLE_TIME, F
    GOTO    RPM_LOOP_IN
    DECFSZ  ADC_H, F
    GOTO    RPM_LOOP_OUT

    MOVF    TMR0, W
    MOVWF   RPM_VAL
    MOVWF   FAN_SPEED

    CLRF    TEMP_100
    CLRF    TEMP_10
    CLRF    TEMP_1
    MOVF    RPM_VAL, W
    MOVWF   TEMP_VAL

C100_R:
    MOVLW   D'100'
    SUBWF   TEMP_VAL, W
    BTFSS   STATUS, C
    GOTO    C10_R
    MOVWF   TEMP_VAL
    INCF    TEMP_100, F
    GOTO    C100_R

C10_R:
    MOVLW   D'10'
    SUBWF   TEMP_VAL, W
    BTFSS   STATUS, C
    GOTO    C1_R
    MOVWF   TEMP_VAL
    INCF    TEMP_10, F
    GOTO    C10_R

C1_R:
    MOVF    TEMP_VAL, W
    MOVWF   TEMP_1

    MOVF    TEMP_100, W
    MOVWF   D2
    MOVF    TEMP_10, W
    MOVWF   D3
    MOVF    TEMP_1, W
    MOVWF   D4

    CALL    DELAY_CHECK_A_2SEC
    RETURN

CONTROL_LEDS:
    CLRF    TARGET_TEMP

    MOVF    USER_D1, W
    MOVWF   LOOP_COUNT
    MOVF    LOOP_COUNT, F
    BTFSC   STATUS, Z
    GOTO    ADD_ONES_LEDS

CALC_TENS_LEDS:
    MOVLW   D'10'
    ADDWF   TARGET_TEMP, F
    DECFSZ  LOOP_COUNT, F
    GOTO    CALC_TENS_LEDS

ADD_ONES_LEDS:
    MOVF    USER_D2, W
    ADDWF   TARGET_TEMP, F

COMPARE_NOW:
    BCF     PORTC, 0
    BCF     PORTC, 1

    MOVF    TEMP_VAL, W
    SUBWF   TARGET_TEMP, W
    BTFSC   STATUS, Z
    RETURN

    BTFSC   STATUS, C
    GOTO    KEYPAD_BIGGER
    GOTO    KEYPAD_SMALLER

KEYPAD_BIGGER:
    BSF     PORTC, 0
    RETURN

KEYPAD_SMALLER:
    BSF     PORTC, 1
    RETURN

SHOW_DISPLAY:
    BTFSS   DISP_ACTIVE, 0
    RETURN

    MOVF    D1, W
    CALL    GET_SEG
    MOVWF   PORTD
    BSF     PORTA, 0
    CALL    WAIT_1MS
    BCF     PORTA, 0
    CLRF    PORTD

    MOVF    D2, W
    CALL    GET_SEG
    MOVWF   PORTD
    BSF     PORTA, 1
    CALL    WAIT_1MS
    BCF     PORTA, 1
    CLRF    PORTD

    MOVF    D3, W
    CALL    GET_SEG
    MOVWF   PORTD
    BSF     PORTA, 2
    CALL    WAIT_1MS
    BCF     PORTA, 2
    CLRF    PORTD

    MOVF    D4, W
    CALL    GET_SEG
    MOVWF   PORTD
    BSF     PORTA, 3
    CALL    WAIT_1MS
    BCF     PORTA, 3
    CLRF    PORTD
    RETURN

WAIT_1MS:
    MOVLW   D'200'
    MOVWF   DELAY_VAR
DLY_L:
    DECFSZ  DELAY_VAR, F
    GOTO    DLY_L
    RETURN

DELAY_CHECK_A_2SEC:
    MOVLW   D'2'
    MOVWF   ADC_H
DL_OUT:
    MOVLW   D'200'
    MOVWF   LOOP_COUNT
DL_IN:
    CALL    SHOW_DISPLAY
    CALL    UART_Check
    CALL    SCAN_KEYPAD
    XORLW   0x0A
    BTFSC   STATUS, Z
    GOTO    SYSTEM_RESET

    DECFSZ  LOOP_COUNT, F
    GOTO    DL_IN
    DECFSZ  ADC_H, F
    GOTO    DL_OUT
    RETURN

SYSTEM_RESET:
    CLRF    PORTC
    GOTO    START

READ_TEMP_SAFE:
    BSF     STATUS, RP0
    MOVLW   B'10000000'
    MOVWF   ADCON1
    BCF     STATUS, RP0

    BSF     ADCON0, GO
W_ADC:
    BTFSC   ADCON0, GO
    GOTO    W_ADC

    BSF     STATUS, RP0
    MOVF    ADRESL, W
    BCF     STATUS, RP0
    MOVWF   ADC_L
    MOVF    ADRESH, W
    MOVWF   ADC_H

    BSF     STATUS, RP0
    MOVLW   B'00000110'
    MOVWF   ADCON1
    BCF     STATUS, RP0

    BCF     STATUS, C
    RRF     ADC_H, F
    RRF     ADC_L, F
    MOVF    ADC_L, W
    MOVWF   TEMP_VAL

    MOVWF   AMBIENT_TEMP_INT
    CLRF    AMBIENT_TEMP_FRAC

    CLRF    TEMP_100
    CLRF    TEMP_10
    CLRF    TEMP_1

C100:
    MOVLW   D'100'
    SUBWF   TEMP_VAL, W
    BTFSS   STATUS, C
    GOTO    C10
    MOVWF   TEMP_VAL
    INCF    TEMP_100, F
    GOTO    C100
C10:
    MOVLW   D'10'
    SUBWF   TEMP_VAL, W
    BTFSS   STATUS, C
    GOTO    C1
    MOVWF   TEMP_VAL
    INCF    TEMP_10, F
    GOTO    C10
C1:
    MOVF    TEMP_VAL, W
    MOVWF   TEMP_1

    MOVF    TEMP_10, W
    MOVWF   D1
    MOVF    TEMP_1, W
    MOVWF   D2
    MOVLW   D'14'
    MOVWF   D3
    MOVLW   0
    MOVWF   D4

    MOVF    ADC_L, W
    MOVWF   TEMP_VAL
    RETURN

WAIT_KEY_RELEASE:
    CALL    SHOW_DISPLAY
    CALL    SCAN_KEYPAD
    XORLW   0xFF
    BTFSS   STATUS, Z
    GOTO    WAIT_KEY_RELEASE
    RETURN

SCAN_KEYPAD:
    BSF     STATUS, RP0
    MOVLW   0xF0
    MOVWF   TRISB
    BCF     STATUS, RP0

    MOVLW   B'11111110'
    MOVWF   PORTB
    CALL    KEY_WAIT
    BTFSS   PORTB, 4
    RETLW   0x01
    BTFSS   PORTB, 5
    RETLW   0x02
    BTFSS   PORTB, 6
    RETLW   0x03
    BTFSS   PORTB, 7
    RETLW   0x0A

    MOVLW   B'11111101'
    MOVWF   PORTB
    CALL    KEY_WAIT
    BTFSS   PORTB, 4
    RETLW   0x04
    BTFSS   PORTB, 5
    RETLW   0x05
    BTFSS   PORTB, 6
    RETLW   0x06
    BTFSS   PORTB, 7
    RETLW   0x0B

    MOVLW   B'11111011'
    MOVWF   PORTB
    CALL    KEY_WAIT
    BTFSS   PORTB, 4
    RETLW   0x07
    BTFSS   PORTB, 5
    RETLW   0x08
    BTFSS   PORTB, 6
    RETLW   0x09
    BTFSS   PORTB, 7
    RETLW   0x0C

    MOVLW   B'11110111'
    MOVWF   PORTB
    CALL    KEY_WAIT
    BTFSS   PORTB, 4
    RETLW   0x0E
    BTFSS   PORTB, 5
    RETLW   0x00
    BTFSS   PORTB, 6
    RETLW   0x0F
    BTFSS   PORTB, 7
    RETLW   0x0D

    RETLW   0xFF

KEY_WAIT:
    MOVLW   D'50'
    MOVWF   KEY_DELAY
K_LOOP:
    DECFSZ  KEY_DELAY, F
    GOTO    K_LOOP
    RETURN

;=============================================================================
; UART PROTOCOL
;=============================================================================
UART_Check:
    BTFSS   PIR1, RCIF
    RETURN

    MOVF    RCREG, W
    MOVWF   UART_TEMP

    BTFSC   UART_TEMP, 7
    GOTO    Handle_Set

    MOVF    UART_TEMP, W
    XORLW   B'00000001'
    BTFSC   STATUS, Z
    GOTO    S_Des_F

    MOVF    UART_TEMP, W
    XORLW   B'00000010'
    BTFSC   STATUS, Z
    GOTO    S_Des_I

    MOVF    UART_TEMP, W
    XORLW   B'00000011'
    BTFSC   STATUS, Z
    GOTO    S_Amb_F

    MOVF    UART_TEMP, W
    XORLW   B'00000100'
    BTFSC   STATUS, Z
    GOTO    S_Amb_I

    MOVF    UART_TEMP, W
    XORLW   B'00000101'
    BTFSC   STATUS, Z
    GOTO    S_Fan

    RETURN

Handle_Set:
    BTFSS   UART_TEMP, 6
    GOTO    Set_Des_Low
    GOTO    Set_Des_High

Set_Des_Low:
    MOVF    UART_TEMP, W
    ANDLW   B'00111111'
    MOVWF   DESIRED_TEMP_FRAC
    MOVWF   USER_D4
    RETURN

Set_Des_High:
    MOVF    UART_TEMP, W
    ANDLW   B'00111111'
    MOVWF   DESIRED_TEMP_INT

    CLRF    USER_D1
    MOVF    DESIRED_TEMP_INT, W
    MOVWF   TEMP_CALC

Check_Tens_Loop:
    MOVLW   D'10'
    SUBWF   TEMP_CALC, W
    BTFSS   STATUS, C
    GOTO    Tens_Done
    MOVWF   TEMP_CALC
    INCF    USER_D1, F
    GOTO    Check_Tens_Loop

Tens_Done:
    MOVF    TEMP_CALC, W
    MOVWF   USER_D2
    RETURN

S_Des_F:
    MOVF    DESIRED_TEMP_FRAC, W
    GOTO    Tx_Byte
S_Des_I:
    MOVF    DESIRED_TEMP_INT, W
    GOTO    Tx_Byte
S_Amb_F:
    MOVF    AMBIENT_TEMP_FRAC, W
    GOTO    Tx_Byte
S_Amb_I:
    MOVF    AMBIENT_TEMP_INT, W
    GOTO    Tx_Byte
S_Fan:
    MOVF    FAN_SPEED, W
    GOTO    Tx_Byte

Tx_Byte:
    BTFSS   PIR1, TXIF
    GOTO    Tx_Byte
    MOVWF   TXREG
    RETURN

    END
