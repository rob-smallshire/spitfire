; Master Compact clock call probe
; Shows what OSWORD &0E (read clock) returns on this machine, and who
; answers it: the MOS itself, or a sideways ROM such as ANFS.
;
; Three views:
;   1. All ROMs   - what *TIME and TIME$ currently see
;   2. MOS only   - every ROM hidden, so only MOS 5.10 can answer;
;                   also converts some fixed BCD blocks with subcall 2
;   3. Each ROM on its own, listed if its subcall 0 answer differs
;                   from the MOS-only answer
; and finally the ANFS file server subcalls 3 and 4 with all ROMs.
; The output is longer than a MODE 7 screen, so it runs in paged mode:
; press SHIFT to continue.
;
; ROMs are hidden by zeroing their entries in the MOS ROM type table
; (&2A1-&2B0), which the MOS checks before offering a ROM service calls.
; The table is restored straight after each hidden call, before
; anything is printed. Nothing here raises errors while ROMs are hidden.
;
; Every block is pre-filled with '#' (&23) so bytes nobody wrote show as
; '#'. In strings, CR shows as '~' and other control codes as '.'.

ORG &1900

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7
OSWORD = &FFF1
OSBYTE = &FFF4
OSRDRM = &FFB9

ROMTYPE  = &02A1            ; MOS ROM type table, one byte per slot
ROMPTR   = &F6              ; OSRDRM address (2 bytes)

FILL     = '#'
BLKSIZE  = 32               ; OSWORD &0E blocks are at most 25 bytes

; Zero page
ptr      = &70              ; 2 bytes
blk      = &72              ; 2 bytes, current OSWORD block
slot     = &74
cnt      = &75
tmp      = &76
save_x   = &77
save_y   = &78

.start
    JSR print_inline
    EQUS 14, "OSWORD &0E probe", 13, 10, 0   ; VDU 14: paged mode

    ; MOS version: OSBYTE 0 with X=1 returns it in X
    LDA #0
    LDX #1
    JSR OSBYTE
    TXA
    PHA
    JSR print_inline
    EQUS "OSBYTE 0: ", 0
    PLA
    JSR print_hex_byte
    JSR OSNEWL

    LDX #15
.save_types
    LDA ROMTYPE, X
    STA saved_types, X
    DEX
    BPL save_types

; ------ 1. All ROMs ------
    LDA #LO(blk_all0)
    LDX #HI(blk_all0)
    LDY #0
    JSR read_clock
    LDA #LO(blk_all1)
    LDX #HI(blk_all1)
    LDY #1
    JSR read_clock

    JSR print_inline
    EQUS 13, 10, "All ROMs:", 13, 10, 0
    LDX #LO(blk_all0)
    LDY #HI(blk_all0)
    JSR print_sub0
    LDX #LO(blk_all1)
    LDY #HI(blk_all1)
    JSR print_sub1

; ------ 2. MOS only ------
    JSR hide_all
    LDA #LO(blk_mos0)
    LDX #HI(blk_mos0)
    LDY #0
    JSR read_clock
    LDA #LO(blk_mos1)
    LDX #HI(blk_mos1)
    LDY #1
    JSR read_clock
    LDA #LO(blk_conv_a)
    LDX #HI(blk_conv_a)
    LDY #LO(bcd_a - bcd_tables)
    JSR convert_bcd
    LDA #LO(blk_conv_b)
    LDX #HI(blk_conv_b)
    LDY #LO(bcd_b - bcd_tables)
    JSR convert_bcd
    LDA #LO(blk_conv_c)
    LDX #HI(blk_conv_c)
    LDY #LO(bcd_c - bcd_tables)
    JSR convert_bcd
    JSR restore_all

    JSR print_inline
    EQUS 13, 10, "MOS only:", 13, 10, 0
    LDX #LO(blk_mos0)
    LDY #HI(blk_mos0)
    JSR print_sub0
    LDX #LO(blk_mos1)
    LDY #HI(blk_mos1)
    JSR print_sub1
    JSR print_inline
    EQUS "2: 26 10 07 04 12 34 56", 13, 10, 0
    LDX #LO(blk_conv_a)
    LDY #HI(blk_conv_a)
    JSR print_string_block
    JSR print_inline
    EQUS "2: 99 12 31 06 23 59 59", 13, 10, 0
    LDX #LO(blk_conv_b)
    LDY #HI(blk_conv_b)
    JSR print_string_block
    JSR print_inline
    EQUS "2: 26 10 07 00 12 34 56", 13, 10, 0
    LDX #LO(blk_conv_c)
    LDY #HI(blk_conv_c)
    JSR print_string_block

; ------ 3. Each ROM on its own ------
    JSR print_inline
    EQUS 13, 10, "ROMs answering subcall 0:", 13, 10, 0
    LDA #0
    STA cnt
    LDA #15
    STA slot
.slot_loop
    LDX slot
    LDA saved_types, X
    BEQ next_slot           ; Empty slot
    JSR hide_all
    LDX slot
    LDA saved_types, X
    STA ROMTYPE, X          ; Reveal just this ROM
    LDA #LO(blk_rom)
    LDX #HI(blk_rom)
    LDY #0
    JSR read_clock
    JSR restore_all

    LDY #24                 ; Same answer as the MOS on its own?
.compare
    LDA blk_rom, Y
    CMP blk_mos0, Y
    BNE answered
    DEY
    BPL compare
    BMI next_slot           ; Always

.answered
    INC cnt
    LDA slot
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    JSR print_rom_title
    JSR OSNEWL
    LDX #LO(blk_rom)
    LDY #HI(blk_rom)
    JSR print_string_block

.next_slot
    DEC slot
    BPL slot_loop

    LDA cnt
    BNE anfs_calls
    JSR print_inline
    EQUS "   (none)", 13, 10, 0

; ------ 4. ANFS file server time, all ROMs ------
.anfs_calls
    LDA #LO(blk_anfs3)
    LDX #HI(blk_anfs3)
    LDY #3
    JSR read_clock
    LDA #LO(blk_anfs4)
    LDX #HI(blk_anfs4)
    LDY #4
    JSR read_clock
    JSR print_inline
    EQUS 13, 10, "All ROMs, subcalls 3, 4:", 13, 10, "3:", 13, 10, 0
    LDX #LO(blk_anfs3)
    LDY #HI(blk_anfs3)
    JSR print_string_block
    JSR print_inline
    EQUS "4: ", 0
    LDX #LO(blk_anfs4)
    LDY #HI(blk_anfs4)
    JSR print_hex8
    LDA #15                 ; VDU 15: paged mode off
    JMP OSWRCH

; ------ OSWORD &0E calls ------

; Fill the block at XA with FILL, set subcall Y, call OSWORD &0E
.read_clock
    STA blk
    STX blk+1
    TYA
    PHA
    JSR fill_block
    PLA
    LDY #0
    STA (blk), Y
.call_osword
    LDA #&0E
    LDX blk
    LDY blk+1
    JMP OSWORD

; Fill the block at XA with FILL, copy the 7 BCD bytes at
; bcd_tables+Y to block+1, and convert them with subcall 2
.convert_bcd
    STA blk
    STX blk+1
    STY tmp
    JSR fill_block
    LDA #2
    LDY #0
    STA (blk), Y
    LDX tmp
    LDY #1
.copy_bcd
    LDA bcd_tables, X
    STA (blk), Y
    INX
    INY
    CPY #8
    BNE copy_bcd
    BEQ call_osword         ; Always

.fill_block
    LDA #FILL
    LDY #BLKSIZE - 1
.fill_loop
    STA (blk), Y
    DEY
    BPL fill_loop
    RTS

; ------ ROM type table ------

.hide_all
    LDA #0
    LDX #15
.hide_loop
    STA ROMTYPE, X
    DEX
    BPL hide_loop
    RTS

.restore_all
    LDX #15
.restore_loop
    LDA saved_types, X
    STA ROMTYPE, X
    DEX
    BPL restore_loop
    RTS

; ------ Printing ------

; Subcall 0 result: the string
.print_sub0
    STX save_x
    STY save_y
    JSR print_inline
    EQUS "0:", 13, 10, 0
    LDX save_x
    LDY save_y
    ; Fall through

; Print 25 bytes at YX as characters, indented
.print_string_block
    STX save_x
    STY save_y
    JSR print_inline        ; Uses ptr, so set it afterwards
    EQUS "   ", 0
    LDA save_x
    STA ptr
    LDA save_y
    STA ptr+1
    LDY #0
.psb_loop
    LDA (ptr), Y
    CMP #13
    BNE psb_not_cr
    LDA #'~'
    BNE psb_print           ; Always
.psb_not_cr
    CMP #' '
    BCC psb_dot
    CMP #127
    BCC psb_print
.psb_dot
    LDA #'.'
.psb_print
    JSR OSWRCH
    INY
    CPY #25
    BNE psb_loop
    JMP OSNEWL

; Subcall 1 result: 7 BCD bytes plus the next byte, in hex
.print_sub1
    STX save_x
    STY save_y
    JSR print_inline
    EQUS "1: ", 0
    LDX save_x
    LDY save_y
    ; Fall through

; Print 8 bytes at YX in hex
.print_hex8
    STX ptr
    STY ptr+1
    LDY #0
.ph8_loop
    LDA (ptr), Y
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    INY
    CPY #8
    BNE ph8_loop
    JMP OSNEWL

; Print the title of ROM slot, read with OSRDRM (at most 20 chars)
.print_rom_title
    LDA #&09
    STA ROMPTR
    LDA #&80
    STA ROMPTR+1
    LDA #20
    STA tmp
.prt_loop
    LDY slot
    JSR OSRDRM
    CMP #' '
    BCC prt_done            ; Title ends with a zero byte
    CMP #127
    BCS prt_done
    JSR OSWRCH
    INC ROMPTR
    DEC tmp
    BNE prt_loop
.prt_done
    RTS

; Print the zero-terminated string following the JSR
.print_inline
    PLA
    STA ptr
    PLA
    STA ptr+1
    LDY #0
.pi_loop
    INC ptr
    BNE pi_no_carry
    INC ptr+1
.pi_no_carry
    LDA (ptr), Y
    BEQ pi_done
    JSR OSWRCH
    JMP pi_loop
.pi_done
    LDA ptr+1
    PHA
    LDA ptr
    PHA
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

; BCD blocks for subcall 2: year, month, date, day of week (1 = Sunday),
; hours, minutes, seconds
.bcd_tables
.bcd_a
    EQUB &26, &10, &07, &04, &12, &34, &56   ; Wed 07 Oct 2026: century?
.bcd_b
    EQUB &99, &12, &31, &06, &23, &59, &59   ; Fri 31 Dec 1999
.bcd_c
    EQUB &26, &10, &07, &00, &12, &34, &56   ; Day of week unknown

.end

saved_types = end
blk_all0    = saved_types + 16
blk_all1    = blk_all0 + BLKSIZE
blk_mos0    = blk_all1 + BLKSIZE
blk_mos1    = blk_mos0 + BLKSIZE
blk_conv_a  = blk_mos1 + BLKSIZE
blk_conv_b  = blk_conv_a + BLKSIZE
blk_conv_c  = blk_conv_b + BLKSIZE
blk_rom     = blk_conv_c + BLKSIZE
blk_anfs3   = blk_rom + BLKSIZE
blk_anfs4   = blk_anfs3 + BLKSIZE

SAVE "TIMEPROBE", start, end
