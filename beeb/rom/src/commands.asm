; *SPITFIRE commands, *HELP, *STATUS and OSWORD &3F
; See "The *SPITFIRE Command Namespace" and "Module: Joystick" in
; docs/rom-design.md.
;
;   *SPITFIRE                   Version and modules
;   *SPITFIRE JOYSTICK          Joystick settings
;   *SPITFIRE JOYSTICK ON|OFF   Hand the MOS's joystick handling to the
;                               ROM, or give it back
;   *SPITFIRE JOYSTICK PORT A|B <type>
;                               Set and save a port's type: NONE, SINGLE,
;                               DUAL, 3BS, 3BT, 14B, BITSTIK or QUINKEY
;   *SPITFIRE ADVAL [ALL]       The ADVAL channels SPItFIRE answers, with
;                               their values; ALL lists unused ones too
;   *HELP                       Title, version, the SPITFIRE topic and
;                               the current settings (as the network
;                               filing systems show their station)
;   *HELP SPITFIRE [JOYSTICK]   The commands, then the settings
;   *STATUS [SPITFIRE]          The settings, after the MOS's
;   OSWORD &3F                  Identify SPItFIRE and describe the
;                               joysticks (for software)
;
; The port types live in the AVR's EEPROM. The AVR only writes it when a
; value changes, and only PORT changes them.
;
; Keywords match in either case and must be followed by a space or the
; end of the line. Uses &A8-&AF, which are free during *commands; the
; OSWORD handler saves and restores them.

cmd_start = ws + 0          ; Start of the word being matched
port      = ws + 0          ; After parsing: the port being shown
dtype     = ws + 0          ; ADVAL rows: the slot's type
lead      = ws + 0          ; print_dec16: a digit has been printed
choice    = ws + 1          ; match_choice: index of the word matched
row       = ws + 1          ; ADVAL: row of adval_rows
choice_x  = ws + 2          ; match_choice: offset of the word tried
indent    = ws + 2          ; After parsing: non-zero to indent
all       = ws + 2          ; ADVAL: non-zero to show unused channels
config    = ws + 3          ; The AVR's configuration byte
dport     = ws + 4          ; ADVAL rows: the slot's port (shares wsp)
dj        = ws + 5          ; ADVAL rows: joystick within the port
value     = ws + 4          ; print_dec16: 2 bytes (shares wsp)
str_ptr   = ws + 6          ; 2 bytes: print_inline's pointer

T_14B     = 5
T_BITSTIK = 6
T_QUINKEY = 7
T_BITSTIK_AUX = 8           ; OSWORD &3F: a Bitstik's second slot

; Service &04: unrecognised command. Y = offset of the command at
; (CMD_PTR). Return C=0 if claimed (the command has run), C=1 to pass.
.cmd_star
    LDX #word_spitfire - words
    JSR match_word
    BCS cmd_pass
    JSR at_end
    BEQ cmd_summary
    LDX #word_adval - words
    JSR match_word
    BCS cmd_star_joystick
    JMP cmd_adval
.cmd_star_joystick
    LDX #word_joystick - words
    JSR match_word
    BCS cmd_syntax
    JSR at_end
    BEQ cmd_joystick_status
    LDX #word_on - words    ; ON, OFF
    JSR match_choice
    BCC cmd_joystick_on_off
    LDX #word_port - words
    JSR match_word
    BCC cmd_joystick_port
    ; Fall through
.cmd_syntax
    LDX #error_syntax - errors
    JMP cmd_error

.cmd_pass
    SEC
    RTS

; *SPITFIRE: version and modules
.cmd_summary
    JSR print_title
    JSR print_inline
    EQUS "Modules: RTC JOYSTICK", 13, 0
    JSR have_ws
    BEQ cmd_done
    JSR print_reminder
.cmd_done
    CLC
    RTS

; *SPITFIRE JOYSTICK: the settings
.cmd_joystick_status
    LDA #0
    STA indent
    JSR print_joystick
    CLC
    RTS

; *SPITFIRE JOYSTICK ON|OFF: set or clear bit 7 of the MOS's joystick
; byte (*FX190,128,127 or *FX190,0,127), keeping the rest
.cmd_joystick_on_off
    JSR at_end
    BNE cmd_syntax
    LDX #&80                ; ON
    LDA choice
    BEQ cmd_joystick_set
    LDX #&00                ; OFF
.cmd_joystick_set
    LDA #&BE
    LDY #&7F
    JSR OSBYTE
    CLC
    RTS

; *SPITFIRE JOYSTICK PORT A|B <type>
.cmd_joystick_port
    JSR match_port
    BCS cmd_syntax
    STA config              ; Keep the port; match_word uses cmd_start
    LDX #word_none - words  ; The types, in the AVR's order
    JSR match_choice
    BCS cmd_syntax
    JSR at_end
    BNE cmd_syntax
    LDA config
    ASL A
    ASL A
    ASL A
    ORA choice
    ORA #CMD_CFG_PORT       ; &D0 + 8 * port + type
    ; Send configuration command A to the AVR, which applies it and
    ; saves it in EEPROM. The AVR echoes the command.
    STA config
    JSR joy_command
    CMP config
    BNE cmd_not_responding
    CLC
    RTS

.cmd_not_responding
    LDX #error_avr - errors
    ; Fall through

; Raise the error at errors+X
.cmd_error
    LDY #0
.cmd_error_copy
    LDA errors, X
    STA &0100, Y
    INX
    INY
    CMP #0
    BNE cmd_error_copy
    CPY #3                  ; Past the BRK, number and first zero?
    BCC cmd_error_copy
    JMP &0100

; ------ *SPITFIRE ADVAL [ALL] ------

.cmd_adval_syntax
    JMP cmd_syntax
.cmd_adval
    LDA #0
    STA all
    JSR at_end
    BEQ cmd_adval_go
    LDX #word_all - words
    JSR match_word
    BCS cmd_adval_syntax
    JSR at_end
    BNE cmd_adval_syntax
    DEC all
.cmd_adval_go
    JSR have_ws
    BEQ cmd_adval_ws
    JSR print_reminder
    CLC
    RTS
.cmd_adval_ws
    JSR read_config
    BCC cmd_adval_rows
    JMP cmd_not_responding
.cmd_adval_rows
    JSR print_inline
    EQUS "Ch Use               Port Value", 13, 0
    LDA #0
    STA row
.cmd_adval_row
    JSR adval_row
    LDX row
    LDA adval_rows, X
    CMP #4                  ; After ADVAL(4): the mouse channels
    BNE cmd_adval_next
    LDA all
    BEQ cmd_adval_next
    JSR print_inline
    EQUS "5-9 Passed on (mouse)", 13, 0
.cmd_adval_next
    INC row
    LDA row
    CMP #adval_rows_end - adval_rows
    BNE cmd_adval_row
    CLC
    RTS

; One row of the table, for adval_rows+row. Skipped if nothing is
; allocated to the channel, unless `all` is set.
.adval_row
    LDX row
    LDA adval_slots, X
    JSR slot_info           ; A = type or &FF, X = port, Y = j
    STA dtype
    STX dport
    STY dj
    CMP #&FF
    BEQ adval_row_unused
    LDX row
    LDA adval_kinds, X
    CMP #K_KEYS
    BNE adval_row_print
    LDA dtype
    CMP #T_14B
    BEQ adval_row_print
.adval_row_unused
    LDA #&FF
    STA dtype
    LDA all
    BNE adval_row_print
    RTS

.adval_row_print
    LDX row                 ; The channel, right-aligned in 2
    LDA adval_rows, X
    CMP #10
    BCS adval_row_ch
    PHA
    LDA #' '
    JSR OSASCI
    PLA
.adval_row_ch
    JSR print_dec8
    LDA #' '
    JSR OSASCI
    LDA dtype
    BPL adval_row_use
    LDA #'-'                ; Unused
    JSR OSASCI
    LDX #21
    JSR tab_to
    LDA #'-'
    JSR OSASCI
    JMP adval_row_value
.adval_row_use
    JSR print_use
    LDX #21
    JSR tab_to
    LDA dport
    CLC
    ADC #'A'
    JSR OSASCI
.adval_row_value
    LDX #26
    JSR tab_to
    LDX row
    LDA adval_rows, X
    TAX
    LDA #&80                ; OSBYTE &80, through our BYTEV hook
    LDY #0
    JSR OSBYTE              ; X = low byte, Y = high byte
    STX value
    STY value+1
    LDX row
    LDA adval_kinds, X
    CMP #K_SWITCHES
    BEQ adval_row_byte
    CMP #K_KEYS
    BEQ adval_row_word
    CMP #K_SWBYTES
    BEQ adval_row_word
    JSR print_dec16
    JMP OSNEWL
.adval_row_byte
    LDA #'&'
    JSR OSASCI
    LDA value
    JSR print_hex
    JMP OSNEWL
.adval_row_word
    LDA #'&'
    JSR OSASCI
    LDA value+1
    JSR print_hex
    LDA value
    JSR print_hex
    JMP OSNEWL

; Print what the channel at adval_rows+row carries, for a slot of type
; dtype; dj = joystick within its port
.print_use
    LDX row
    LDA adval_kinds, X
    CMP #K_SWITCHES
    BEQ print_use_fire
    CMP #K_KEYS
    BEQ print_use_keys
    CMP #K_SWBYTES
    BEQ print_use_switches
    STA dport               ; K_X or K_Y (0 or 1); port is printed later
    LDA dtype               ; so keep the axis in its place for now
    CMP #T_BITSTIK
    BEQ print_use_bitstik
    CMP #T_QUINKEY
    BEQ print_use_quinkey
    JSR print_joystick_n
    LDA #' '
    JSR OSASCI
    LDA dport
    CLC
    ADC #'X'
    JSR OSASCI
    JMP print_use_port
.print_use_bitstik
    LDA dj                  ; Index: 2j + axis
    ASL A
    ORA dport
    TAX
    LDA bitstik_uses, X
    TAX
.print_use_bitstik_char
    LDA bitstik_x, X
    BEQ print_use_port
    JSR OSASCI
    INX
    BNE print_use_bitstik_char
.print_use_quinkey
    JSR print_inline
    EQUS "Quinkey ", 0
    LDA dj
    ASL A
    ORA dport
    CLC
    ADC #1
    JSR print_dec8
    ; Fall through
.print_use_port             ; Recover the port for the Port column
    LDX row
    LDA adval_slots, X
    JSR slot_info
    STX dport
    RTS
.print_use_keys
    JSR print_joystick_n
    JSR print_inline
    EQUS " keypad", 0
    RTS
.print_use_switches
    JSR print_inline
    EQUS "Switches ", 0
    JMP print_use_pair
.print_use_fire
    JSR print_inline
    EQUS "Fire ", 0
.print_use_pair             ; The pair's joysticks: "1, 2" or "1"
    LDX row
    LDA adval_slots, X
    PHA
    CLC
    ADC #1
    JSR print_dec8
    PLA
    CLC
    ADC #1                  ; The pair's second slot
    JSR slot_info
    CMP #&FF
    BEQ print_use_fire_done
    JSR print_inline
    EQUS ", ", 0
    LDX row
    LDA adval_slots, X
    CLC
    ADC #2
    JSR print_dec8
.print_use_fire_done
    RTS

; "Joystick n" for the slot of adval_rows+row
.print_joystick_n
    JSR print_inline
    EQUS "Joystick ", 0
    LDX row
    LDA adval_slots, X
    CLC
    ADC #1
    JMP print_dec8

; Pad with spaces to column X
.tab_to
    TXA
    PHA
    LDA #&86                ; Read the cursor position: X = column
    JSR OSBYTE
    PLA
    STA dj                  ; The target (dj is free by now)
.tab_to_loop
    CPX dj
    BCS tab_to_done
    LDA #' '
    JSR OSASCI
    INX
    BNE tab_to_loop
.tab_to_done
    RTS

; ------ Allocation ------

; The joystick in slot A (0-3), from the configuration in `config`:
; A = its port's type and X = the port (0 or 1), Y = which of the port's
; joysticks it is (0 or 1); or A = &FF if nothing is allocated to it.
.slot_info
    TAY
    LDA config
    AND #7
    TAX                     ; Port A's type
    TYA
    CMP joysticks_of, X
    BCS slot_info_b
    TXA
    LDX #0
    RTS
.slot_info_b
    SBC joysticks_of, X     ; C=1: the slot within Port B
    TAY
    LDA config
    LSR A
    LSR A
    LSR A
    AND #7
    TAX                     ; Port B's type
    TYA
    CMP joysticks_of, X
    BCS slot_info_none
    TXA
    LDX #1
    RTS
.slot_info_none
    LDA #&FF
    RTS

; The first slot of port `port`: 0 for Port A, after Port A's for B
.first_slot
    LDA port
    BEQ first_slot_done
    LDA config
    AND #7
    TAX
    LDA joysticks_of, X
.first_slot_done
    RTS

; Read the AVR's configuration into `config`. C=0 if it answered.
.read_config
    LDA #CMD_JOY_CONFIG
    JSR joy_command
    STA config
    AND #&C0
    CMP #CONFIG_VALID
    BEQ read_config_ok
    SEC
    RTS
.read_config_ok
    CLC
    RTS

; Z=1 if this ROM has its workspace. Corrupts A and X.
.have_ws
    LDX &F4
    JSR joy_find_ws
    LDA wsp+1
    BEQ have_ws_no
    LDA #0
    RTS
.have_ws_no
    LDA #1
    RTS

.print_reminder
    JSR print_indent
    JSR print_inline
    EQUS "Press Ctrl-Break to start SPItFIRE", 13, 0
    RTS

; ------ Settings ------

; Print the current settings, indented, for *HELP
.print_settings
    LDA #1
    STA indent
    ; Fall through

; Print the joystick settings, indented if `indent` is non-zero:
;   Joystick on
;   Port A: Standard dual joystick
;           Joysticks 1, 2
;   Port B: No joystick
; "on" or "off" is bit 7 of the MOS's joystick byte, the rest is the
; AVR's saved configuration.
.print_joystick
    JSR have_ws
    BEQ print_joystick_ws
    JMP print_reminder
.print_joystick_ws
    JSR print_indent
    JSR print_inline
    EQUS "Joystick o", 0
    JSR joystick_on
    BPL print_joystick_off
    JSR print_inline
    EQUS "n", 13, 0
    JMP print_joystick_config
.print_joystick_off
    JSR print_inline
    EQUS "ff", 13, 0
.print_joystick_config
    JSR read_config
    BCC print_joystick_ports
    JSR print_indent
    JSR print_inline
    EQUS "SPItFIRE not responding", 13, 0
    RTS
.print_joystick_ports
    LDA #0
    STA port
    JSR print_port
    INC port
    ; Fall through

; Print port `port`'s type and, on the next line, its allocation
.print_port
    JSR print_indent
    JSR print_inline
    EQUS "Port ", 0
    LDA port
    CLC
    ADC #'A'
    JSR OSASCI
    JSR print_inline
    EQUS ": ", 0
    JSR port_type
    PHA
    TAX
    LDA type_names, X
    TAX
.print_port_name
    LDA type_name_none, X
    BEQ print_port_named
    JSR OSASCI
    INX
    BNE print_port_name
.print_port_named
    JSR OSNEWL
    PLA
    TAX
    LDA joysticks_of, X
    BNE print_port_alloc
    RTS                     ; None: nothing allocated
.print_port_alloc
    JSR print_indent
    JSR print_inline
    EQUS "        ", 0
    CPX #T_BITSTIK
    BCS print_port_channels
    LDA joysticks_of, X
    CMP #2
    PHP
    JSR print_inline
    EQUS "Joystick", 0
    PLP
    BCC print_port_one
    LDA #'s'
    JSR OSASCI
.print_port_one
    LDA #' '
    JSR OSASCI
    JSR first_slot
    CLC
    ADC #1
    JSR print_dec8
    JSR port_type
    TAX
    LDA joysticks_of, X
    CMP #2
    BCC print_port_end
    JSR print_inline
    EQUS ", ", 0
    JSR first_slot
    CLC
    ADC #2
    JSR print_dec8
    JMP print_port_end
.print_port_channels        ; A Bitstik or Quinkeys: their channels
    JSR print_inline
    EQUS "Channels ", 0
    JSR first_slot
    TAX
    LDA slot_channels, X
    PHA
    JSR print_dec8
    JSR print_inline
    EQUS ", ", 0
    PLA
    PHA
    CLC
    ADC #1
    JSR print_dec8
    JSR print_inline
    EQUS ", ", 0
    JSR first_slot
    TAX
    LDA slot_channels + 1, X
    PHA
    JSR print_dec8
    JSR print_inline
    EQUS ", ", 0
    PLA
    CLC
    ADC #1
    JSR print_dec8
    PLA
.print_port_end
    JMP OSNEWL

; A = the type of port `port`
.port_type
    LDA config
    LDX port
    BEQ port_type_a
    LSR A
    LSR A
    LSR A
.port_type_a
    AND #7
    RTS

; N=1 if the MOS's joystick byte has bit 7 set (SPItFIRE has the
; joystick). Corrupts A, X and Y.
.joystick_on
    LDA #&BE                ; Read the joystick byte
    LDX #0
    LDY #&FF
    JSR OSBYTE
    TXA
    RTS

.print_indent
    LDA indent
    BEQ print_indent_done
    JSR print_inline
    EQUS "  ", 0
.print_indent_done
.cmd_help_done
    RTS

; ------ *HELP ------

; Service &09: *HELP. Y = offset of the argument at (CMD_PTR). Never
; claimed, so other ROMs see it too.
.cmd_help
    JSR at_end
    BNE cmd_help_topic
    JSR print_title
    JSR print_inline
    EQUS "  SPITFIRE", 13, 0
    JMP print_settings
.cmd_help_topic
    LDX #word_spitfire - words
    JSR match_word
    BCS cmd_help_done
    JSR print_title
    JSR at_end
    BEQ cmd_help_all
    LDX #word_joystick - words
    JSR match_word
    BCS cmd_help_done
    JMP help_joystick
.cmd_help_all
    JSR print_inline
    EQUS "  SPITFIRE", 13
    EQUS "  SPITFIRE ADVAL [ALL]", 13, 0
.help_joystick
    JSR print_inline
    EQUS "  SPITFIRE JOYSTICK [ON|OFF]", 13
    EQUS "  SPITFIRE JOYSTICK PORT A|B <type>", 13
    EQUS "    <type>: NONE SINGLE DUAL 3BS 3BT", 13
    EQUS "            14B BITSTIK QUINKEY", 13, 0
    JMP print_settings

; ------ *STATUS ------

; Service &29: *STATUS. Y = offset of the argument at (CMD_PTR). On its
; own, print the settings after the MOS's and leave the call for other
; ROMs (C=1); with SPITFIRE, print them and claim it (C=0).
.cmd_status
    JSR at_end
    BEQ cmd_status_print
    LDX #word_spitfire - words
    JSR match_word
    BCS cmd_status_pass
    JSR at_end
    BNE cmd_status_pass
    JSR cmd_status_print
    CLC
    RTS
.cmd_status_print
    LDA #0
    STA indent
    JSR print_inline
    EQUS "SPItFIRE: ", 0
    JSR print_joystick
    JSR have_ws
    BNE cmd_status_pass
    JSR joystick_on
    BPL cmd_status_hint
    JSR print_inline
    EQUS "Proportional, Switched, Stick unused", 13, 0
.cmd_status_hint
    JSR print_inline
    EQUS "Configure with *SPITFIRE JOYSTICK", 13, 0
.cmd_status_pass
    SEC
    RTS

; ------ OSWORD &3F ------

; Service &08: OSWORD &3F, for software (see "Enumeration: OSWORD &3F"
; in docs/rom-design.md). Byte 0 of the block is the reason code:
;   0 identify: 0 &53, 1 API version, 2-3 ROM version (BCD major,
;     minor), 4 modules (b0 joystick, b1 RTC), 5 status flags
;   1 joystick summary: 0 &53, 1 n, 2-3 port types, 4-7 joysticks 1-4
;     (b7 port, b6 handset, b0-5 type; &FF if not allocated), 8 flags
;   2 describe joystick j (byte 1): 0 &53, 2 as reason 1, 3 kind,
;     4 capabilities, 5 buttons
;   3 name a port type: 1 type, 2 which (0 keyword, 1 full name), 3-4
;     buffer, 5 buffer size; on exit 0 &53, 6 characters copied (before
;     the CR), 7 b0 = no such type or name
; Other reason codes are not claimed. C=0 if claimed. Saves and restores
; &A8-&AF.
API_VERSION = 1

ST_NO_WS   = 1              ; Status flags
ST_NO_AVR  = 2
ST_OFF     = 4
ST_STOPPED = 8

MOD_JOYSTICK = 1            ; Modules in this ROM
MOD_RTC      = 2

flags     = ws + 2          ; OSWORD: the status flags
slot      = ws + 1          ; OSWORD: the slot being described
src       = ws + 4          ; OSWORD reason 3: the name (2 bytes)
dst       = ws + 6          ; OSWORD reason 3: the buffer (2 bytes)

.joy_osword
    LDA OSWORD_A
    CMP #&3F
    BNE joy_osword_pass
    LDY #0
    LDA (OSWORD_BLK), Y
    CMP #joy_osword_reasons_end - joy_osword_reasons
    BCS joy_osword_pass     ; Not a reason code we know
    LDX #7                  ; Save &A8-&AF
.joy_osword_save
    LDA ws, X
    PHA
    DEX
    BPL joy_osword_save
    JSR joy_osword_reason
    LDX #&F8                ; Restore &A8-&AF (as rtc_osword)
.joy_osword_restore
    PLA
    STA ws + 8, X
    INX
    BNE joy_osword_restore
    CLC
    RTS
.joy_osword_pass
    SEC
    RTS

; Answer the block's reason code: mark the block as answered, then run
; the reason's routine
.joy_osword_reason
    LDY #0
    LDA (OSWORD_BLK), Y
    TAX
    LDA joy_osword_hi, X
    PHA
    LDA joy_osword_reasons, X
    PHA
    LDY #0
    LDA #&53
    STA (OSWORD_BLK), Y
    RTS                     ; To the routine
.joy_osword_reasons         ; Routine addresses less one, low bytes
    EQUB LO(joy_identify - 1), LO(joy_summary - 1)
    EQUB LO(joy_joystick - 1), LO(joy_name - 1)
.joy_osword_reasons_end
.joy_osword_hi
    EQUB HI(joy_identify - 1), HI(joy_summary - 1)
    EQUB HI(joy_joystick - 1), HI(joy_name - 1)

; The status flags into `flags`, and `config` from the AVR if the flags
; allow (bits 0 and 1 clear). Z=1 if they do.
.joy_status
    LDA OSWORD_A            ; OSBYTE stores its A, X and Y over the
    PHA                     ; OSWORD number and block address: keep them
    LDA OSWORD_BLK
    PHA
    LDA OSWORD_BLK+1
    PHA
    LDA #&BE                ; Read the MOS's joystick byte into X
    LDX #0
    LDY #&FF
    JSR OSBYTE
    PLA
    STA OSWORD_BLK+1
    PLA
    STA OSWORD_BLK
    PLA
    STA OSWORD_A
    LDA #0
    CPX #&80
    BCS joy_status_on
    LDA #ST_OFF             ; Bit 7 clear: the MOS has the joystick
.joy_status_on
    LDX ADC_MAXIMUM
    BNE joy_status_running
    ORA #ST_STOPPED         ; *FX16,0
.joy_status_running
    STA flags
    JSR have_ws
    BEQ joy_status_ws
    LDA #ST_NO_WS
    BNE joy_status_bad
.joy_status_ws
    JSR read_config
    BCC joy_status_ok
    LDA #ST_NO_AVR
.joy_status_bad
    ORA flags
    STA flags
    RTS                     ; Z=0
.joy_status_ok
    LDA #0                  ; Z=1
    RTS

; Reason 0: identify
.joy_identify
    JSR joy_status
    LDY #1
    LDA #API_VERSION
    STA (OSWORD_BLK), Y
    INY
    LDA #HI(VERSION_BCD)
    STA (OSWORD_BLK), Y
    INY
    LDA #LO(VERSION_BCD)
    STA (OSWORD_BLK), Y
    INY
    LDA #MOD_JOYSTICK OR MOD_RTC
    STA (OSWORD_BLK), Y
    INY
    LDA flags
    STA (OSWORD_BLK), Y
    RTS

; Reason 1: joystick summary
.joy_summary
    LDY #1                  ; Start from nothing allocated
    LDA #0
    STA (OSWORD_BLK), Y
    INY
    STA (OSWORD_BLK), Y
    INY
    STA (OSWORD_BLK), Y
    LDA #&FF
.joy_summary_clear
    INY
    STA (OSWORD_BLK), Y     ; Bytes 4-7
    CPY #7
    BNE joy_summary_clear
    JSR joy_status
    PHP
    LDY #8
    LDA flags
    STA (OSWORD_BLK), Y
    PLP
    BNE joy_summary_done
    LDA config
    AND #7
    LDY #2
    STA (OSWORD_BLK), Y
    LDA config
    LSR A
    LSR A
    LSR A
    AND #7
    INY
    STA (OSWORD_BLK), Y
    LDA #0
    STA slot
.joy_summary_slot
    LDA slot
    JSR slot_byte
    CMP #&FF
    BEQ joy_summary_next
    PHA
    LDA slot
    CLC
    ADC #4
    TAY
    PLA
    STA (OSWORD_BLK), Y
    LDY #1                  ; n = this slot + 1: slots fill in order
    LDA slot
    CLC
    ADC #1
    STA (OSWORD_BLK), Y
.joy_summary_next
    INC slot
    LDA slot
    CMP #4
    BNE joy_summary_slot
.joy_summary_done
    RTS

; Reason 2: describe joystick j
.joy_joystick
    LDY #2
    LDA #&FF                ; Not allocated
    STA (OSWORD_BLK), Y
    LDA #0
.joy_joystick_clear
    INY
    STA (OSWORD_BLK), Y     ; Bytes 3-5
    CPY #5
    BNE joy_joystick_clear
    JSR joy_status
    BNE joy_joystick_done
    LDY #1
    LDA (OSWORD_BLK), Y
    SEC
    SBC #1
    CMP #4
    BCS joy_joystick_done   ; Not joystick 1-4
    JSR slot_byte
    CMP #&FF
    BEQ joy_joystick_done
    LDY #2
    STA (OSWORD_BLK), Y
    LDX dtype
    LDA dj
    BEQ joy_joystick_kind
    CPX #T_BITSTIK
    BNE joy_joystick_kind
    LDX #T_BITSTIK_AUX      ; A Bitstik's second slot
.joy_joystick_kind
    INY
    LDA kind_of, X
    STA (OSWORD_BLK), Y
    INY
    LDA capabilities_of, X
    STA (OSWORD_BLK), Y
    INY
    LDA buttons_of, X
    STA (OSWORD_BLK), Y
.joy_joystick_done
    RTS

; The descriptor of slot A (0-3): b7 port, b6 handset, b0-5 type; or
; &FF if nothing is allocated to it. Also dtype = the type and dj = the
; handset. Needs `config`.
.slot_byte
    JSR slot_info           ; A = type or &FF, X = port, Y = handset
    STA dtype
    STY dj
    CMP #&FF
    BEQ slot_byte_done
    CPY #0
    BEQ slot_byte_port
    ORA #&40
.slot_byte_port
    CPX #0
    BEQ slot_byte_done
    ORA #&80
.slot_byte_done
    RTS

; Reason 3: name a port type
.joy_name
    LDY #2
    LDA (OSWORD_BLK), Y     ; Which name
    TAX
    DEY
    LDA (OSWORD_BLK), Y     ; The type
    CMP #joysticks_of_end - joysticks_of
    BCS joy_name_none
    CPX #0
    BEQ joy_name_keyword
    CPX #1
    BNE joy_name_none
    TAX                     ; Full name
    LDA type_names, X
    CLC
    ADC #LO(type_name_none)
    STA src
    LDA #HI(type_name_none)
    ADC #0
    STA src+1
    LDA #0
    BEQ joy_name_copy
.joy_name_keyword           ; Skip `type` keywords from NONE
    TAX
    LDY #0
.joy_name_skip
    DEX
    BMI joy_name_found
.joy_name_skip_char
    INY
    LDA word_none - 1, Y
    BNE joy_name_skip_char
    BEQ joy_name_skip
.joy_name_found
    TYA
    CLC
    ADC #LO(word_none)
    STA src
    LDA #HI(word_none)
    ADC #0
    STA src+1
    LDA #0
    BEQ joy_name_copy
.joy_name_none
    LDA #LO(empty_name)
    STA src
    LDA #HI(empty_name)
    STA src+1
    LDA #1                  ; No such type or name
.joy_name_copy
    LDY #7
    STA (OSWORD_BLK), Y
    LDY #3
    LDA (OSWORD_BLK), Y
    STA dst
    INY
    LDA (OSWORD_BLK), Y
    STA dst+1
    INY
    LDA (OSWORD_BLK), Y     ; The buffer's size
    TAX
    LDY #0
    CPX #0
    BEQ joy_name_count      ; No room even for the CR
    DEX                     ; Room for the characters
.joy_name_char
    TXA
    BEQ joy_name_end        ; Full
    LDA (src), Y
    BEQ joy_name_end
    STA (dst), Y
    INY
    DEX
    JMP joy_name_char
.joy_name_end
    LDA #13
    STA (dst), Y
.joy_name_count
    TYA
    LDY #6
    STA (OSWORD_BLK), Y
    RTS

; ------ Parsing ------

; Match the keyword at words+X against the command at (CMD_PTR),Y.
; Matched: C=0, Y past the word and any spaces. Otherwise C=1, Y
; unchanged. Corrupts A and X.
.match_word
    STY cmd_start
.match_word_char
    LDA words, X
    BEQ match_word_end
    LDA (CMD_PTR), Y
    CMP #'a'
    BCC match_word_compare
    AND #&DF                ; Lower case letter to upper case
.match_word_compare
    CMP words, X
    BNE match_word_fail
    INX
    INY
    BNE match_word_char
.match_word_end
    LDA (CMD_PTR), Y
    CMP #13
    BEQ match_word_ok
    CMP #' '
    BNE match_word_fail
.match_word_space
    INY
    LDA (CMD_PTR), Y
    CMP #' '
    BEQ match_word_space
.match_word_ok
    CLC
    RTS
.match_word_fail
    LDY cmd_start
    SEC
    RTS

; Match one of the keywords in the list at words+X (each followed by a
; zero, the list by another zero). Matched: C=0, choice = its index, Y
; past it. Otherwise C=1, Y unchanged. Corrupts A and X.
.match_choice
    LDA #0
    STA choice
.match_choice_try
    STX choice_x
    JSR match_word
    BCC match_choice_done
    LDX choice_x
.match_choice_skip
    INX
    LDA words - 1, X
    BNE match_choice_skip
    INC choice
    LDA words, X
    BNE match_choice_try
    SEC
.match_choice_done
    RTS

; Match A or B: C=0 and A = 0 or 1, or C=1. Corrupts X.
.match_port
    LDX #word_a - words
    JSR match_choice
    LDA choice
    RTS

; Z=1 if (CMD_PTR),Y is the end of the line
.at_end
    LDA (CMD_PTR), Y
    CMP #13
    RTS

; ------ Printing ------

; Print "SPItFIRE <version>" and a newline
.print_title
    JSR OSNEWL
    LDX #0
.print_title_char
    LDA title, X
    BNE print_title_out
    LDA #' '                ; The zero between title and version
.print_title_out
    JSR OSASCI
    INX
    CPX #copyright - title
    BNE print_title_char
    JMP OSNEWL

; Print A (0-99) in decimal, without leading zeros. Corrupts A and X.
.print_dec8
    LDX #0
.print_dec8_tens
    CMP #10
    BCC print_dec8_units
    SBC #10
    INX
    BNE print_dec8_tens
.print_dec8_units
    PHA
    TXA
    BEQ print_dec8_last
    ORA #'0'
    JSR OSASCI
.print_dec8_last
    PLA
    ORA #'0'
    JMP OSASCI

; Print the 16-bit `value` in decimal, without leading zeros. Corrupts
; A, X, Y and `value`.
.print_dec16
    LDA #0
    STA lead
    LDX #3                  ; 10000, 1000, 100, 10
.print_dec16_digit
    LDY #0
.print_dec16_sub
    LDA value
    SEC
    SBC tens_lo, X
    PHA
    LDA value+1
    SBC tens_hi, X
    BCC print_dec16_got
    STA value+1
    PLA
    STA value
    INY
    BNE print_dec16_sub
.print_dec16_got
    PLA
    TYA
    BNE print_dec16_print
    LDA lead
    BEQ print_dec16_next
    TYA
.print_dec16_print
    ORA #'0'
    JSR OSASCI
    LDA #1
    STA lead
.print_dec16_next
    DEX
    BPL print_dec16_digit
    LDA value
    ORA #'0'
    JMP OSASCI

.tens_lo    EQUB LO(10), LO(100), LO(1000), LO(10000)
.tens_hi    EQUB HI(10), HI(100), HI(1000), HI(10000)

; Print A as two hex digits. Corrupts A.
.print_hex
    PHA
    LSR A
    LSR A
    LSR A
    LSR A
    JSR print_hex_digit
    PLA
    AND #&0F
.print_hex_digit
    CMP #10
    BCC print_hex_out
    ADC #'A' - 10 - 1 - '0' ; C=1
.print_hex_out
    ADC #'0'
    JMP OSASCI

; Print the zero-terminated string that follows the JSR (CR is a
; newline). Preserves X and Y.
.print_inline
    PLA
    STA str_ptr
    PLA
    STA str_ptr+1
    TYA
    PHA
    LDY #0
.print_inline_next
    INC str_ptr
    BNE print_inline_char
    INC str_ptr+1
.print_inline_char
    LDA (str_ptr), Y
    BEQ print_inline_done
    JSR OSASCI
    JMP print_inline_next
.print_inline_done
    PLA
    TAY
    LDA str_ptr+1
    PHA
    LDA str_ptr
    PHA
    RTS

; ------ Data ------

; Joysticks (slots) each port type takes
.joysticks_of
    EQUB 0, 1, 2, 2, 2, 1, 2, 2
.joysticks_of_end

; OSWORD &3F reason 2, by type, then T_BITSTIK_AUX. Kinds: 1 stick,
; 2 position, 3 auxiliary, 4 chord. Capabilities: b0 X and Y carry
; readings, b1 directions, b2 keypad.
.kind_of
    EQUB 0, 1, 1, 1, 1, 1, 2, 4, 3
.capabilities_of
    EQUB 0, 3, 3, 3, 3, 7, 3, 1, 1
.buttons_of
    EQUB 0, 1, 1, 1, 1, 1, 1, 0, 1

; The X channel of each slot
.slot_channels
    EQUB 1, 3, 17, 19

; *SPITFIRE ADVAL: the channels in order, with what each carries and
; the slot it belongs to
K_X        = 0
K_Y        = 1
K_SWITCHES = 2
K_KEYS     = 3
K_SWBYTES  = 4              ; A pair's switch bytes, one each
.adval_rows
    EQUB 0, 1, 2, 3, 4, 10, 11, 12, 16, 17, 18, 19, 20, 26, 27, 28
.adval_rows_end
.adval_kinds
    EQUB K_SWITCHES, K_X, K_Y, K_X, K_Y, K_KEYS, K_KEYS, K_SWBYTES
    EQUB K_SWITCHES, K_X, K_Y, K_X, K_Y, K_KEYS, K_KEYS, K_SWBYTES
.adval_slots
    EQUB 0, 0, 0, 1, 1, 0, 1, 0
    EQUB 2, 2, 2, 3, 3, 2, 3, 2

.bitstik_uses               ; By 2j + axis, offsets into bitstik_x
    EQUB bitstik_x - bitstik_x, bitstik_y - bitstik_x
    EQUB bitstik_twist - bitstik_x, bitstik_button - bitstik_x
.bitstik_x      EQUS "Bitstik X", 0
.bitstik_y      EQUS "Bitstik Y", 0
.bitstik_twist  EQUS "Bitstik twist", 0
.bitstik_button EQUS "Bitstik button", 0

.words
.word_spitfire  EQUS "SPITFIRE", 0
.word_joystick  EQUS "JOYSTICK", 0
.word_port      EQUS "PORT", 0
.word_adval     EQUS "ADVAL", 0
.word_all       EQUS "ALL", 0
.word_on        EQUS "ON", 0            ; Choices, in order of index
                EQUS "OFF", 0, 0
.word_a         EQUS "A", 0
                EQUS "B", 0, 0
.word_none      EQUS "NONE", 0          ; The AVR's type numbers
                EQUS "SINGLE", 0
                EQUS "DUAL", 0
                EQUS "3BS", 0
                EQUS "3BT", 0
                EQUS "14B", 0
                EQUS "BITSTIK", 0
                EQUS "QUINKEY", 0, 0

.type_names
    EQUB type_name_none - type_name_none
    EQUB type_name_single - type_name_none
    EQUB type_name_dual - type_name_none
    EQUB type_name_3bs - type_name_none
    EQUB type_name_3bt - type_name_none
    EQUB type_name_14b - type_name_none
    EQUB type_name_bitstik - type_name_none
    EQUB type_name_quinkey - type_name_none
.type_name_none     EQUS "No joystick", 0
.type_name_single   EQUS "Standard single joystick", 0
.type_name_dual     EQUS "Standard dual joystick", 0
.type_name_3bs      EQUS "Voltmace Delta 3B Single", 0
.type_name_3bt      EQUS "Voltmace Delta 3B Twin", 0
.type_name_14b      EQUS "Voltmace Delta 14B", 0
.type_name_bitstik  EQUS "Acorn Bitstik", 0
.type_name_quinkey  EQUS "Microwriter Quinkey", 0
.empty_name         EQUB 0

; Error blocks: BRK, number, message, zero
.errors
.error_syntax
    EQUB 0, &DC
    EQUS "Syntax: see *HELP SPITFIRE", 0
.error_avr
    EQUB 0, &C8
    EQUS "SPItFIRE not responding", 0
