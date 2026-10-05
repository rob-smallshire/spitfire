; SPItFIRE SD Card Test
; Tests the Adafruit MicroSD breakout on header J4, selected by ~SS_2
; (74HC138 output Y2). Runs the SD SPI-mode initialisation sequence,
; printing each step's response, then reads the card's CID register and
; sector 0.
;
; SPI mode 3 (SCK idles HIGH), as MMFS uses for SD cards: the 6522 shift
; register samples MISO on the rising edge of CB1.
;
; Shared bus: an SD card keeps driving DO for a few clocks after CS goes
; high, so every deselect is followed by one byte of clocks with no
; device selected.

ORG &1900

; VIA registers (User VIA on Master Compact)
VIA_BASE = &FE60
IORB = VIA_BASE + &00
DDRB = VIA_BASE + &02
SR   = VIA_BASE + &0A
ACR  = VIA_BASE + &0B
PCR  = VIA_BASE + &0C
IER  = VIA_BASE + &0E

; Port B bit assignments
MOSI     = %00000001        ; PB0
SCK      = %00000010        ; PB1
SEL_MASK = %00011100        ; Decoder bits (PB2-PB4)

DEV_SD   = %00001000        ; Y2 (A1=1) -> ~SS_2 -> J4 microSD

NOT_SEL  = %11100011
NOT_SCK  = %11111101
NOT_MOSI = %11111110

SECTOR_BUF = &3000          ; 512-byte sector buffer (not saved with program)

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7

; Zero page
spi_temp = &70
ptr      = &72              ; 2 bytes, string pointer
r1       = &74              ; Last R1 response
cnt_lo   = &75              ; 16-bit loop counter
cnt_hi   = &76
card_v2  = &77              ; 1 if the card answered CMD8 (SD v2+)
tmp      = &78
cmd_idx  = &79
crc      = &7A
arg0     = &7B              ; Command argument, arg3 = MSB (sent first)
arg1     = &7C
arg2     = &7D
arg3     = &7E
buf_ptr  = &80              ; 2 bytes

.start
    JSR init_via
    LDA #0
    STA card_v2
    LDX #LO(s_title)
    LDY #HI(s_title)
    JSR print_str

    ; At least 74 clocks with CS high so the card enters native mode
    LDY #10
.power_clocks
    LDA #&FF
    JSR spi_xfer
    DEY
    BNE power_clocks

; ------ CMD0: GO_IDLE_STATE (enter SPI mode) ------
    LDX #LO(s_cmd0)
    LDY #HI(s_cmd0)
    JSR print_str
    LDA #10
    STA tmp
.cmd0_retry
    JSR zero_arg
    LDA #0
    LDX #&95                ; Valid CRC required for CMD0
    JSR sd_cmd
    JSR sd_deselect
    LDA r1
    CMP #&01
    BEQ cmd0_ok
    DEC tmp
    BNE cmd0_retry
    JSR print_r1
    LDX #LO(s_no_card)
    LDY #HI(s_no_card)
    JMP fail
.cmd0_ok
    JSR print_r1
    JSR OSNEWL

; ------ CMD8: SEND_IF_COND (2.7-3.6 V, check pattern AA) ------
    LDX #LO(s_cmd8)
    LDY #HI(s_cmd8)
    JSR print_str
    JSR zero_arg
    LDA #&01
    STA arg1
    LDA #&AA
    STA arg0
    LDA #8
    LDX #&87                ; Valid CRC required for CMD8
    JSR sd_cmd
    JSR print_r1
    LDA r1
    CMP #&01
    BNE cmd8_v1
    JSR read_resp4          ; R7
    JSR sd_deselect
    LDX #LO(s_r7)
    LDY #HI(s_r7)
    JSR print_str
    JSR print_resp4
    LDA resp+3
    CMP #&AA
    BNE cmd8_bad
    LDA resp+2
    AND #&0F
    CMP #&01
    BNE cmd8_bad
    LDA #1
    STA card_v2
    LDX #LO(s_v2)
    LDY #HI(s_v2)
    JSR print_str
    JMP acmd41
.cmd8_bad
    LDX #LO(s_cmd8_bad)
    LDY #HI(s_cmd8_bad)
    JMP fail
.cmd8_v1
    JSR sd_deselect
    LDX #LO(s_v1)
    LDY #HI(s_v1)
    JSR print_str

; ------ ACMD41: SD_SEND_OP_COND until the card is ready ------
.acmd41
    LDX #LO(s_acmd41)
    LDY #HI(s_acmd41)
    JSR print_str
    LDA #LO(2000)
    STA cnt_lo
    LDA #HI(2000)
    STA cnt_hi
.acmd41_loop
    JSR zero_arg
    LDA #55                 ; APP_CMD prefix
    LDX #&01
    JSR sd_cmd
    JSR sd_deselect
    JSR zero_arg
    LDA card_v2
    BEQ acmd41_no_hcs
    LDA #&40                ; HCS: host supports SDHC/SDXC
    STA arg3
.acmd41_no_hcs
    LDA #41
    LDX #&01
    JSR sd_cmd
    JSR sd_deselect
    LDA r1
    BEQ acmd41_ready
    LDA cnt_lo
    BNE acmd41_dec
    DEC cnt_hi
.acmd41_dec
    DEC cnt_lo
    LDA cnt_lo
    ORA cnt_hi
    BNE acmd41_loop
    JSR print_r1
    LDX #LO(s_timeout)
    LDY #HI(s_timeout)
    JMP fail
.acmd41_ready
    JSR print_r1
    JSR OSNEWL

; ------ CMD58: READ_OCR (capacity class) ------
    LDX #LO(s_cmd58)
    LDY #HI(s_cmd58)
    JSR print_str
    JSR zero_arg
    LDA #58
    LDX #&01
    JSR sd_cmd
    JSR print_r1
    JSR read_resp4
    JSR sd_deselect
    LDX #LO(s_ocr)
    LDY #HI(s_ocr)
    JSR print_str
    JSR print_resp4
    LDA resp+0
    AND #&40                ; CCS bit
    BEQ ocr_sdsc
    LDX #LO(s_sdhc)
    LDY #HI(s_sdhc)
    JSR print_str
    JMP read_cid
.ocr_sdsc
    LDX #LO(s_sdsc)
    LDY #HI(s_sdsc)
    JSR print_str

; ------ CMD10: SEND_CID ------
.read_cid
    LDX #LO(s_cmd10)
    LDY #HI(s_cmd10)
    JSR print_str
    JSR zero_arg
    LDA #10
    LDX #&01
    JSR sd_cmd
    JSR print_r1
    LDA r1
    BNE cid_fail
    JSR wait_token
    BCS cid_fail
    LDY #0
.cid_read
    LDA #&FF
    JSR spi_xfer
    STA cid, Y
    INY
    CPY #18                 ; 16 bytes + 2 CRC bytes
    BNE cid_read
    JSR sd_deselect
    JSR OSNEWL
    JSR print_cid
    JMP read_sector
.cid_fail
    JSR sd_deselect
    LDX #LO(s_data_fail)
    LDY #HI(s_data_fail)
    JMP fail

; ------ CMD17: READ_SINGLE_BLOCK, sector 0 ------
.read_sector
    LDX #LO(s_cmd17)
    LDY #HI(s_cmd17)
    JSR print_str
    JSR zero_arg            ; Address 0 is sector 0 for all card types
    LDA #17
    LDX #&01
    JSR sd_cmd
    JSR print_r1
    LDA r1
    BNE sector_fail
    JSR wait_token
    BCS sector_fail
    LDA #LO(SECTOR_BUF)
    STA buf_ptr
    LDA #HI(SECTOR_BUF)
    STA buf_ptr+1
    LDA #2                  ; Two 256-byte pages
    STA tmp
.sector_page
    LDY #0
.sector_byte
    LDA #&FF
    JSR spi_xfer
    STA (buf_ptr), Y
    INY
    BNE sector_byte
    INC buf_ptr+1
    DEC tmp
    BNE sector_page
    LDA #&FF                ; Discard the 16-bit CRC
    JSR spi_xfer
    LDA #&FF
    JSR spi_xfer
    JSR sd_deselect
    JSR OSNEWL
    JSR print_sector
    LDX #LO(s_done)
    LDY #HI(s_done)
    JMP print_str
.sector_fail
    JSR sd_deselect
    LDX #LO(s_data_fail)
    LDY #HI(s_data_fail)
    ; Fall through

; Print the message at X/Y and stop
.fail
    JSR OSNEWL
    JMP print_str

; ------ SD helpers ------

.zero_arg
    LDA #0
    STA arg0
    STA arg1
    STA arg2
    STA arg3
    RTS

; Send command A (0-63) with argument arg3..arg0 and CRC byte X.
; Leaves the card selected. R1 is returned in r1 (FF if no response).
; Preserves nothing.
.sd_cmd
    STA cmd_idx
    STX crc
    JSR sd_select
    LDA #&FF                ; One byte of clocks before the command
    JSR spi_xfer
    LDA cmd_idx
    ORA #&40
    JSR spi_xfer
    LDA arg3
    JSR spi_xfer
    LDA arg2
    JSR spi_xfer
    LDA arg1
    JSR spi_xfer
    LDA arg0
    JSR spi_xfer
    LDA crc
    JSR spi_xfer
    LDY #16                 ; R1 arrives within 8 bytes; allow 16
.sd_r1_wait
    LDA #&FF
    JSR spi_xfer
    BPL sd_r1_got           ; R1 always has bit 7 clear
    DEY
    BNE sd_r1_wait
.sd_r1_got
    STA r1
    RTS

; Read the 4-byte tail of an R3/R7 response into resp
.read_resp4
    LDY #0
.read_resp4_loop
    LDA #&FF
    JSR spi_xfer
    STA resp, Y
    INY
    CPY #4
    BNE read_resp4_loop
    RTS

; Wait for the data start token (FE). Carry clear on success; on failure
; carry is set and the last byte received is in tmp.
.wait_token
    LDA #LO(2000)
    STA cnt_lo
    LDA #HI(2000)
    STA cnt_hi
.wait_token_loop
    LDA #&FF
    JSR spi_xfer
    STA tmp
    CMP #&FF
    BNE wait_token_got
    LDA cnt_lo
    BNE wait_token_dec
    DEC cnt_hi
.wait_token_dec
    DEC cnt_lo
    LDA cnt_lo
    ORA cnt_hi
    BNE wait_token_loop
    SEC
    RTS
.wait_token_got
    CMP #&FE
    BEQ wait_token_ok
    SEC
    RTS
.wait_token_ok
    CLC
    RTS

; ------ VIA and SPI ------

.init_via
    LDA #%00011000          ; Disable CB1/CB2 interrupts
    STA IER
    LDA #0
    STA PCR
    STA ACR
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB
    LDA IORB                ; No device, SCK high, MOSI high
    AND #NOT_SEL
    ORA #MOSI OR SCK
    STA IORB
    RTS

.sd_select
    LDA IORB
    ORA #SCK
    AND #NOT_SEL
    ORA #DEV_SD
    STA IORB
    RTS

; Deselect, then clock one byte so the card releases DO (MISO)
.sd_deselect
    LDA IORB
    AND #NOT_SEL
    STA IORB
    LDA #&FF
    JMP spi_xfer

; SPI transfer with SCK idling high. Send A, return received byte in A.
; Preserves Y.
.spi_xfer
    STA spi_temp
    LDA SR
    LDX #8
.spi_bit
    LDA IORB
    AND #NOT_SCK AND NOT_MOSI
    ASL spi_temp
    BCC spi_mosi_low
    ORA #MOSI
.spi_mosi_low
    STA IORB                ; Falling edge, MOSI valid
    ORA #SCK
    STA IORB                ; Rising edge: both ends sample
    DEX
    BNE spi_bit
    LDA SR
    RTS

; ------ Display ------

.print_r1
    LDX #LO(s_r1)
    LDY #HI(s_r1)
    JSR print_str
    LDA r1
    JMP print_hex_byte

.print_resp4
    LDY #0
.print_resp4_loop
    LDA resp, Y
    JSR print_hex_byte
    INY
    CPY #4
    BNE print_resp4_loop
    RTS

; CID fields: MID [0], OID [1-2], PNM [3-7], PRV [8], PSN [9-12],
; MDT year = cid[13] bits 3-0 : cid[14] bits 7-4 (offset from 2000),
; month = cid[14] bits 3-0
.print_cid
    LDX #LO(s_mid)
    LDY #HI(s_mid)
    JSR print_str
    LDA cid+0
    JSR print_hex_byte
    LDX #LO(s_oid)
    LDY #HI(s_oid)
    JSR print_str
    LDA cid+1 : JSR print_printable
    LDA cid+2 : JSR print_printable
    LDX #LO(s_pnm)
    LDY #HI(s_pnm)
    JSR print_str
    LDY #3
.print_pnm
    LDA cid, Y
    JSR print_printable
    INY
    CPY #8
    BNE print_pnm
    JSR OSNEWL
    LDX #LO(s_prv)
    LDY #HI(s_prv)
    JSR print_str
    LDA cid+8
    LSR A : LSR A : LSR A : LSR A
    JSR print_dec
    LDA #'.' : JSR OSWRCH
    LDA cid+8
    AND #&0F
    JSR print_dec
    LDX #LO(s_psn)
    LDY #HI(s_psn)
    JSR print_str
    LDY #9
.print_psn
    LDA cid, Y
    JSR print_hex_byte
    INY
    CPY #13
    BNE print_psn
    LDX #LO(s_mdt)
    LDY #HI(s_mdt)
    JSR print_str
    ; Year offset = (cid13 & 0F) << 4 | cid14 >> 4
    LDA cid+13
    ASL A : ASL A : ASL A : ASL A
    STA tmp
    LDA cid+14
    LSR A : LSR A : LSR A : LSR A
    ORA tmp
    CMP #100
    BCS mdt_21
    PHA
    LDA #'2' : JSR OSWRCH
    LDA #'0' : JSR OSWRCH
    PLA
    JMP mdt_year
.mdt_21
    SEC
    SBC #100
    PHA
    LDA #'2' : JSR OSWRCH
    LDA #'1' : JSR OSWRCH
    PLA
.mdt_year
    JSR print_dec2
    LDA #'/' : JSR OSWRCH
    LDA cid+14
    AND #&0F
    JSR print_dec2
    JMP OSNEWL

.print_sector
    LDX #LO(s_first16)
    LDY #HI(s_first16)
    JSR print_str
    LDY #0
.print_first16
    LDA SECTOR_BUF, Y
    JSR print_hex_byte
    LDA #' ' : JSR OSWRCH
    INY
    CPY #16
    BNE print_first16
    JSR OSNEWL
    LDX #LO(s_sig)
    LDY #HI(s_sig)
    JSR print_str
    LDA SECTOR_BUF+510
    JSR print_hex_byte
    LDA #' ' : JSR OSWRCH
    LDA SECTOR_BUF+511
    JSR print_hex_byte
    LDA SECTOR_BUF+510
    CMP #&55
    BNE sig_bad
    LDA SECTOR_BUF+511
    CMP #&AA
    BNE sig_bad
    LDX #LO(s_sig_ok)
    LDY #HI(s_sig_ok)
    JSR print_str
    JMP print_part
.sig_bad
    LDX #LO(s_sig_bad)
    LDY #HI(s_sig_bad)
    JSR print_str
.print_part
    ; Partition 1 entry at 1BEh: type at +4, start LBA (little-endian) at +8
    LDX #LO(s_part)
    LDY #HI(s_part)
    JSR print_str
    LDA SECTOR_BUF+&1C2
    JSR print_hex_byte
    LDX #LO(s_lba)
    LDY #HI(s_lba)
    JSR print_str
    LDY #3
.print_lba
    LDA SECTOR_BUF+&1C6, Y
    JSR print_hex_byte
    DEY
    BPL print_lba
    JMP OSNEWL

; Print A as a character, or '.' if not printable
.print_printable
    CMP #32
    BCC not_printable
    CMP #127
    BCC printable
.not_printable
    LDA #'.'
.printable
    JMP OSWRCH

; Print A (0-99) as exactly two decimal digits. Clobbers X.
.print_dec2
    LDX #0
.print_dec2_loop
    CMP #10
    BCC print_dec2_done
    SBC #10
    INX
    BNE print_dec2_loop
.print_dec2_done
    PHA
    TXA
    ORA #'0'
    JSR OSWRCH
    PLA
    ORA #'0'
    JMP OSWRCH

; Print A (0-99) in decimal without a leading zero. Clobbers X.
.print_dec
    CMP #10
    BCS print_dec2
    ORA #'0'
    JMP OSWRCH

; Print the zero-terminated string at X (low), Y (high). Clobbers Y.
.print_str
    STX ptr
    STY ptr+1
    LDY #0
.print_str_loop
    LDA (ptr), Y
    BEQ print_str_done
    JSR OSWRCH
    INY
    BNE print_str_loop
.print_str_done
    RTS

; Print A as two hex digits
.print_hex_byte
    PHA
    LSR A
    LSR A
    LSR A
    LSR A
    JSR print_hex_nybble
    PLA
    AND #&0F
.print_hex_nybble
    CMP #10
    BCC hex_digit
    ADC #6
.hex_digit
    ADC #&30
    JMP OSWRCH

; ------ Data ------

.s_title
    EQUS "SPItFIRE SD Card Test (J4, Y2)", 13, 10, 10, 0
.s_cmd0
    EQUS "CMD0  GO_IDLE   ", 0
.s_cmd8
    EQUS "CMD8  IF_COND   ", 0
.s_acmd41
    EQUS "ACMD41 OP_COND  ", 0
.s_cmd58
    EQUS "CMD58 READ_OCR  ", 0
.s_cmd10
    EQUS "CMD10 SEND_CID  ", 0
.s_cmd17
    EQUS "CMD17 SECTOR 0  ", 0
.s_r1
    EQUS "R1=", 0
.s_r7
    EQUS " R7=", 0
.s_ocr
    EQUS " OCR=", 0
.s_v2
    EQUS " SD v2+", 13, 10, 0
.s_v1
    EQUS " (SD v1 or MMC)", 13, 10, 0
.s_sdhc
    EQUS " SDHC/SDXC", 13, 10, 0
.s_sdsc
    EQUS " SDSC", 13, 10, 0
.s_mid
    EQUS "  MID ", 0
.s_oid
    EQUS "  OID ", 0
.s_pnm
    EQUS "  Name ", 0
.s_prv
    EQUS "  Rev ", 0
.s_psn
    EQUS "  Serial ", 0
.s_mdt
    EQUS "  Made ", 0
.s_first16
    EQUS "  ", 0
.s_sig
    EQUS "  Signature ", 0
.s_sig_ok
    EQUS " OK", 13, 10, 0
.s_sig_bad
    EQUS " (no MBR/boot signature)", 13, 10, 0
.s_part
    EQUS "  Partition 1 type ", 0
.s_lba
    EQUS " start LBA ", 0
.s_no_card
    EQUS "No response: no card, or DO not reaching MISO", 13, 10, 0
.s_cmd8_bad
    EQUS "CMD8 echo mismatch: unusable card", 13, 10, 0
.s_timeout
    EQUS "Card did not become ready", 13, 10, 0
.s_data_fail
    EQUS "Data read failed", 13, 10, 0
.s_done
    EQUS 13, 10, "Done", 13, 10, 0

.resp
    SKIP 4
.cid
    SKIP 18

.end

SAVE "SPISD", start, end
