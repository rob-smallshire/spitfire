; *SPITFIRE commands and *HELP
; See "The *SPITFIRE Command Namespace" in docs/rom-design.md.
;
;   *SPITFIRE                   Version and modules
;   *SPITFIRE JOYSTICK          Joystick status
;   *SPITFIRE JOYSTICK ON|OFF   Hand the MOS's joystick handling to the
;                               ROM, or give it back
;   *HELP                       Title, version, the SPITFIRE topic and
;                               the current settings (as the network
;                               filing systems show their station)
;   *HELP SPITFIRE [JOYSTICK]   The commands (or the joystick's), then
;                               the settings
;
; Keywords match in either case and must be followed by a space or the
; end of the line. Uses &A8-&AF, which are free during *commands.

cmd_start = ws + 0          ; Start of the word being matched
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
    LDX #word_on - words
    JSR match_word
    BCC cmd_joystick_on
    LDX #word_off - words
    JSR match_word
    BCS cmd_syntax
    JSR at_end
    BNE cmd_syntax
    LDX #&00                ; *FX190,0,127: clear bit 7, keep the rest
    BEQ cmd_joystick_set
.cmd_joystick_on
    JSR at_end
    BNE cmd_syntax
    LDX #&80                ; *FX190,128,127: set bit 7, keep the rest
.cmd_joystick_set
    LDA #&BE
    LDY #&7F
    JSR OSBYTE
    CLC
    RTS
.cmd_pass
    SEC
    RTS

.cmd_syntax
    LDX #0
.cmd_syntax_copy
    LDA error_syntax, X
    STA &0100, X
    INX
    CPX #error_syntax_end - error_syntax
    BNE cmd_syntax_copy
    JMP &0100

; *SPITFIRE: version and modules
.cmd_summary
    JSR print_title
    JSR print_inline
    EQUS "Modules: RTC JOYSTICK", 13, 0
    CLC
    RTS

; *SPITFIRE JOYSTICK: whether the ROM has the MOS's joystick handling
.cmd_joystick_status
    JSR print_joystick
    CLC
    RTS

; Print the current settings, indented, for *HELP
.print_settings
    JSR print_inline
    EQUS "  ", 0
    ; Fall through

; Print "Joystick on (Port A CH0/CH1)" or "Joystick off": whether bit 7
; of the MOS's joystick byte hands its joystick handling to the ROM
.print_joystick
    LDA #&BE                ; Read the joystick byte
    LDX #0
    LDY #&FF
    JSR OSBYTE
    TXA
    BPL print_joystick_off
    JSR print_inline
    EQUS "Joystick on (Port A CH0/CH1)", 13, 0
    RTS
.print_joystick_off
    JSR print_inline
    EQUS "Joystick off", 13, 0
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
    EQUS "    Port A CH0/CH1 as ADVAL(0)-(2)", 13, 0
    JMP print_settings
.cmd_help_done
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
    AND #&DF                ; Upper case (keywords are letters only)
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
.word_on        EQUS "ON", 0
.word_off       EQUS "OFF", 0

.error_syntax
    EQUB 0, &DC
    EQUS "Syntax: SPITFIRE JOYSTICK [ON|OFF]", 0
.error_syntax_end
