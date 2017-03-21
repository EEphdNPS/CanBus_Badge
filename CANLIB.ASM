;**********************************************************
;**********************************************************


; MCP2510 Instructions
#define d2510Rd      0x03      ; MCP2510 read instruction
#define d2510Wrt     0x02      ; MCP2510 write instruction
#define d2510Reset   0xC0      ; MCP2510 reset instruction
#define d2510RTS     0x80      ; MCP2510 RTS instruction
#define d2510Status  0xA0      ; MCP2510 Status instruction
#define d2510BitMod  0x05      ; MCP2510 bit modify instruction



;**********************************************************
;*************** SPECIAL CAN MACROS ***********************
;**********************************************************

; Read 2510 register Reg and return data in W.
SPI_Read macro Reg
          movlw     Reg
          call      Rd2510Reg
          endm

; Write literal byte to 2510 register Reg.
SPI_WriteL macro Reg,LitData
          movlw     LitData
          movwf     b2510RegData
          movlw     Reg
          call      Wrt2510Reg
          endm

; Write Data byte to 2510 register Reg.
SPI_WriteV macro Reg,RegData
          movfw     RegData
          movwf     b2510RegData
          movlw     Reg
          call      Wrt2510Reg
          endm

; Write W byte to 2510 register Reg.
SPI_WriteW macro Reg
          movwf     b2510RegData
          movlw     Reg
          call      Wrt2510Reg
          endm


; Write bits determined by Mask & Data to 2510 register Reg.
SPI_BitMod macro Reg,Mask,Data
          movlw     Mask
          movwf     b2510RegMask
          movlw     Data
          movwf     b2510RegData
          movlw     Reg
          call      BitMod2510
          endm

; Arm xmit buffers for xmission
SPI_Rts macro Data
          movlw     Data
          call      Rts2510
          endm


;**********************************************************
;**********************************************************
;Support routines for communicating with 2510 chip
;**********************************************************
;**********************************************************

;******************************************************
;CheckCANMsg
;
; Checks for message in Receive Buf 1.  If no message pending return
; with Z flag set.
;         
; If message pending:
;     Load iRecID_L,iRecID_H with ID.
;     Load bRecCount with number of bytes of data received.
;     Load buffer at pRecDataBase with data
;     Clear 2510 Receive Buffer 1 interrupt flag
;     Set tbRxMsgPend flag and clear Z flag.
;
; NOTE: If message already pending doesn't check for new message.
;
;******************************************************/
CheckCANMsg

          bcf       _Z                  ; for return
          skipClr   tbRxMsgPend         ; new CAN message received
          return                        ; Message already pending

     ;; Test for Message pending in Receive Buffer 1
          SPI_Read  CANINTF
          andlw     0x02      

          skipNZ
          return              ; Nothing in Rec Buf 1

          bsf       tbRxMsgPend         ; new CAN message received

     ;; Get ID of message source 
          SPI_Read  RXB1SIDH
          movwf     iRecID_H
          SPI_Read  RXB1SIDL
          andlw     0xE0
          movwf     iRecID_L

     ;; Get number of bytes of data
          SPI_Read  RXB1DLC
          andlw     0x0F
          movwf     bRecCount

     ;; Get data from buffer. Up to 8 bytes based on 
          clrf      bCnt

jRxChk11  jmpFeqF   bCnt,bRecCount,jRxChk90            ; no data left

     ;; Calculate correct 2510 receive buffer location
          movlw     RXB1D0
          addwf     bCnt,W

     ;; Get data byte
          call      Rd2510Reg
          movwf     b2510RegData     ; temporary save

     ;; Calculate destination buffer location
          movlw     pRecDataBase
          addwf     bCnt,W
          movwf     FSR

     ;; Store data in buffer
          movfw     b2510RegData     ; temporary save
          movwf     INDF
          incf      bCnt,F
          goto      jRxChk11

jRxChk90
          SPI_BitMod CANINTF,0x02,0     ; Clear receive buffer 1 interrupt
          bcf       _Z                  ; signal data pending
          return


;**********************************************************
;SetConfigMode
;
;// Function Name: Set_Config_Mode()
;**********************************************************
SetConfigMode
;  SPI_BitMod(CANCTRL, 0xE0, 0x80);    //Config. mode/
          bL2bV     0xE0,b2510RegMask
          bL2bV     0x80,b2510RegData
          movlw     CANCTRL
          call      BitMod2510

jSetConfigM1
          movlw     CANSTAT
          call      Rd2510Reg
          andlw     0xE0
          xorlw     0x80
          jmpNZ     jSetConfigM1

          return


;**********************************************************
;SetNormalMode
;
;// Function Name: Set_Normal_Mode()
;**********************************************************
SetNormalMode

          bL2bV     0xE0,b2510RegMask
          bL2bV     0x00,b2510RegData
          movlw     CANCTRL
          call      BitMod2510

jSetNormalM1
          movlw     CANSTAT
          call      Rd2510Reg
          andlw     0xE0
          jmpNZ     jSetNormalM1

          return

;**********************************************************
;WaitANDeqZ
;         Wait for byte from address in W to AND with mask in
;         b2510RegMask to be zero. Uses b2510RegAdr to hold address.
;         
;**********************************************************
WaitANDeqZ
          movwf     b2510RegAdr         ; save

jWaitANDeqZ
          movfw     b2510RegAdr         ; save
          call      Rd2510Reg
          andwf     b2510RegMask,W
          jmpNZ     jWaitANDeqZ
          return


;**********************************************************
;**********************************************************


;**********************************************************
;**************** BASIC COMMUNICATION *********************
;**********************************************************


;**********************************************************
;Get2510Status
;         Get Status byte from 2510.
;// Function Name: SPI_ReadStatus()
;**********************************************************
Get2510Status
          call      InitSPIBuf
          movlw     d2510Status          ; MCP2510 Status instruction
          call      LoadSPIByte
          movlw     1                   ; expect 1 byte answer
          call      LoadSPIZeros
          call      ExchangeSPI
          call      WaitSPIExchange
          return

;**********************************************************
;Rd2510Reg
;         Read 2510 register at address in W. Return results
;         in W. Uses b2510RegAdr to hold address.
;// Function Name: SPI_Read(uint address)
;**********************************************************
Rd2510Reg
          movwf     b2510RegAdr         ; save
          call      InitSPIBuf
          movlw     d2510Rd              ; MCP2510 read instruction
          call      LoadSPIByte
          movfw     b2510RegAdr         ; get address
          call      LoadSPIByte
          movlw     1                   ; expect 1 byte answer
          call      LoadSPIZeros
          call      ExchangeSPI
          call      WaitSPIExchange
          movfw     pSPIBufBase+2
          return

;**********************************************************
;Wrt2510Reg
;         Write byte in b2510RegData to 2510 register at location in W. 
;         Uses b2510RegAdr to hold address.
;// Function Name: SPI_Write(uint address)
;**********************************************************
Wrt2510Reg
          movwf     b2510RegAdr         ; save
          call      InitSPIBuf
          movlw     d2510Wrt             ; MCP2510 write instruction
          call      LoadSPIByte
          movfw     b2510RegAdr         ; get address
          call      LoadSPIByte
          movfw     b2510RegData        ; get data
          call      LoadSPIByte
          call      ExchangeSPI
          call      WaitSPIExchange
          return


;**********************************************************
;BitMod2510
;// Function Name: SPI_BitMod()
;         Write data in b2510RegData using mask in b2510RegMask to 
;         address in W. Uses b2510RegAdr to hold address.
;**********************************************************
BitMod2510
          movwf     b2510RegAdr         ; save
          call      InitSPIBuf

          movlw     d2510BitMod         ; MCP2510 bit modify instruction
          call      LoadSPIByte

          movfw     b2510RegAdr         ; address
          call      LoadSPIByte

          movfw     b2510RegMask        ; mask
          call      LoadSPIByte

          movfw     b2510RegData        ; data
          call      LoadSPIByte

          call      ExchangeSPI
          call      WaitSPIExchange
          return


;**********************************************************
;Rts2510
;         Request to send to MCP2510.
;         Send the request to send instruction to the CANbus Controller ORed
;         with value in W.  Uses b2510RegData.
;// Function Name: SPI_Reset()
;**********************************************************
Rts2510
          movwf     b2510RegData
          call      InitSPIBuf

          movlw     d2510RTS            ; MCP2510 RTS instruction
          iorwf     b2510RegData,W      ; get data and OR it with RTS
          call      LoadSPIByte

          call      ExchangeSPI
          call      WaitSPIExchange
          return


;**********************************************************
;Reset2510
;         Reset MCP2510.
;// Function Name: SPI_Reset()
;**********************************************************
Reset2510
          call      InitSPIBuf
          movlw     d2510Reset           ; MCP2510 reset instruction
          call      LoadSPIByte
          call      ExchangeSPI
          call      WaitSPIExchange
          return



;**********************************************************
;***************** LOCAL - DON'T CALL DIRECTLY ************
;**********************************************************

;**********************************************************
;InitSPIPort
;         Intialize SPI port
;**********************************************************
InitSPIPort
	BANK0
          bcf       _SSPEN         ; disable SPI     
          movlw     0x11           ; SPI Master, Idle high, Fosc/16
          movwf     SSPCON
          bsf       _SSPEN         ; enable SPI     
          bcf       _SSPIF         ; clear interrupt flag
          BANK1
          bsf       _SSPIE_P       ; SSP int enable (BANK 1)
          BANK0
          return

;**********************************************************
;InitSPIBuf
;         Initializes SPI buffer for transaction.  Sets up
;         FSR as buffer pointer.
;**********************************************************
InitSPIBuf
          clrf      bSPICnt
          movlw     pSPIBufBase
          movwf     pSPIBuf
          movwf     FSR
          return

;**********************************************************
;LoadSPIByte
;         Load byte in W to SPI buffer.  Assumes FSR is pointer.
;**********************************************************
LoadSPIByte
          movwf     INDF
          incf      FSR,F
          return

;**********************************************************
;LoadSPIZeros
;         Load number of zeros in W to SPI buffer.  
;         Assumes FSR is pointer.
;**********************************************************
LoadSPIZeros
          andlw     0xFF
          skipNZ
          return                        ; finished
          clrf      INDF
          incf      FSR,F
          addlw     0xFF                ; Subtract 1 from W
          jmpNZ     LoadSPIZeros
          return

;**********************************************************
;ExchangeSPI
;         Initiate SPI transaction.  
;**********************************************************
ExchangeSPI
     ;; Get number of bytes to exchange
          bV2bV     FSR,bSPICnt
          movlw     pSPIBufBase
          subwf     bSPICnt,F

          skipNZ
          return                        ; nothing to exchange

          movlw     pSPIBufBase
          movwf     pSPIBuf

     ;; Load 1st byte to begin exchange
          bcf       tp2510_CS_           ; CS_ for 2510 chip
          movfw     pSPIBufBase         ; get 1st byte in buffer
          movwf     SSPBUF              ; send it
          return


;**********************************************************
;WaitSPIExchange
;         Wait for SPI transaction to be completed.
;**********************************************************
WaitSPIExchange
          jmpFneZ   bSPICnt,WaitSPIExchange
          return

