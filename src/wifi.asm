;; Wi-Fi for the radio: when the ESP is on no network, join the one of the
;; karabas gopher settings, /zifi/gopher.ini: [zifi32] ssid= / password=, with
;; the commands gopher uses (SET_AP_NAME, SET_AP_PWD, AP_CONNECT). The settings
;; of the ESP itself are not changed.
;; The file is found from the root in WC stream 1 (a clone of the panel's);
;; stream 0 stays on the folder of the play list.

E_CMD_NETSTATE  equ #11
E_CMD_AP_NAME   equ #13
E_CMD_AP_PWD    equ #14
E_CMD_AP_CONN   equ #16
NET_OPEN        equ 2               ; NETSTATE: connected, with an address
INI_MAX         equ BUFSZ - 1       ; the part of the file read
CONN_TRIES      equ 60              ; esp_wait rounds (~0.5 s each) for AP_CONNECT

;; OUT: CF = 1 when there is still no network
net_up:
    call net_state
    cp NET_OPEN
    ret z                           ; CF = 0
    xor a
    ld (wf_ssid),a
    ld (wf_pass),a
    call ini_load
    jr c,.no
    call ini_parse
    ld a,(wf_ssid)
    or a
    jr z,.no
    ; join
    ld hl,wf_ssid
    ld a,E_CMD_AP_NAME
    call esp_str
    ld hl,wf_pass
    ld a,E_CMD_AP_PWD
    call esp_str
    ld a,E_CMD_AP_CONN
    call esp_cmd
    ld b,CONN_TRIES
.wait:
    push bc
    ld c,0
    call esp_wait
    pop bc
    jr nc,.done
    djnz .wait
.done:
    call net_state
    cp NET_OPEN
    ret z
.no:
    scf
    ret

;; OUT: A = NETSTATE of the ESP (#FF: no answer)
net_state:
    ld a,E_CMD_NETSTATE
    call esp_run
    ld a,#FF
    ret c
    ld d,E_REG_STR_SIZE
    jp esp_rd8

;; HL = 0-terminated text, A = command: STRING_SIZE, STRING_DATA, the command
esp_str:
    push af
    push hl
    call strlen                     ; BC = length
    ld a,c
    cp 62
    jr c,.len
    ld a,61
.len:
    ld (wf_len),a
    call esp_cs_on
    ld a,SPI_WR_REGS : out (SPI_DATA),a
    ld a,E_REG_STR_SIZE : out (SPI_DATA),a
    in a,(SPI_DATA)                 ; dummy
    ld a,(wf_len) : out (SPI_DATA),a
    pop hl
    or a
    jr z,.end
    ld b,a
    ld c,SPI_DATA
    otir
.end:
    call esp_cs_off
    pop af
    jp esp_run

;; /zifi/gopher.ini into BUF (0-terminated). OUT: CF = 1 not there
ini_load:
    ld d,#FE                        ; clone the panel's stream into 0 and 1 (0 active)
    WCALL WCF_STREAM
    ld d,1
    ld bc,#FFFF                     ; stream 1
    WCALL WCF_STREAM
    ld d,#FF                        ; its root
    WCALL WCF_STREAM
    ld hl,s_ini
    WCALL WCF_FENTRY
    jr z,.none
    ld a,d : or e
    jr nz,.big
    ld bc,INI_MAX
    or a
    sbc hl,bc
    add hl,bc
    jr c,.size
.big:
    ld hl,INI_MAX
.size:
    ld (wf_size),hl
    WCALL WCF_GFILE
    ld hl,BUF
    ld b,BUF_SECT
    WCALL WCF_LOAD512
    ld hl,(wf_size)
    ld de,BUF
    add hl,de
    ld (hl),0
    call .back
    or a
    ret
.none:
    call .back
    scf
    ret
.back:
    ld d,0                          ; stream 0 again: the folder of the list
    ld bc,#FFFF
    WCALL WCF_STREAM
    ret

;; BUF -> wf_ssid / wf_pass of the section [zifi32]
ini_parse:
    ld hl,BUF
    xor a
    ld (wf_in),a
.line:
    ld a,(hl)
    or a
    ret z
    ld de,lbuf
    ld b,LINE_MAX
.copy:
    ld a,(hl)
    or a
    jr z,.eol
    inc hl
    cp 10
    jr z,.eol
    cp 13
    jr z,.eol
    ld (de),a
    inc de
    djnz .copy
.skip:
    ld a,(hl)                       ; a longer line: the rest of it
    or a
    jr z,.eol
    inc hl
    cp 10
    jr nz,.skip
.eol:
    xor a
    ld (de),a
    push hl
    call .use
    pop hl
    jr .line
.use:
    ld hl,lbuf
    call skip_sp
    ld a,(hl)
    cp '['
    jr nz,.key
    ld de,s_sect                    ; "[zifi32]" (compared with bit 5 set: { })
    call prefix
    ld a,1
    jr z,.in
    xor a
.in:
    ld (wf_in),a
    ret
.key:
    ld a,(wf_in)
    or a
    ret z
    push hl
    ld de,s_ssid
    call prefix
    pop hl
    jr z,.ssid
    ld de,s_pass
    call prefix
    ret nz
    ld de,wf_pass
    ld b,63
    jr .val
.ssid:
    ld de,wf_ssid
    ld b,32
.val:
    ; HL in the key: after '=', spaces off
    ld a,(hl)
    or a
    ret z
    inc hl
    cp '='
    jr nz,.val
    call skip_sp
.v:
    ld a,(hl)
    ld (de),a
    or a
    ret z
    inc hl
    inc de
    djnz .v
    xor a
    ld (de),a
    ret

;; HL past spaces and tabs
skip_sp:
    ld a,(hl)
    cp ' '
    jr z,.n
    cp 9
    ret nz
.n:
    inc hl
    jr skip_sp

s_ini:      db 0, "zifi/gopher.ini", 0  ; FENTRY: flag (a file), path
s_sect:     db "{zifi32}", 0
s_ssid:     db "ssid", 0
s_pass:     db "password", 0
