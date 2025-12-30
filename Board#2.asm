;====================================================================
; Tolga Çayc? 152120231185
; Yusuf Eren Kurul 152120221082  
;====================================================================

    PROCESSOR 16F877A
    #include <xc.inc>

;--- Konfigurasyon ---
    CONFIG FOSC = XT
    CONFIG WDTE = OFF
    CONFIG PWRTE = ON
    CONFIG BOREN = OFF
    CONFIG LVP = OFF
    CONFIG CPD = OFF
    CONFIG WRT = OFF
    CONFIG CP = OFF

;--- Degiskenler ---
    PSECT udata_bank0
; BMP180 Degiskenleri
I2C_BUFFER:     DS 1
TEMP_MSB:       DS 1
TEMP_LSB:       DS 1
TEMP_INTEGER:   DS 1 ; High Byte (Integral)
TEMP_FRAC:      DS 1 ; Low Byte (Fractional - Simdilik 0)
PRESS_MSB:      DS 1
PRESS_LSB:      DS 1
PRESS_XLSB:     DS 1
PRESS_INTEGER:  DS 1 ; High Byte (Integral)
PRESS_FRAC:     DS 1 ; Low Byte (Fractional)

; Motor ve Sensör Degiskenleri
DesiredCurtain:      DS 1 ; High Byte (Integral Part)
DesiredCurtain_Frac: DS 1 ; Low Byte (Fractional Part - Tablo istegi icin)
CurrentCurtain:      DS 1
LightValue:          DS 1 ; High Byte (Integral)
LightValue_Frac:     DS 1 ; Low Byte (Fractional - Simdilik 0)
PotValue:            DS 1
StepPhase:           DS 1
ShadowPORTD:         DS 1

; UART ve Kontrol Degiskenleri
RX_DATA:        DS 1      ; Gelen veri
SystemMode:     DS 1      ; 0: Otomatik, 1: UART Kontrol

; LCD ve Yardimci Degiskenler
LCD_Temp:       DS 1
Bin_H:          DS 1
Bin_T:          DS 1
Bin_O:          DS 1
Press_Th:       DS 1
Press_H:        DS 1
Press_T:        DS 1
Press_O:        DS 1
TempVar:        DS 1
TempVar2:       DS 1
BIT_CNT:        DS 1
DelayVar1:      DS 1
DelayVar2:      DS 1

;--- Makrolar ---
SCL_HIGH MACRO
    BSF     PORTC, 3
    NOP
    ENDM
SCL_LOW MACRO
    BCF     PORTC, 3
    NOP
    ENDM
SDA_HIGH MACRO
    BSF     PORTC, 4
    NOP
    ENDM
SDA_LOW MACRO
    BCF     PORTC, 4
    NOP
    ENDM

;--- Reset Vektörü ---
    PSECT code
    ORG 0x00
    GOTO    INIT

;====================================================================
; BASLANGIC AYARLARI
;====================================================================
INIT:
    ; 1. PORT AYARLARI
    BANKSEL TRISD
    CLRF    TRISD           ; PORTD Cikis (Motor + LED)
    
    BANKSEL TRISB
    CLRF    TRISB           ; PORTB Cikis (LCD)
    
    BANKSEL TRISC
    BCF     TRISC, 0        ; RC0 Cikis
    BCF     TRISC, 3        ; RC3 Cikis (SCL)
    BCF     TRISC, 4        ; RC4 Cikis (SDA)
    BSF     TRISC, 7        ; RC7 Giris (RX)
    BCF     TRISC, 6        ; RC6 Cikis (TX)
    
    BANKSEL TRISA
    MOVLW   0xFF
    MOVWF   TRISA           ; PORTA Giris
    
    ; 2. ADC AYARLARI
    BANKSEL ADCON1
    MOVLW   00000100B       ; Sola Dayali, AN0 ve AN1 analog
    MOVWF   ADCON1
    
    ; 3. UART AYARLARI (9600 BAUD @ 4MHz)
    BANKSEL SPBRG
    MOVLW   25              ; 9600 Baud
    MOVWF   SPBRG
    
    MOVLW   00100100B       ; TXEN=1, BRGH=1
    MOVWF   TXSTA
    
    BANKSEL RCSTA
    MOVLW   10010000B       ; SPEN=1, CREN=1
    MOVWF   RCSTA

    ; 4. BA?LANGIÇ DURUMLARI
    BANKSEL PORTC
    BCF     PORTC, 0
    SCL_HIGH
    SDA_HIGH
    
    BANKSEL PORTD
    CLRF    PORTD
    CLRF    ShadowPORTD
    CLRF    StepPhase
    CLRF    PORTB
    
    MOVLW   10000001B       ; ADC Acik
    MOVWF   ADCON0
    
    CLRF    CurrentCurtain
    CLRF    DesiredCurtain
    CLRF    DesiredCurtain_Frac
    CLRF    SystemMode      ; Baslangic: OTOMATIK
    
    ; Varsay?lan Fractional De?erleri S?f?rla (Sensörler tam say? okuyor varsaydik)
    CLRF    TEMP_FRAC
    CLRF    PRESS_FRAC
    CLRF    LightValue_Frac
    
    ; 5. LCD BA?LATMA
    CALL    LCD_INIT
    
    ; Sabit Etiketler
    CALL    LCD_LINE1
    MOVLW   'T'
    CALL    LCD_CHAR
    MOVLW   ':'
    CALL    LCD_CHAR

;====================================================================
; ANA DÖNGÜ
;====================================================================
MAIN_LOOP:
    ; -----------------------------------------------------------
    ; 0. UART PROTOKOL KONTROL (Tablo Gereksinimi)
    ; -----------------------------------------------------------
    CALL    UART_CHECK_COMMAND

    ; -----------------------------------------------------------
    ; 1. BMP180 SICAKLIK OKU
    ; -----------------------------------------------------------
    CALL    BMP180_READ_TEMP
    
    ; LCD Guncelle
    MOVLW   0x82
    CALL    LCD_CMD
    MOVF    TEMP_INTEGER, W
    CALL    BIN_TO_DEC
    CALL    PRINT_NUMBERS
    MOVLW   0xDF
    CALL    LCD_CHAR
    MOVLW   'C'
    CALL    LCD_CHAR
    
    ; -----------------------------------------------------------
    ; 1B. BMP180 BASINÇ OKU
    ; -----------------------------------------------------------
    CALL    BMP180_READ_PRESSURE
    
    ; -----------------------------------------------------------
    ; 2. LDR OKU (ISIK)
    ; -----------------------------------------------------------
    BANKSEL ADCON0
    BCF     ADCON0, 5
    BCF     ADCON0, 4
    BCF     ADCON0, 3       ; Kanal 0 (LDR)
    CALL    DELAY_ADC
    BSF     ADCON0, 2
WAIT_LDR:
    BTFSC   ADCON0, 2
    GOTO    WAIT_LDR
    
    MOVLW   255
    MOVWF   TempVar
    MOVF    ADRESH, W
    SUBWF   TempVar, F
    MOVF    TempVar, W
    MOVWF   LightValue
    
    ; LCD Yaz
    CALL    LCD_LINE2
    MOVLW   'L'
    CALL    LCD_CHAR
    MOVLW   ':'
    CALL    LCD_CHAR
    MOVF    LightValue, W
    CALL    BIN_TO_DEC
    CALL    PRINT_NUMBERS
    MOVLW   ' '
    CALL    LCD_CHAR

    ; -----------------------------------------------------------
    ; 3. PERDE DURUMU
    ; -----------------------------------------------------------
    MOVLW   'C'
    CALL    LCD_CHAR
    MOVLW   ':'
    CALL    LCD_CHAR
    MOVF    CurrentCurtain, W
    CALL    BIN_TO_DEC
    CALL    PRINT_NUMBERS
    MOVLW   '%'
    CALL    LCD_CHAR

    ; -----------------------------------------------------------
    ; 4. BASINÇ GÖSTERGES?
    ; -----------------------------------------------------------
    MOVLW   0x8A
    CALL    LCD_CMD
    MOVLW   'P'
    CALL    LCD_CHAR
    MOVLW   ':'
    CALL    LCD_CHAR
    CALL    PRINT_PRESSURE
    MOVLW   'h'
    CALL    LCD_CHAR

    ; -----------------------------------------------------------
    ; 5. KARAR MEKAN?ZMASI
    ; -----------------------------------------------------------
    ; Eger UART Modu (SystemMode = 1) ise LDR/Pot atlanir
    MOVF    SystemMode, W
    SUBLW   1
    BTFSC   STATUS, 2       
    GOTO    ISLEM_SONU      ; SystemMode=1 ise sensör kontrolünü atla

    ; --- OTOMATIK MOD ---
    MOVLW   150
    SUBWF   LightValue, W
    BTFSS   STATUS, 0       ; Light >= 150 ?
    GOTO    GUNDUZ_MODU
    GOTO    GECE_MODU

GECE_MODU:
    BSF     ShadowPORTD, 7
    MOVLW   100
    MOVWF   DesiredCurtain
    GOTO    ISLEM_SONU

GUNDUZ_MODU:
    BCF     ShadowPORTD, 7
    ; POT OKU
    BANKSEL ADCON0
    BCF     ADCON0, 5
    BCF     ADCON0, 4
    BSF     ADCON0, 3       ; Kanal 1 (Pot)
    CALL    DELAY_ADC
    BSF     ADCON0, 2
WAIT_POT:
    BTFSC   ADCON0, 2
    GOTO    WAIT_POT
    
    MOVF    ADRESH, W
    MOVWF   PotValue
    ; 0-100 Donusumu
    BCF     STATUS, 0
    RRF     PotValue, W
    MOVWF   TempVar
    MOVLW   100
    SUBWF   TempVar, W
    BTFSC   STATUS, 0
    MOVLW   100
    BTFSS   STATUS, 0
    MOVF    TempVar, W
    MOVWF   DesiredCurtain

ISLEM_SONU:
    ; LED Guncelle
    MOVF    ShadowPORTD, W
    MOVWF   PORTD
    
    ; MOTOR HAREKET?
    MOVF    DesiredCurtain, W
    SUBWF   CurrentCurtain, W
    BTFSC   STATUS, 2
    GOTO    MAIN_LOOP
    BTFSS   STATUS, 0
    GOTO    HAREKET_KAPAT
    GOTO    HAREKET_AC

HAREKET_KAPAT:
    INCF    StepPhase, F
    MOVLW   0x03
    ANDWF   StepPhase, F
    CALL    MOTORU_SUR_MANUEL
    INCF    CurrentCurtain, F
    GOTO    MAIN_LOOP

HAREKET_AC:
    DECF    StepPhase, F
    MOVLW   0x03
    ANDWF   StepPhase, F
    CALL    MOTORU_SUR_MANUEL
    DECF    CurrentCurtain, F
    GOTO    MAIN_LOOP

;====================================================================
; UART PROTOKOL VE KOMUT ??LEY?C? (TABLOYA GORE YENIDEN YAZILDI)
;====================================================================
UART_CHECK_COMMAND:
    BANKSEL PIR1
    BTFSS   PIR1, 5         ; Veri geldi mi?
    RETURN                  ; Hayir, don

    ; Veri gelmis, oku
    BANKSEL RCREG
    MOVF    RCREG, W
    MOVWF   RX_DATA         ; Gelen veriyi sakla

    ; -------------------------------------------------------
    ; 1. SET KOMUTLARI KONTROLU (Bit 7 ve 6 Kontrolü)
    ; -------------------------------------------------------
    ; Tabloda:
    ; 10xxxxxx -> Set Curtain Low Byte (Fractional)
    ; 11xxxxxx -> Set Curtain High Byte (Integral)

    MOVF    RX_DATA, W
    ANDLW   11000000B       ; Sadece ust 2 bite bak
    MOVWF   TempVar         ; TempVar'a kaydet

    ; Kontrol: 10xxxxxx (0x80) mi?
    MOVF    TempVar, W
    SUBLW   10000000B
    BTFSC   STATUS, 2
    GOTO    CMD_SET_CURTAIN_LOW

    ; Kontrol: 11xxxxxx (0xC0) mi?
    MOVF    TempVar, W
    SUBLW   11000000B
    BTFSC   STATUS, 2
    GOTO    CMD_SET_CURTAIN_HIGH

    ; -------------------------------------------------------
    ; 2. GET KOMUTLARI KONTROLU (Tam E?le?me)
    ; -------------------------------------------------------
    ; 00000001B -> Get Curtain Low
    MOVF    RX_DATA, W
    SUBLW   00000001B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_CURTAIN_LOW

    ; 00000010B -> Get Curtain High
    MOVF    RX_DATA, W
    SUBLW   00000010B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_CURTAIN_HIGH

    ; 00000011B -> Get Temp Low
    MOVF    RX_DATA, W
    SUBLW   00000011B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_TEMP_LOW

    ; 00000100B -> Get Temp High
    MOVF    RX_DATA, W
    SUBLW   00000100B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_TEMP_HIGH

    ; 00000101B -> Get Pressure Low
    MOVF    RX_DATA, W
    SUBLW   00000101B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_PRESS_LOW

    ; 00000110B -> Get Pressure High
    MOVF    RX_DATA, W
    SUBLW   00000110B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_PRESS_HIGH

    ; 00000111B -> Get Light Low
    MOVF    RX_DATA, W
    SUBLW   00000111B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_LIGHT_LOW

    ; 00001000B -> Get Light High
    MOVF    RX_DATA, W
    SUBLW   00001000B
    BTFSC   STATUS, 2
    GOTO    CMD_GET_LIGHT_HIGH

    RETURN ; Tanimsiz komut

; --- GET ACTIONS ---
CMD_GET_CURTAIN_LOW:
    MOVF    DesiredCurtain_Frac, W
    CALL    UART_SEND_BYTE
    RETURN
CMD_GET_CURTAIN_HIGH:
    MOVF    DesiredCurtain, W
    CALL    UART_SEND_BYTE
    RETURN
CMD_GET_TEMP_LOW:
    MOVF    TEMP_FRAC, W
    CALL    UART_SEND_BYTE
    RETURN
CMD_GET_TEMP_HIGH:
    MOVF    TEMP_INTEGER, W
    CALL    UART_SEND_BYTE
    RETURN
CMD_GET_PRESS_LOW:
    MOVF    PRESS_FRAC, W
    CALL    UART_SEND_BYTE
    RETURN
CMD_GET_PRESS_HIGH:
    MOVF    PRESS_INTEGER, W
    CALL    UART_SEND_BYTE
    RETURN
CMD_GET_LIGHT_LOW:
    MOVF    LightValue_Frac, W
    CALL    UART_SEND_BYTE
    RETURN
CMD_GET_LIGHT_HIGH:
    MOVF    LightValue, W
    CALL    UART_SEND_BYTE
    RETURN

; --- SET ACTIONS ---
CMD_SET_CURTAIN_LOW:
    ; Python once 0x80 (Baslik) gonderdi, simdi asil veriyi bekliyoruz
    CALL    UART_WAIT_AND_READ  ; 2. Byte'i bekle (Kusurat degeri)
    MOVWF   DesiredCurtain_Frac ; Gelen degeri kaydet
    
    MOVLW   1                   ; Manuel Moda Gec
    MOVWF   SystemMode
    RETURN

CMD_SET_CURTAIN_HIGH:
    ; Python once 0xC0 (Baslik) gonderdi, simdi asil veriyi bekliyoruz
    CALL    UART_WAIT_AND_READ  ; 2. Byte'i bekle (Tam sayi 100 gibi)
    MOVWF   DesiredCurtain      ; Gelen degeri direk kaydet (Maskeleme yok!)
    
    MOVLW   1                   ; Manuel Moda Gec
    MOVWF   SystemMode
    RETURN

;====================================================================
; UART SEND BYTE (VERI GONDERME)
;====================================================================
UART_SEND_BYTE:
    BANKSEL TXSTA
TX_WAIT:
    BTFSS   TXSTA, 1        ; TRMT (Buffer bos mu?)
    GOTO    TX_WAIT
    
    BANKSEL TXREG
    MOVWF   TXREG           ; W registerindeki veriyi gonder
    RETURN

;====================================================================
; MOTOR SÜRME (Degismedi)
;====================================================================
MOTORU_SUR_MANUEL:
    MOVF    ShadowPORTD, W
    MOVWF   TempVar
    MOVLW   11110000B
    ANDWF   TempVar, F
    
    MOVF    StepPhase, W
    SUBLW   0
    BTFSC   STATUS, 2
    GOTO    PHASE_0
    MOVF    StepPhase, W
    SUBLW   1
    BTFSC   STATUS, 2
    GOTO    PHASE_1
    MOVF    StepPhase, W
    SUBLW   2
    BTFSC   STATUS, 2
    GOTO    PHASE_2
    GOTO    PHASE_3

PHASE_0:
    MOVLW   00000001B
    GOTO    BIRLESTIR
PHASE_1:
    MOVLW   00000010B
    GOTO    BIRLESTIR
PHASE_2:
    MOVLW   00000100B
    GOTO    BIRLESTIR
PHASE_3:
    MOVLW   00001000B
    GOTO    BIRLESTIR

BIRLESTIR:
    IORWF   TempVar, W
    MOVWF   ShadowPORTD
    MOVWF   PORTD
    CALL    DELAY_STEP
    RETURN

;====================================================================
; BMP180 FONKS?YONLARI
;====================================================================
BMP180_READ_TEMP:
    ; S?cakl?k Ölçüm Komutu
    CALL    SOFT_I2C_START
    MOVLW   0xEE
    CALL    SOFT_I2C_WRITE
    MOVLW   0xF4
    CALL    SOFT_I2C_WRITE
    MOVLW   0x2E
    CALL    SOFT_I2C_WRITE
    CALL    SOFT_I2C_STOP
    
    MOVLW   10
    CALL    DELAY_MS_PARAM

    ; Veriyi Al
    CALL    SOFT_I2C_START
    MOVLW   0xEE
    CALL    SOFT_I2C_WRITE
    MOVLW   0xF6
    CALL    SOFT_I2C_WRITE
    
    CALL    SOFT_I2C_STOP
    CALL    SOFT_I2C_START
    
    MOVLW   0xEF
    CALL    SOFT_I2C_WRITE
    
    CALL    SOFT_I2C_READ
    CALL    SOFT_SEND_ACK
    MOVF    I2C_BUFFER, W
    MOVWF   TEMP_MSB
    
    CALL    SOFT_I2C_READ
    CALL    SOFT_SEND_NACK
    MOVF    I2C_BUFFER, W
    MOVWF   TEMP_LSB
    
    CALL    SOFT_I2C_STOP
    
    ; Basitle?tirilmi?: MSB'yi kullan
    MOVF    TEMP_MSB, W
    MOVWF   TEMP_INTEGER
    RETURN

;====================================================================
; BMP180 BASINÇ OKUMA
;====================================================================
BMP180_READ_PRESSURE:
    ; Bas?nç Ölçüm Komutu (OSS=3)
    CALL    SOFT_I2C_START
    MOVLW   0xEE
    CALL    SOFT_I2C_WRITE
    MOVLW   0xF4
    CALL    SOFT_I2C_WRITE
    MOVLW   0xF4                ; 0x34 + 0xC0
    CALL    SOFT_I2C_WRITE
    CALL    SOFT_I2C_STOP
    
    MOVLW   30
    CALL    DELAY_MS_PARAM

    ; Bas?nç Verisini Al
    CALL    SOFT_I2C_START
    MOVLW   0xEE
    CALL    SOFT_I2C_WRITE
    MOVLW   0xF6
    CALL    SOFT_I2C_WRITE
    
    CALL    SOFT_I2C_STOP
    CALL    SOFT_I2C_START
    
    MOVLW   0xEF
    CALL    SOFT_I2C_WRITE
    
    CALL    SOFT_I2C_READ       ; MSB
    CALL    SOFT_SEND_ACK
    MOVF    I2C_BUFFER, W
    MOVWF   PRESS_MSB
    
    CALL    SOFT_I2C_READ       ; LSB
    CALL    SOFT_SEND_ACK
    MOVF    I2C_BUFFER, W
    MOVWF   PRESS_LSB
    
    CALL    SOFT_I2C_READ       ; XLSB
    CALL    SOFT_SEND_NACK
    MOVF    I2C_BUFFER, W
    MOVWF   PRESS_XLSB
    
    CALL    SOFT_I2C_STOP
    
    MOVF    PRESS_MSB, W
    MOVWF   PRESS_INTEGER
    RETURN

;====================================================================
; BASINÇ YAZDIRMA FONKS?YONU
;====================================================================
PRINT_PRESSURE:
    MOVF    PRESS_INTEGER, W
    MOVWF   TempVar
    
    MOVF    TempVar, W
    MOVWF   TempVar2        ; Yedek
    
    BCF     STATUS, 0
    RRF     TempVar, F      ; TempVar / 2
    
    MOVF    TempVar, W
    ADDWF   TempVar2, F     ; 1.5x
    
    MOVLW   150
    SUBWF   TempVar2, W
    BTFSC   STATUS, 0
    MOVLW   150
    BTFSS   STATUS, 0
    MOVF    TempVar2, W
    
    MOVWF   TempVar
    
    MOVLW   50
    ADDWF   TempVar, F
    
    MOVF    TempVar, W
    CALL    BIN_TO_DEC_PRESS
    
    MOVLW   '1'
    CALL    LCD_CHAR
    MOVLW   '0'
    CALL    LCD_CHAR
    
    MOVLW   '0'
    ADDWF   Press_H, W
    CALL    LCD_CHAR
    
    MOVLW   '0'
    ADDWF   Press_T, W
    CALL    LCD_CHAR
    
    RETURN

;====================================================================
; BASINÇ ?Ç?N BIN TO DEC
;====================================================================
BIN_TO_DEC_PRESS:
    MOVWF   TempVar2
    CLRF    Press_Th
    CLRF    Press_H
    CLRF    Press_T
    CLRF    Press_O
    
PRESS_HUNDREDS:
    MOVLW   100
    SUBWF   TempVar2, W
    BTFSS   STATUS, 0
    GOTO    PRESS_TENS
    MOVWF   TempVar2
    INCF    Press_H, F
    GOTO    PRESS_HUNDREDS
    
PRESS_TENS:
    MOVLW   10
    SUBWF   TempVar2, W
    BTFSS   STATUS, 0
    GOTO    PRESS_ONES
    MOVWF   TempVar2
    INCF    Press_T, F
    GOTO    PRESS_TENS
    
PRESS_ONES:
    MOVF    TempVar2, W
    MOVWF   Press_O
    RETURN

;====================================================================
; SOFTWARE I2C FONKS?YONLARI
;====================================================================
SOFT_I2C_START:
    BANKSEL PORTC
    SDA_HIGH
    SCL_HIGH
    CALL    I2C_DELAY
    SDA_LOW
    CALL    I2C_DELAY
    SCL_LOW
    RETURN

SOFT_I2C_STOP:
    BANKSEL PORTC
    SDA_LOW
    SCL_HIGH
    CALL    I2C_DELAY
    SDA_HIGH
    CALL    I2C_DELAY
    RETURN

SOFT_I2C_WRITE:
    MOVWF   I2C_BUFFER
    MOVLW   8
    MOVWF   BIT_CNT
    
WRITE_LOOP:
    RLF     I2C_BUFFER, F
    BTFSC   STATUS, 0
    GOTO    BIT_IS_1
    GOTO    BIT_IS_0

BIT_IS_1:
    SDA_HIGH
    GOTO    CLOCK_PULSE
BIT_IS_0:
    SDA_LOW
    GOTO    CLOCK_PULSE

CLOCK_PULSE:
    CALL    I2C_DELAY
    SCL_HIGH
    CALL    I2C_DELAY
    SCL_LOW
    DECFSZ  BIT_CNT, F
    GOTO    WRITE_LOOP
    
    ; ACK Pulse
    SDA_HIGH
    CALL    I2C_DELAY
    SCL_HIGH
    CALL    I2C_DELAY
    SCL_LOW
    RETURN

SOFT_I2C_READ:
    CLRF    I2C_BUFFER
    MOVLW   8
    MOVWF   BIT_CNT
    
    BANKSEL TRISC
    BSF     TRISC, 4            ; SDA Input
    BANKSEL PORTC
    
READ_LOOP:
    CALL    I2C_DELAY
    SCL_HIGH
    CALL    I2C_DELAY
    
    BCF     STATUS, 0
    BTFSC   PORTC, 4
    BSF     STATUS, 0
    RLF     I2C_BUFFER, F
    
    SCL_LOW
    DECFSZ  BIT_CNT, F
    GOTO    READ_LOOP
    
    BANKSEL TRISC
    BCF     TRISC, 4            ; SDA Output
    BANKSEL PORTC
    RETURN

SOFT_SEND_ACK:
    SDA_LOW
    CALL    I2C_DELAY
    SCL_HIGH
    CALL    I2C_DELAY
    SCL_LOW
    SDA_HIGH
    RETURN

SOFT_SEND_NACK:
    SDA_HIGH
    CALL    I2C_DELAY
    SCL_HIGH
    CALL    I2C_DELAY
    SCL_LOW
    RETURN

I2C_DELAY:
    NOP
    NOP
    NOP
    NOP
    NOP
    RETURN

;====================================================================
; LCD FONKS?YONLARI
;====================================================================
LCD_INIT:
    CALL    DELAY_LONG
    MOVLW   0x30
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    CALL    DELAY_MS
    MOVLW   0x30
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    CALL    DELAY_MS
    MOVLW   0x30
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    CALL    DELAY_MS
    MOVLW   0x20
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    CALL    DELAY_MS
    MOVLW   0x28
    CALL    LCD_CMD
    MOVLW   0x0C
    CALL    LCD_CMD
    MOVLW   0x06
    CALL    LCD_CMD
    MOVLW   0x01
    CALL    LCD_CMD
    RETURN

LCD_CMD:
    MOVWF   LCD_Temp
    MOVF    LCD_Temp, W
    ANDLW   0xF0
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    SWAPF   LCD_Temp, W
    ANDLW   0xF0
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    CALL    DELAY_MS
    RETURN

LCD_CHAR:
    MOVWF   LCD_Temp
    MOVF    LCD_Temp, W
    ANDLW   0xF0
    IORLW   0x04
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    SWAPF   LCD_Temp, W
    ANDLW   0xF0
    IORLW   0x04
    MOVWF   PORTB
    BSF     PORTB, 3
    NOP
    BCF     PORTB, 3
    CALL    DELAY_US
    RETURN

LCD_LINE1:
    MOVLW   0x80
    CALL    LCD_CMD
    RETURN

LCD_LINE2:
    MOVLW   0xC0
    CALL    LCD_CMD
    RETURN

LCD_CLEAR:
    MOVLW   0x01
    CALL    LCD_CMD
    CALL    DELAY_MS
    RETURN

;====================================================================
; YARDIMCI FONKS?YONLAR
;====================================================================
BIN_TO_DEC:
    MOVWF   TempVar
    CLRF    Bin_H
    CLRF    Bin_T
    CLRF    Bin_O
HUNDREDS:
    MOVLW   100
    SUBWF   TempVar, W
    BTFSS   STATUS, 0
    GOTO    TENS
    MOVWF   TempVar
    INCF    Bin_H, F
    GOTO    HUNDREDS
TENS:
    MOVLW   10
    SUBWF   TempVar, W
    BTFSS   STATUS, 0
    GOTO    ONES
    MOVWF   TempVar
    INCF    Bin_T, F
    GOTO    TENS
ONES:
    MOVF    TempVar, W
    MOVWF   Bin_O
    RETURN

PRINT_NUMBERS:
    MOVLW   '0'
    ADDWF   Bin_H, W
    CALL    LCD_CHAR
    MOVLW   '0'
    ADDWF   Bin_T, W
    CALL    LCD_CHAR
    MOVLW   '0'
    ADDWF   Bin_O, W
    CALL    LCD_CHAR
    RETURN

;====================================================================
; GEC?KME FONKS?YONLARI
;====================================================================
DELAY_MS_PARAM:
    MOVWF   DelayVar2
LOOP_OUT:
    MOVLW   250
    MOVWF   DelayVar1
LOOP_IN:
    NOP
    DECFSZ  DelayVar1, F
    GOTO    LOOP_IN
    DECFSZ  DelayVar2, F
    GOTO    LOOP_OUT
    RETURN

DELAY_STEP:
    MOVLW   15
    MOVWF   DelayVar1
DL1:
    MOVLW   255
    MOVWF   DelayVar2
DL2:
    DECFSZ  DelayVar2, F
    GOTO    DL2
    DECFSZ  DelayVar1, F
    GOTO    DL1
    RETURN

DELAY_ADC:
    MOVLW   30
    MOVWF   DelayVar1
DL_A:
    DECFSZ  DelayVar1, F
    GOTO    DL_A
    RETURN

DELAY_MS:
    MOVLW   5
    MOVWF   DelayVar1
D_MS:
    MOVLW   200
    MOVWF   DelayVar2
D_MS2:
    DECFSZ  DelayVar2, F
    GOTO    D_MS2
    DECFSZ  DelayVar1, F
    GOTO    D_MS
    RETURN

DELAY_US:
    MOVLW   10
    MOVWF   DelayVar1
D_US:
    DECFSZ  DelayVar1, F
    GOTO    D_US
    RETURN

DELAY_LONG:
    MOVLW   50
    MOVWF   DelayVar1
D_L:
    MOVLW   255
    MOVWF   DelayVar2
D_L2:
    DECFSZ  DelayVar2, F
    GOTO    D_L2
    DECFSZ  DelayVar1, F
    GOTO    D_L
    RETURN
; --- YENI EKLENECEK FONKSIYON: 2. BYTE'I BEKLE ---
UART_WAIT_AND_READ:
    BANKSEL PIR1
WAIT_DATA:
    BTFSS   PIR1, 5         ; Veri geldi mi? (RCIF)
    GOTO    WAIT_DATA       ; Gelmediyse bekle
    
    BANKSEL RCREG
    MOVF    RCREG, W        ; Gelen veriyi W'ye al
    RETURN
    END