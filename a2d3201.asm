
;**********************************************************
;Read3201
;         This functions reads MCP3201 and store the result 
;         in iA2DValue as a 12 bit value.
;**********************************************************
Read3201

          bcf       tpA2D_CS_           ; CS_ for 3201 A2D chip

          call      InitSPIBuf
          movlw     2                   ; expect 2 bytes
          call      LoadSPIZeros

     ;; Initiate SPI transaction.  
     ;; Get number of bytes to exchange
          bV2bV     FSR,bSPICnt
          movlw     pSPIBufBase
          subwf     bSPICnt,F

          movlw     pSPIBufBase
          movwf     pSPIBuf

     ;; Load 1st byte to begin exchange
          movfw     pSPIBufBase         ; get 1st byte in buffer
          movwf     SSPBUF              ; send it

          call      WaitSPIExchange

          bsf       tpA2D_CS_           ; CS_ for 3201 A2D chip

          bV2bV     pSPIBufBase,iA2DValue+1
          bV2bV     pSPIBufBase+1,iA2DValue

     ;; Shift right by 1 to remove extra b1 bit
          iShiftR   iA2DValue

     ;; remove dummy upper 4 bits
          movlw     0x0F
          andwf     iA2DValue+1,F
          return


