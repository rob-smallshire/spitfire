; SPItFIRE Sideways ROM
; Prototype: ROM header, service call dispatch, SPI core, the RTC module
; (OSWORD &0E/&0F) and the joystick module (MOS 5.x service call &2C).
; See docs/rom-design.md.
;
; Build with beebasm from beeb/rom (see Makefile).

; OS calls
OSASCI = &FFE3
OSNEWL = &FFE7

; OS workspace
OSWORD_A   = &EF            ; OSWORD number, on service call &08
OSWORD_BLK = &F0            ; OSWORD parameter block address (2 bytes)
CMD_PTR    = &F2            ; Command line pointer, on service call &09

; Workspace &A8-&AF: free for *commands, but an OSWORD handler must
; save and restore it (rtc.asm does). Shared by the modules below.
ws = &A8

ORG &8000
GUARD &C000

.rom_start
    EQUB 0, 0, 0            ; No language entry
    JMP service
    EQUB &82                ; Service entry, 6502 code
    EQUB LO(copyright - rom_start)
    EQUB 1                  ; Binary version
.title
    EQUS "SPItFIRE"
    EQUB 0
.version
    EQUS "0.01"
.copyright
    EQUB 0
    EQUS "(C)2026 Robert Smallshire", 0

; ------ Service call dispatch ------
; A = reason, X = this ROM's slot, Y = parameter. Return A=0 to claim,
; otherwise A unchanged. X and Y must be preserved.
.service
    CMP #&2C
    BEQ service_joystick
    CMP #&04
    BEQ service_command
    CMP #&08
    BEQ service_osword
    CMP #&09
    BEQ service_help
    CMP #&27
    BEQ service_reset
    RTS

; Service &2C: Master Compact joystick poll (in the interrupt). Claimed.
.service_joystick
    JSR joy_poll
    LDA #0
    RTS

; Service &27: reset
.service_reset
    JSR joy_reset
    LDA #&27
    RTS

; Service &08: unrecognised OSWORD
.service_osword
    PHA
    TXA
    PHA
    TYA
    PHA
    JSR rtc_osword          ; C=0 if claimed
    PLA
    TAY
    PLA
    TAX
    PLA
    BCS service_pass
    LDA #0
.service_pass
    RTS

; Service &04: unrecognised *command
.service_command
    PHA
    TXA
    PHA
    TYA
    PHA
    JSR cmd_star            ; C=0 if claimed
    PLA
    TAY
    PLA
    TAX
    PLA
    BCS service_command_pass
    LDA #0
.service_command_pass
    RTS

; Service &09: *HELP. Never claimed.
.service_help
    PHA
    TXA
    PHA
    TYA
    PHA
    JSR cmd_help
    PLA
    TAY
    PLA
    TAX
    PLA
    RTS

INCLUDE "src/spi.asm"
INCLUDE "src/rtc.asm"
INCLUDE "src/joystick.asm"
INCLUDE "src/commands.asm"

.rom_end

SAVE rom_start, rom_end
