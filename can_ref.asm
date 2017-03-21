;*******************************************************************
; Microchip CAN Reference Design
;
; Mike Richitelli
; Diversified Engineering
; 283 Indian River Road
; Orange, CT 06477
; (203)799-7875 fax(203)799-7892
; WWW.DIVERSIFIEDENGINEERING.NET 
;
;*******************************************************************
;*******************************************************************

          TITLE " CAN_Ref Design "

;*******************************************************************

dVersion       equ  1
dRelease       equ  5

;======================================================================
; Transmits CAN message every 131 mSec.  Message contains two data bytes
;         that represent a 12 bit value with least significant byte
;         sent first.
; Cycles between three outputs:
;         Pot:  Value goes from 0 to 0xFF0 as Pot is turned clockwise.
;               ID is selected from DIP switches #3 and #4 as follows:
;                   #3 #4  ID
;                   0  0   transmission disabled 
;                   0  1   0x100
;                   1  0   0x200
;                   1  1   0x300
;
;         Push button switch: Switch open => 0, Switch closed => 0xFFF   
;               ID is Pot ID + 0x010
;
;         CdS:  Value goes from 0 to 0xFF0 as Pot is turned clockwise.
;               ID is Pot ID + 0x020
;
; CAN messages received are assumed to be 12 bit data sent as two bytes, 
;         least significant byte first.
;
;         The base ID for receiving CAN messages is specified by DIP 
;         switches #1 and #2:
;                   #1 #2  ID
;                   0  0   0x000
;                   0  1   0x100
;                   1  0   0x200
;                   1  1   0x300
;
;         Lamp: If the message ID matches the ID selected by the DIP 
;               switches the 12 bit data is used to generate a PWM output 
;               where a 0 value gives a zero duty cycle and 0xFFF generates 
;               a 100% duty cycle.  The lamp output is proportional to
;               the duty cycle.
;               ID is Base ID
;
;         LED: On if value received is >= 0x800 and off if < 0x800.
;               ID is Base ID + 0x010
;
;======================================================================

;----- PIC16F876 Micro -----;

          LIST P=16F876
          LIST r=dec,x=on,t=off

#include "P16F876.INC"

  __CONFIG _BODEN_ON&_CP_OFF&_WRT_ENABLE_ON&_PWRTE_ON&_WDT_OFF&_HS_OSC&_DEBUG_OFF&_CPD_OFF&_LVP_OFF
  __IDLOCS (dVersion<<8)|dRelease  ; version: vvrr , vv- version, rr - release

;---------------------------;

#include "MACROS16.INC"
#include "MCP2510.INC"

;          errorlevel 0,-306,-302,-305

 
;******** constants

;Crystal freq 4.00 MHz, Fosc/4 = 1 uS
;
; Timer 1: Uses no prescale => Tic is 1 uSec
;       8 bit rollover 256 uSec
;       16 bit rollover 65.536 mSec

;   8 bit timers
;    TMR1L: 1 uSec tics with maximum of 1/2 rollover = 128 uSec maximum
;    TMR1H: 256 uSec tics with maximum of 1/2 rollover = 32.768 msec maximum



;======================================================================

;************************
; A/D selection ( value of ADCON0 )

#define dA2DRA0     B'01000000'         ; fosc/8 clk, RA0, A/D off
#define dA2DRA3     B'01011000'         ; fosc/8 clk, RA3, A/D off


;************************
; special function defines

#define _SSPEN      SSPCON,SSPEN        ; SPI enable

;************************

;; General control flags definitions

#define tbWork          bGenFlags1,0   ; working bit
#define tbReset         bGenFlags1,1   ; must reset 
#define tbNewSPI        bGenFlags1,2   ; new SPI data available
#define tbRxMsgPend     bGenFlags1,3   ; new CAN message received
#define tbTxMsg         bGenFlags1,4   ; xmit next CAN message
#define tbRC2NowHigh    bGenFlags1,5   ; Robot PWM signal high


;*****************  PIN DEFINITIONS **************************

#define tp2510_CS_   PORTA,1       ; CS_ for 2510 chip

;; I/O 
#define tpSwitch_    PORTB,1       ; Push button switch, Open => high
#define tpLED        PORTB,2       ; LED 

;; Analog In 
#define tpA2D_CS_    PORTB,1       ; CS_ for 3201 A2D chip
#define tpEE_CS_     PORTB,2       ; CS_ for 25040 E2

;*****************  LOCAL REGISTER STORAGE **************************
;
;
;============ BANK 0 =================

 cblock   0x20
     ;; interrupt variables
          bIntSaveSt       ; save Status
          bIntSaveFSR      ; save FSR
          bIntSavPCLATH    ; interrupt storage for PCLATH
          bIntWork         ; working
          iIntWork:2       ; working

     ;; general work space
	bGenFlags1       ; general control flags 1
	bGenFlags2       ; general control flags 2
          bWork            ; work byte
          bWork1           ; work byte 
	iWork:2          ; work integer
	bCnt             ; work byte counter

     ;; Arithmetic
          iA:2             ; 2 byte integer
          iB:2             ; 2 byte integer

     ;; Timer1
          iTimer1:2        ; counts Timer1 rollover   
          bGenClk          ; general clock    
          bXmitClk         ; Countdown to xmit next message

     ;; In/Out variables
          iA2DValue:2      ; 12 bit or 8 bit A2D value   
          bPWMValue        ; 8 bit PWM value   
          iRecValue:2      ; 12 bit received value

     ;; general control
          bSwXmitID        ; ID for transmission from DIP switch
          bBaseRecID       ; ID for reception from DIP switch
          bRecIDNext       ; Rec Base ID + 1
          bXmitID          ; ID for transmission of next msg
          bNextMsgType     ; Select next msg

     ;; Received CAN message
          iRecID_L         ; ID of received message (3 bits left justified)
          iRecID_H         ; ID of received message (8 bits left justified)
          bRecCount        ; number of bytes received
          pRecDataBase:8   ; received data

     ;; Low level SPI interface
          b2510RegAdr      ; Register address
          b2510RegData     ; Data sent/received
          b2510RegMask     ; Bit Mask

       ; following used in interrupt      
          bSPICnt          ; # bytes remaining to receive
          pSPIBuf          ; Pointer into buffer   
          pSPIBufBase:12   ; Base of SPI receive/xmit buffer

 endc


; storage for interrupt service routine
; W saved in one of these locations depending on the page selected 
; at the time the interrupt occured

bIntSaveW0 equ  0x7F       ; interrupt storage for W

;============ BANK 1 =================
bIntSaveW1 equ  0xFF       ; interrupt storage for W

;*******************************************************************
;********** LOCAL MACROS *******************************************
;*******************************************************************
; 
; Shift left 2 byte integer once.
iShiftL macro    iVar
        bcf      _C                ; clear carry bit    
        rlf      iVar,F
        rlf      iVar+1,F
        endm

; Shift right 2 byte integer once.
iShiftR macro    iVar
        bcf      _C               ; clear carry bit    
        rrf      iVar+1,F
        rrf      iVar,F
        endm

; Increment 2 byte integer
intInc  macro   iVar
        incf    iVar,F
        skipNZ
        incf    iVar+1,F
        endm

; 
;; --------------------------------------------------------
;; Set TRM1H 8 bit clock
;    TMR1H: 256 uSec tics with maximum of 1/2 rollover = 32.768 msec maximum
;; --------------------------------------------------------
Set1HClock macro bClk,Value
          movfw     TMR1H
          addlw     Value
          movwf     bClk
          endm

;; --------------------------------------------------------
;; Jump to jLabel if TMR1H (low byte) < bClk
;; --------------------------------------------------------
jmp1HNotYet macro bClk,jLabel

          movfw     TMR1H
          subwf     bClk,W
          andlw     0x80
          jmpZ      jLabel
          endm

;; --------------------------------------------------------
;; Jump to jLabel if TMR1H (low byte) < bClk
;; --------------------------------------------------------
jmp1HDone macro bClk,jLabel

          movfw     TMR1H
          subwf     bClk,W
          andlw     0x80
          jmpNZ     jLabel
          endm


;********************************************************************
;      Begin Program Code
;********************************************************************

          ORG      0x0            ;memory @ 0x0
          nop                     ;nop ICD!!
	goto     HardStart

	ORG     04h             ;Interrupt Vector @ 0x4
;**********************************************************
; Interrupt service routine - must be at location 4 if page 1 is used
; Context save & restore takes ~20 instr
;**********************************************************
     ;; Global int bit, GIE, has been reset.
     ;; W saved in bIntSaveW0 or bIntSaveW1 depending on the bank selected at
     ;; the time the interrupt occured.
          movwf     bIntSaveW0      ; save W in either of two locations 
                                    ; depending on bank currently selected

     ;; only way to preserve Status bits (since movf sets Z) is with a 
     ;; swapf command now
          swapf     STATUS,W        ; Status to W with nibbles swapped
          BANK0
          movwf     bIntSaveSt
          movfw     FSR
          movwf     bIntSaveFSR     ; save FSR
          movf      PCLATH,W 
          movwf     bIntSavPCLATH   ; interrupt storage for PCLATH
          clrf      PCLATH          ; set to page 0

     ;; Must determine source of interrupt

     ;; SPI interrupt
	btfsc    _SSPIF        ; SPI interrupt
	goto     IntSPI

          jmpSet   _TMR1IF,jIntTimer1  ; Timer1 overflow interrupt flag

     ;; unknown
                   
     ;; restore registers and return
IntReturn          
          BANK0
          movf      bIntSavPCLATH,W   ; interrupt storage for PCLATH
          movwf     PCLATH
          movf      bIntSaveFSR,W  ; restore FSR
          movwf     FSR
          swapf     bIntSaveSt,W ; get swapped Status (now unswapped)
          movwf     STATUS       ; W to Status  ( bank select restored )
          swapf     bIntSaveW0,F ; swap original W in place
          swapf     bIntSaveW0,W ; now load and unswap ( no status change)
          retfie                 ; return from interrupt


;***************** ID TABLE ****************************
; Look up ID associated with bits 0,1 in W
RxIDTable addwf    PCL,F           ;Jump to char pointed to in W reg
                                      ;( adds 5bits from PCLATH )
          retlw    0x00  ; 0
          retlw    0x20  ; 1
          retlw    0x10  ; 2
          retlw    0x30  ; 3
RxIDTable_End
#if ( (RxIDTable & 0xF00) != (RxIDTable_End & 0xF00) )
       MESSG   "Warning - Table crosses page boundry in computed jump"
#endif

; Look up ID associated with bits 0,1 in W
TxIDTable addwf    PCL,F           ;Jump to char pointed to in W reg
                                      ;( adds 5bits from PCLATH )
          retlw    0xFF  ; 0
          retlw    0x20  ; 1
          retlw    0x10  ; 2
          retlw    0x30  ; 3
TxIDTable_End
#if ( (TxIDTable & 0xF00) != (TxIDTable_End & 0xF00) )
       MESSG   "Warning - Table crosses page boundry in computed jump"
#endif

;***************** LIBRARY STORAGE & FUNCTIONS ****************************

#include "CanLib.asm"         ; basic 2510 interface routines
#include "a2d3201.asm"        ; MCP3201 AD routines

;***************** Local Interrupt Handlers ****************************

          
;**********************************************************
;jIntTimer1 
;         Timer1 rollover interrupt.
;
;**********************************************************
jIntTimer1  ; Timer1 overflow interrupt flag
          bcf       _TMR1IF        ; timer1 rollover interrupt flag
          intInc    iTimer1

          jmpFeqZ   bXmitClk,IntReturn
          
          decfsz    bXmitClk,F     ; Countdown to xmit next message
          goto      IntReturn

     ; Countdown to xmit next message

          bsf       tbTxMsg        ; xmit next CAN msg     
          goto      IntReturn

;**********************************************************
;IntSPI                                 
; 
; A single buffer, at pSPIBufBase, is used for both SPI receive and
; transmit.  When a byte is removed from the buffer to transmit it is
; replaced by the byte received.  
; 
; When here the buffer pointer, pSPIBuf, points to the last byte loaded 
; for transmission. This is the location that the received byte will be stored.
; 
; When here the count, bSPICnt, contains the number of bytes remaining
; to be received.  This is one less then the number remaining to be
; transmitted.  When bSPICnt reaches zero the transaction is complete.
; 
;         
;**********************************************************
IntSPI    
          bcf       _SSPIF              ; clear interrupt flag

     ;; Transfer received byte to the next location in the buffer
          bV2bV     pSPIBuf,FSR
          incf      pSPIBuf,F

          movfw     SSPBUF              ; get data & clear buffer flag
          movwf     INDF                ; put it into SPI buffer

          decfsz    bSPICnt,F
          goto      jIntSPI1            ; More bytes to send

     ;; Last transaction completed
          bsf       tp2510_CS_           ; CS_ for 2510 chip
          goto      IntReturn

jIntSPI1
     ;; Fetch next byte from buffer and load it for transmission
          incf      FSR,F
          movfw     INDF                ; get byte from buffer
          movwf     SSPBUF              ; send it
          goto      IntReturn


;**********************************************************
;**********************************************************
;**********************************************************

HardStart 
          call      Init

     ;; Make sure no chips are selected
          bsf       tp2510_CS_   ; CS_ for 2510 chip

     ;; Read DIP switch and create bBaseRecID and bSwXmitID

     ;; Rec ID bits are at pins 0,1 of PORTC and are logic high = 1
          movfw     PORTC
          andlw     0x03
          call      RxIDTable
          movwf     bBaseRecID

     ;; Xmit ID bits are at pins 6,7 of PORTC and are logic low = 1
          swapf     PORTC,W
          movwf     bSwXmitID
          rrf	bSwXmitID,F
          rrf	bSwXmitID,W
          andlw     0x03
          call      TxIDTable
          movwf     bSwXmitID


     ;; ----------------- One time calculations ----------------

     ;; Setup SPI port
          call      InitSPIPort

     ;; Wait 28 mS for 2510 to initialize ( there is no significance to 28 mS -
     ;; we just selected a large time since time is not critical)
          Set1HClock bGenClk,100   ; 277.77 uSec tics
jInit5
          jmp1HNotYet bGenClk,jInit5


     ;; Setup all 2510 registers
          call      Init2510

          bsf       tbTxMsg             ; xmit flag

;; --------------------------------------------------------
;; ----------- MAIN LOOP ----------------------------------
;; --------------------------------------------------------

jMainLoop clrwdt


;;====================== XMIT CODE ========================

          jmpClr    tbTxMsg,jMain10     ; not time to xmit next CAN msg yet
          bcf       tbTxMsg             ; reset xmit flag

     ;; Reload counter
          movlw     2              ; 65 mS units
          movwf     bXmitClk       ; Countdown to xmit next message

          jmpFeqL   bXmitID,0xFF,jMain10 ; Transmission turned off

     ;; Time to xmit next CAN message.  Select source of message and ID
     ;; to use for transmission

;; <<<<< Analog Input Board >>>>>

          jmpFeqL   bNextMsgType,0,Xmit3201   
          jmpFeqL   bNextMsgType,1,XmitRA0   
          goto      jMain8

;********** POT **********     

Xmit3201
          call      Read3201            ; read 3201 AD
          movfw     bSwXmitID           ; Use DIP Tx address for transmission
          movwf     bXmitID
          incf      bNextMsgType,F      ; Next time use next source and ID
          goto      jMain8  

XmitRA0                                 ;; Use Pot as input
          movlw     dA2DRA0             ; fosc/8 clk, RA0, A/D off
          call      ReadA2D             ; Read A/D port in W
          movfw     bSwXmitID           ; Use DIP Tx address for transmission
          addlw     0x01
          movwf     bXmitID
          clrf      bNextMsgType        ; clear next message
          goto      jMain8

jMain8
          
     ;; Wait for pending messages to be sent (ALL BUFFERS)
          bL2bV     0x08,b2510RegMask
          movlw     TXB0CTRL
          call      WaitANDeqZ

     ;; Send CAN message with 
     ;;    ID = bXmitID 
     ;;    Two data bytes: iA2DValue,iA2DValue+1

          SPI_WriteV TXB0SIDH,bXmitID    ; Message ID
          SPI_WriteL TXB0SIDL,0x00       ; Send message - lower bits 0
          SPI_WriteL TXB0DLC,0x02        ; 2 data bytes

     ;; Send least significant byte first
          SPI_WriteV TXB0D0,iA2DValue
          SPI_WriteV TXB0D1,iA2DValue+1
          SPI_Rts   RTS0                ; Transmit buffer 0

jMain10

;;====================== RECEIVE CODE ========================

          call      CheckCANMsg

          jmpClr    tbRxMsgPend,jMainLoop

     ;; new CAN message received

          call      ParseCAN
          bcf       tbRxMsgPend         ; new CAN message received
          goto      jMainLoop

;**********************************************************
;OutputPWM
;       OutputPWM - Uses PWM1 output.
;        
;**********************************************************
OutputPWM    
          movfw     bPWMValue   ; 8 bit PWM value   
          movwf     iA
          clrf      iA+1

     ;; W = 0 - 255.  Load into PWM register.     
     ;; load LOWER 2 bits into CCP1CON bits 5,4
     ;; load UPPER 6 bits (shifted right by 2 ) into CCPR1
     ;; this is high res 8 bit mode (upper 2 bits of 10 bit word are zero)
          movf     iA,W       ; low byte to W
          clrf     iA+1
          rrf      iA,F       ; low bit to carry          
          rrf      iA+1,F      ; move carry into upper bit 
          rrf      iA,F       ; low bit to carry          
          rrf      iA+1,F      ; move carry into upper bit
          rrf      iA+1,F      ; move to 6,5
          rrf      iA+1,W      ; move to 5,4 in W
          andlw    B'00110000'   ; mask other bits
          iorlw    B'00001100'   ; turn on PWM mode
          movwf    CCP1CON       ; set PWM1 and lower 2 bits
     ;; get upper 6 bits
          movf     iA,W
          andlw    B'00111111'   ; mask upper 2 bits
          movwf    CCPR1L           
                              
          return

;**********************************************************
;ReadA2D
;         This functions reads analog input and stores the result 
;         in iA2DValue as a 12 bit value.  Value in W is used to set
;         ADCON0 to select correct port.
;**********************************************************
ReadA2D

     ;; setup A/D to select port, etc
          movwf     ADCON0

     ;; turn on A/D 
          bsf      ADCON0,0        ;A/D on
     ;; allow 50us for settling
          movlw     25
          movwf     bCnt
ReadAD10 
          decfsz    bCnt,F
          goto      ReadAD10

     ;; begin conversion
          bsf       ADCON0,2           ; GO
ReadAD20  jmpSet    ADCON0,2,ReadAD20   ; wait for done bit

          movf      ADRES,W
          movwf     iA2DValue
          clrf      iA2DValue+1

     ;; Convert to 12 bit
          iShiftL   iA2DValue
          iShiftL   iA2DValue
          iShiftL   iA2DValue
          iShiftL   iA2DValue
          return

;******************************************************
;ParseCAN <<<<<INPUTS>>>>>
;         Parse message. Assumes message is two byte 12 bit data.
;         Uses bBaseRecID and bRecIDNext to accept message for PWM output.
;******************************************************
ParseCAN

;********** Analog In Board **********

          movlw     b'00001111'
          andwf     iRecID_H,W
          movwf     iA 
          jmpFeqL   iA,0x0,IDx0             ;check for ID x0
          goto      jParCANRet          

IDx0                                              ;; x0 input send PWM to lamp
     ;; 12 bits of data 
          bV2bV     pRecDataBase,iRecValue
          bV2bV     pRecDataBase+1,iRecValue+1

     ;; new PWM value pending

          bV2bV     iRecValue,iA
          bV2bV     iRecValue+1,iA+1              ; 12 bit received value

     ;; convert to 8 for PWM out
          iShiftR   iA
          iShiftR   iA
          iShiftR   iA
          iShiftR   iA

     ;; Convert to 8 bit
          bV2bV     iA,bPWMValue
          call      OutputPWM    
          goto      jParCANRet

jParCANRet
          return

;******************************************************
;Init2510
;*  Function:   Init_MCP2510()
;*      Place MCP2510 initialization here...
;*******************************************************
Init2510
     ;; Reset 2510
          call      Reset2510

     ;; set CLKOUT prescaler to div by 4
          bL2bV     0x03,b2510RegMask
          bL2bV     0x02,b2510RegData
          movlw     CANCTRL
          call      BitMod2510

;Set physical layer configuration 
;
;     Fosc = 16MHz
;     BRP        =   7  (divide by 8)
;     Sync Seg   = 1TQ
;     Prop Seg   = 1TQ
;     Phase Seg1 = 3TQ
;     Phase Seg2 = 3TQ
;
;    TQ = 2 * (1/Fosc) * (BRP+1) 
;     Bus speed = 1/(Total # of TQ) * TQ
;
          SPI_WriteL CNF1,0x07           ; set BRP to div by 8

;#define BTLMODE_CNF3    0x80
;#define SMPL_1X         0x00
;#define PHSEG1_3TQ      0x10
;#define PRSEG_1TQ       0x00
          SPI_WriteL CNF2,0x90

;#define PHSEG2_3TQ      0x02
          SPI_WriteL CNF3,0x02

;
     ;; Configure Receive buffer 0 Mask and Filters 
     ;; Receive buffer 0 will not be used
          SPI_WriteL RXM0SIDH,0xFF
          SPI_WriteL RXM0SIDL,0xFF

          SPI_WriteL RXF0SIDH,0xFF
          SPI_WriteL RXF0SIDL,0xFF

          SPI_WriteL RXF1SIDH,0xFF
          SPI_WriteL RXF1SIDL,0xFF

     ;; Configure Receive Buffer 1 Mask and Filters 
          SPI_WriteL RXM1SIDH,0xFF 
          SPI_WriteL RXM1SIDL,0xE0

     ;; Initialize Filter 2 to match x0 bBaseRecID from  DIP switch
          SPI_WriteV RXF2SIDH,bBaseRecID
          SPI_WriteL RXF2SIDL,0x00       ; Make sure EXIDE bit (bit 3) is set correctly in filter

     ;; Initialize Filter 3 to match x1 from DIP switch
          incf       bBaseRecID,F
          SPI_WriteV RXF3SIDH,bBaseRecID
          SPI_WriteL RXF3SIDL,0x00

     ;; Initialize Filter 4 to match x2 from DIP switch
          incf       bBaseRecID,F
          SPI_WriteV RXF4SIDH,bBaseRecID
          SPI_WriteL RXF4SIDL,0x00       

     ;; Initialize Filter 5 to match x3 from DIP switch
          incf       bBaseRecID,F
          SPI_WriteV RXF5SIDH,bBaseRecID
          SPI_WriteL RXF5SIDL,0x00       

          movlw     b'11110000'
          andwf     bBaseRecID,F

     ;; Disable all MCP2510 Interrupts
          bL2bV     0x00,b2510RegData
          movlw     CANINTE
          call      Wrt2510Reg

     ;; Sets normal mode
          call      SetNormalMode
          return

;**********************************************************
;ProcessSPI     
;
;**********************************************************
ProcessSPI
          skipSet   bSPICnt,2
     ;; buffer not full yet
          return

     ;; disable SPI interupt
          BANK1
          bcf       _SSPIE_P       ; SSP int enable (BANK 1)
          BANK0


     ;; enable SPI
          BANK1
          bsf       _SSPIE_P  ; SSP int enable (BANK 1)
          BANK0
          return


;*******************************************************************
;WaitMSec
;	Delay W number of Msec Routines (255 max)
;         Actually slightly larger than 1 mS
;*******************************************************************

WaitMSec
	movwf	bCnt		;store Msec -> bCnt

jWaitMSec0
    	clrwdt         		;clear wdt

; TMR1H: 256 uSec tics with maximum of 1/2 rollover = 32.768 msec maximum
          Set1HClock bGenClk,4          ; 256 uS

jWaitMSec1
          jmp1HNotYet bGenClk,jWaitMSec1

          decfsz    bCnt,F
          goto      jWaitMSec0
	return

;
;**********************************************************
;Init
;         Initialize 
;        
;**********************************************************
Init                          
          clrwdt                ; required before changing wdt to timer0

     ;; clear peripheral interrupts
	BANK1
          clrf      PIE1_P
       
     ;; OPTION_REG: PortB Pullups on.
     ;; no prescale for WDT -> should always > 7 mSec  ( 18 mS nominal)
     ;; Timer 0:  Use 64 prescale for 0.27127 * 64 = 17.361 uSec tics 

          movlw     B'01000101'        ; Timer0 prescale 64
          movwf     OPTION_REG_P

     ;; clear bank 0 
          movlw     0x20
          movwf     FSR
jInitClr1 clrf      INDF
          incf      FSR,F
          jmpClr    FSR,7,jInitClr1

     ;; clear bank 1
          movlw     0xA0
          movwf     FSR
jInitClr2 clrf      INDF
          incf      FSR,F
          jmpSet    FSR,7,jInitClr2

          call      InitIO              ;initalize IO of microcontroller

     ;; configure Timer1:
          BANK0
          movlw     B'00000001'     ; Prescale = 1, Timer enabled 
          movwf     T1CON

	BANK1
          bsf       _TMR1IE_P      ; timer1 rollover interrupt enable (page 1)
	BANK0

     ;; init output PWM1 ( uses timer2 )
	BANK0
            ;; Timer2 ( 8 bit timer ) set for 
	movlw    B'00000100'     ; prescale of 1, internal clk, enable timer2
	movwf    T2CON
              ; load PWM counter(PR2) with 0x3F ( 8 bit high res mode)
              ; this gives a 15.625KHz signal with 4MHz crystal
	BANK1
	movlw    0x3F
	movwf    PR2_P             
	BANK0


     ;; for testing
          clrf      TMR1L
          clrf      TMR1H

     ;; turn on interrupts
	BANK0
          movlw    B'11000000'     ; Enable interrupts ( Periphrals only )
          movwf    INTCON

          return


;; INITIALIZE I/O OF MICROCONTROLLER

InitIO
          BANK1
        	movlw    b'00000100'    	;turn on A/D conversion RA0, RA1, RA3  
       	movwf    ADCON1_P

    ;; Port A
    ;;      0  in     <*>A2D input POT<*>
    ;;      1  out(1) 2510 chip select 
    ;;      2  in     <*>open<*>
    ;;      3  in     <*>open<*>
    ;;      4  in     <*>open<*>
    ;;      5  out(1) RST 2510 

          BANK0
	movlw	B'00000010'	;; initialize Port A outputs 
       	movfw  	PORTA       	
          BANK1
        	movlw   	B'11111101'
        	movwf   	TRISA_P         	;; set Port A


    ;; Port B 
    ;;      0  in     Interrupt from 2510
    ;;      1  out(1) <*>CS' MCP3201<*>
    ;;      2  out(1) <*>CS' 25C04<*>
    ;;      3  in     <*>open<*>
    ;;      4  in     <*>open<*>
    ;;      5  in     RX0BF from 2510 
    ;;      6  in     ICD
    ;;      7  in     ICD

          BANK0
	movlw	B'00000110'	;; initialize Port B outputs 
       	movfw  	PORTB       	
          BANK1
      	movlw   	B'11111001'
          movwf     TRISB_P         	;; set Port B

    ;; Port C
    ;;      0  in     DIP #1
    ;;      1  in     DIP #2
    ;;      2  out(0) <*>PWM Out<*>
    ;;      3  out(0) SPI clock - master
    ;;      4  in     SPI data in
    ;;      5  out(0) SPI data out
    ;;      6  in     DIP #3
    ;;      7  in     DIP #4
    
          BANK0
          movlw     B'00000000'
          movwf     PORTC
          BANK1

          movlw     B'11010011'
          movwf     TRISC_P          ;; set Port C

          BANK0
          return

 ifdef ROBUST
;; robust design - force WDT reset
          FILL (goto WDTReset1),(0xFFF-$)
WDTReset1  goto      WDTReset1
 endif


         END
