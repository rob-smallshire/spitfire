; *SPITFIRE commands and *HELP
; See "The *SPITFIRE Command Namespace" in docs/rom-design.md.
;
;   *SPITFIRE                   Version and modules
;   *SPITFIRE JOYSTICK          Joystick settings
;   *SPITFIRE JOYSTICK ON|OFF   Hand the MOS's joystick handling to the
;                               ROM, or give it back
;   *SPITFIRE JOYSTICK A|B <type>
;                               Set and save a port's type: NONE, TWIN,
;                               SINGLE or 14B
;   *SPITFIRE JOYSTICK USE A|B [1|2]
;                               Set and save which handset is the BBC's
;                               joystick (1 = CH0/CH1, 2 = CH2/CH3)
;   *HELP                       Title, version, the SPITFIRE topic and
;                               the current settings (as the network
;                               filing systems show their station)
;   *HELP SPITFIRE [JOYSTICK]   The commands (or the joystick's), then
;                               the settings
;
; The port types and the handset live in the AVR's EEPROM. The AVR only
; writes it when a value changes, and only these commands change them.
;
; Keywords match in either case and must be followed by a space or the
; end of the line. Uses &A8-&AF, which are free during *commands.

cmd_start = ws + 0          ; Start of the word being matched
choice    = ws + 1          ; match_choice: index of the word matched
choice_x  = ws + 2          ; match_choice: offset of the word tried
config    = ws + 3          ; The AVR's configuration byte
port      = ws + 4          ; 0 = Port A, 1 = Port B
indent    = ws + 5          ; Non-zero to indent the settings
str_ptr   = ws + 6          ; 2 bytes: print_inline's pointer

; Service &04: unrecognised command. Y = offset of the command at
; (CMD_PTR). Return C=0 if claimed (the command has run), C=1 to pass.
.cmd_star
    LDX #word_spitfire - words
    JSR match_word
    BCS cmd_pass
    JSR at_end
    BEQ cmd_summary
    LDX #word_joystick - words
    JSR match_word
    BCS cmd_syntax
    JSR at_end
    BEQ cmd_joystick_status
    LDX #word_on - words    ; ON, OFF
    JSR match_choice
    BCC cmd_joystick_on_off
    LDX #word_a - words     ; A, B
    JSR match_choice
    BCC cmd_joystick_port
    LDX #word_use - words
    JSR match_word
    BCC cmd_joystick_use
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

; *SPITFIRE JOYSTICK A|B <type>
.cmd_joystick_port
    LDA choice
    STA port
    LDX #word_none - words  ; NONE, TWIN, SINGLE, 14B
    JSR match_choice
    BCS cmd_syntax
    JSR at_end
    BNE cmd_syntax
    LDA port
    ASL A
    ASL A
    ORA choice
    ORA #CMD_CFG_TYPE_A     ; &D0 + 4 * port + type
    BNE cmd_configure       ; Always

; *SPITFIRE JOYSTICK USE A|B [1|2]
.cmd_joystick_use
    LDX #word_a - words
    JSR match_choice
    BCS cmd_syntax
    LDA choice
    STA port
    LDA #0
    STA choice              ; Handset 1 unless given
    JSR at_end
    BEQ cmd_joystick_use_set
    LDX #word_1 - words     ; 1, 2
    JSR match_choice
    BCS cmd_syntax
    JSR at_end
    BNE cmd_syntax
.cmd_joystick_use_set
    LDA port
    ASL A
    ORA choice
    ORA #CMD_CFG_HANDSET    ; &D8 + 2 * port + handset
    ; Fall through

; Send configuration command A to the AVR, which applies it and saves it
; in EEPROM. The AVR echoes the command.
.cmd_configure
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

; Print the current settings, indented, for *HELP
.print_settings
    LDA #1
    STA indent
    ; Fall through

; Print the joystick settings, indented if `indent` is non-zero:
;   Joystick on, Port A 1
;   Ports A 3B Twin, B None
; "on" or "off" is bit 7 of the MOS's joystick byte, the rest is the
; AVR's saved configuration.
.print_joystick
    JSR print_indent
    JSR print_inline
    EQUS "Joystick o", 0
    LDA #&BE                ; Read the joystick byte
    LDX #0
    LDY #&FF
    JSR OSBYTE
    TXA
    BPL print_joystick_off
    JSR print_inline
    EQUS "n", 0
    JMP print_joystick_config
.print_joystick_off
    JSR print_inline
    EQUS "ff", 0
.print_joystick_config
    LDA #CMD_JOY_CONFIG
    JSR joy_command
    STA config
    AND #&C0
    CMP #CONFIG_VALID
    BEQ print_joystick_handset
    JSR print_inline
    EQUS ", SPItFIRE not responding", 13, 0
    RTS
.print_joystick_handset
    JSR print_inline
    EQUS ", Port ", 0
    LDA config              ; b5 = port, b4 = handset
    LSR A
    LSR A
    LSR A
    LSR A
    PHA
    LSR A
    AND #1
    CLC
    ADC #'A'
    JSR OSASCI
    LDA #' '
    JSR OSASCI
    PLA
    AND #1
    CLC
    ADC #'1'
    JSR OSASCI
    JSR OSNEWL
    JSR print_indent
    JSR print_inline
    EQUS "Ports A ", 0
    LDA config
    JSR print_type
    JSR print_inline
    EQUS ", B ", 0
    LDA config
    LSR A
    LSR A
    JSR print_type
    JMP OSNEWL

; Print the name of the type in bits 0-1 of A
.print_type
    AND #3
    TAX
    LDA type_names, X
    TAX
.print_type_char
    LDA type_name_none, X
    BEQ print_type_done
    JSR OSASCI
    INX
    BNE print_type_char
.print_type_done
    RTS

.print_indent
    LDA indent
    BEQ print_indent_done
    JSR print_inline
    EQUS "  ", 0
.print_indent_done
.cmd_help_done
    RTS

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
    EQUS "  SPITFIRE", 13, 0
.help_joystick
    JSR print_inline
    EQUS "  SPITFIRE JOYSTICK [ON|OFF]", 13
    EQUS "  SPITFIRE JOYSTICK A|B <type>", 13
    EQUS "  SPITFIRE JOYSTICK USE A|B [1|2]", 13
    EQUS "    <type>: NONE TWIN SINGLE 14B", 13, 0
    JMP print_settings

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

; Print the zero-terminated string that follows the JSR (CR is a
; newline). Preserves Y.
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

.words
.word_spitfire  EQUS "SPITFIRE", 0
.word_joystick  EQUS "JOYSTICK", 0
.word_use       EQUS "USE", 0
.word_on        EQUS "ON", 0            ; Choices, in order of index
                EQUS "OFF", 0, 0
.word_a         EQUS "A", 0
                EQUS "B", 0, 0
.word_1         EQUS "1", 0
                EQUS "2", 0, 0
.word_none      EQUS "NONE", 0          ; The AVR's type numbers
                EQUS "TWIN", 0
                EQUS "SINGLE", 0
                EQUS "14B", 0, 0

.type_names
    EQUB type_name_none - type_name_none
    EQUB type_name_twin - type_name_none
    EQUB type_name_single - type_name_none
    EQUB type_name_14b - type_name_none
.type_name_none     EQUS "None", 0
.type_name_twin     EQUS "3B Twin", 0
.type_name_single   EQUS "3B Single", 0
.type_name_14b      EQUS "14B", 0

; Error blocks: BRK, number, message, zero
.errors
.error_syntax
    EQUB 0, &DC
    EQUS "Syntax: see *HELP SPITFIRE JOYSTICK", 0
.error_avr
    EQUB 0, &C8
    EQUS "SPItFIRE not responding", 0
