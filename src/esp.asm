;; The audio stream player of ZiFi32 (ESP_CMD_AUDIO_*, pentevo/esp32/doc/
;; esp32-audio.md of tslabs/zx-evo), over the SPI of TS-Conf (#77 chip
;; select, #57 data), the register protocol as in the esp32 lib of ft812sdk.
;; The ESP decodes MP3, WAV, FLAC and Ogg Vorbis and buffers 512 KB of the
;; stream.

SPI_DATA        equ #57
SPI_CTRL        equ #77
SPI_ESP_ON      equ #13
SPI_ESP_OFF     equ #03

SPI_WR_REGS     equ #01
SPI_RD_REGS     equ #02
SPI_WR_DATA     equ #03
SPI_W_END       equ #07

E_REG_COMMAND   equ #00
E_REG_STATUS    equ #01
E_REG_PARAM     equ #02         ; AUDIO_FORMAT / AUDIO_PARAM
E_REG_SIZE      equ #03         ; DATA_SIZE, 4 bytes
E_REG_OFFSET    equ #07         ; DATA_OFFSET, 4 bytes
E_REG_STATE     equ #10         ; state block #10..#2B

E_CMD_GET_VER   equ #02
E_CMD_START     equ #90
E_CMD_PUSH      equ #91
E_CMD_END       equ #92
E_CMD_FLUSH     equ #93
E_CMD_PAUSE     equ #94
E_CMD_VOLUME    equ #95
E_CMD_STOP      equ #96
E_CMD_STATE     equ #97

E_ST_IDLE       equ #00
E_ST_READY      equ #01
E_ST_BUSY       equ #02
E_ST_M2S        equ #03
E_ERR_INV_CMD   equ #80

; AUDIO_ST_*
A_ST_IDLE       equ 0
A_ST_WAIT       equ 1
A_ST_PLAY       equ 2
A_ST_DRAIN      equ 3
A_ST_ENDED      equ 4
A_ST_ERROR      equ 5

; AUDIO_FMT_*
A_FMT_AUTO      equ 0
A_FMT_WAV       equ 1
A_FMT_MP3       equ 2
A_FMT_OGG       equ 3
A_FMT_FLAC      equ 4

A_FLAG_SEEKABLE equ #01

;; ---------------------------------------------------------------------------
;; SPI primitives

esp_cs_on:
    ld a,SPI_ESP_ON
    out (SPI_CTRL),a
    ret

esp_cs_off:
    ld a,SPI_ESP_OFF
    out (SPI_CTRL),a
    ret

;; D = register, E = value
esp_wr8:
    call esp_cs_on
    ld a,SPI_WR_REGS : out (SPI_DATA),a
    ld a,d : out (SPI_DATA),a
    in a,(SPI_DATA)             ; dummy
    ld a,e : out (SPI_DATA),a
    jr esp_cs_off

;; D = register, HL = 4 bytes
esp_wr32:
    call esp_cs_on
    ld a,SPI_WR_REGS : out (SPI_DATA),a
    ld a,d : out (SPI_DATA),a
    in a,(SPI_DATA)
    ld bc,4*256 + SPI_DATA
    otir
    jr esp_cs_off

;; D = register -> A
esp_rd8:
    call esp_cs_on
    ld a,SPI_RD_REGS : out (SPI_DATA),a
    ld a,d : out (SPI_DATA),a
    in a,(SPI_DATA)             ; dummy
    in a,(SPI_DATA)             ; dummy
    in a,(SPI_DATA)
    push af
    call esp_cs_off
    pop af
    ret

;; D = register, HL = buffer, B = bytes
esp_rd:
    call esp_cs_on
    ld a,SPI_RD_REGS : out (SPI_DATA),a
    ld a,d : out (SPI_DATA),a
    in a,(SPI_DATA)
    in a,(SPI_DATA)
    ld c,SPI_DATA
    inir
    jr esp_cs_off

;; A = command: COMMAND = A, STATUS = IDLE
esp_cmd:
    ld e,a
    call esp_cs_on
    ld a,SPI_WR_REGS : out (SPI_DATA),a
    xor a : out (SPI_DATA),a    ; E_REG_COMMAND
    in a,(SPI_DATA)
    ld a,e : out (SPI_DATA),a
    xor a : out (SPI_DATA),a    ; STATUS = E_ST_IDLE
    jr esp_cs_off

;; Wait while the status is IDLE or BUSY (or M2S with C = 1: after W_END).
;; OUT: A = status; CF = 1 on a timeout (about 1 s at 14 MHz)
esp_wait:
    ld hl,0
.loop:
    push hl
    push bc
    ld d,E_REG_STATUS
    call esp_rd8
    pop bc
    pop hl
    cp E_ST_IDLE
    jr z,.more
    cp E_ST_BUSY
    jr z,.more
    cp E_ST_M2S
    jr nz,.done
    bit 0,c
    jr z,.done
.more:
    dec hl
    ld a,h : or l
    jr nz,.loop
    ld a,E_ST_BUSY
    scf
    ret
.done:
    or a
    ret

;; A = command, run to its status. OUT: A = status, CF = 1 timeout
esp_run:
    call esp_cmd
    ld c,0
    jr esp_wait

;; A = command with E = its parameter (AUDIO_FORMAT / AUDIO_PARAM)
esp_run_p:
    push af
    ld d,E_REG_PARAM
    call esp_wr8
    pop af
    jr esp_run

;; The state block (#10..#2B) into esp_st
esp_rd_state:
    ld d,E_REG_STATE
    ld hl,esp_st
    ld b,ESP_ST_LEN
    jr esp_rd

;; ---------------------------------------------------------------------------
;; The player's calls

;; Find the ESP and its audio player.
;; OUT: CF = 1 if there is none; esp_ans = the status GET_STATE answered
esp_detect:
    xor a
    ld (esp_ended),a
    ld a,E_CMD_STATE
    call esp_run
    ld (esp_ans),a
    ret c
    cp E_ST_READY
    ret z
    scf
    ret

;; A = attenuation, 0.5 dB steps (0 full, #FE silence; as a VS1053)
esp_volume:
    ld e,a
    ld a,E_CMD_VOLUME
    jp esp_run_p

;; A new stream, the format from the file name (fname)
;; OUT: CF = 1 refused
esp_start:
    call ext_fmt
    ld (esp_fmt),a
    xor a
    ld (esp_ended),a
    ld (esp_sent_end),a
    ld (esp_base),a
    ld (esp_base+1),a
    ld a,(esp_fmt)
    ld e,a
    ld a,E_CMD_START
    call esp_run_p
    ret c
    cp E_ST_READY
    scf
    ret nz
    ld a,(vol)
    call esp_volume
    call esp_rd_state
    or a
    ret

;; Stop the sound (leaving the player)
esp_stop:
    ld a,E_CMD_STOP
    jp esp_run

;; DEHL = file offset of the next data: drop what the ESP holds (seek)
esp_flush:
    ld (esp_tmp4),hl
    ld (esp_tmp4+2),de
    ld d,E_REG_OFFSET
    ld hl,esp_tmp4
    call esp_wr32
    xor a
    ld (esp_ended),a
    ld (esp_sent_end),a
    ld a,E_CMD_FLUSH
    call esp_run
    jp esp_rd_state

;; A = 1 pause / 0 go on
esp_pause:
    ld e,a
    ld a,E_CMD_PAUSE
    jp esp_run_p

;; The whole file is sent: play out
esp_end:
    ld a,(esp_sent_end)
    or a
    ret nz
    inc a
    ld (esp_sent_end),a
    ld a,E_CMD_END
    jp esp_run

;; OUT: HL = bytes the next PUSH may take: FREE of the ESP, at most BUFSZ
esp_free:
    ld hl,(esp_st + ST_FREE + 2)
    ld a,h : or l
    ld hl,BUFSZ
    ret nz                          ; >= 64 KB
    ld de,(esp_st + ST_FREE)
    or a
    sbc hl,de
    ex de,hl
    ret nc                          ; FREE <= BUFSZ: FREE
    ld hl,BUFSZ
    ret

;; OUT: A = how full the ESP's 512 KB buffer is, 0..128
esp_fill:
    ld hl,(esp_st + ST_BUFFERED + 1)    ; / 256
    ld a,(esp_st + ST_BUFFERED + 3)
    or a
    ld a,128
    ret nz
    ld a,(esp_st + ST_BUFFERED + 2)
    cp 8
    ld a,128
    ret nc                              ; >= 512 KB
    srl h : rr l                        ; / 4096 -> 0..127
    srl h : rr l
    srl h : rr l
    srl h : rr l
    ld a,l
    ret

;; HL = data, DE = bytes (1..BUFSZ): AUDIO_PUSH
;; OUT: CF = 1 if the ESP refused it (the caller keeps the data)
esp_push:
    push hl
    push de
    ld (esp_tmp4),de
    ld hl,0
    ld (esp_tmp4+2),hl
    ld d,E_REG_SIZE
    ld hl,esp_tmp4
    call esp_wr32
    ld a,E_CMD_PUSH
    call esp_cmd
    ld c,0
    call esp_wait
    pop de
    pop hl
    ; no M2S in time: the ESP may arm its DMA a moment later and then wait for
    ; this data for ever (a new PUSH can not get M2S again): send it anyway
    jr c,.send
    cp E_ST_M2S
    jr nz,.fail                 ; refused (INV_STATE, INV_SIZE ...)
.send:
    push de
    call esp_cs_on
    ld a,SPI_WR_DATA : out (SPI_DATA),a
    in a,(SPI_DATA)             ; dummy
    in a,(SPI_DATA)             ; dummy
    pop de
    ld c,SPI_DATA
    ld a,e
    or a
    jr z,.pages
    ld b,a
    otir                        ; the part below 256
.pages:
    ld a,d
    or a
    jr z,.pad
    ld b,0
.page:
    otir                        ; 256 bytes
    dec d
    jr nz,.page
.pad:
    ; the DMA of the ESP takes words: zeros up to a multiple of 4 (the ESP
    ; keeps DATA_SIZE bytes of it)
    ld a,(esp_tmp4)
    neg
    and 3
    jr z,.sent
    ld b,a
    xor a
.z:
    out (SPI_DATA),a
    djnz .z
.sent:
    call esp_cs_off
    call esp_cs_on
    ld a,SPI_W_END : out (SPI_DATA),a
    in a,(SPI_DATA)
    call esp_cs_off
    ld c,1                      ; M2S counts as busy until the W_END is taken
    call esp_wait
    jr c,.fail
    push af
    call esp_rd_state
    pop af
    cp E_ST_READY
    jr nz,.fail
    or a
    ret
.fail:
    call esp_rd_state
    scf
    ret

;; Once per frame: the state of the ESP
esp_tick:
    ld a,E_CMD_STATE
    call esp_run
    ret c
    call esp_rd_state
    ld a,(esp_st + ST_STATE)
    cp A_ST_ENDED
    jr z,.ended
    cp A_ST_ERROR
    ret nz
.ended:
    ld a,1
    ld (esp_ended),a
    ret

;; Elapsed seconds: esp_base + played / rate. OUT: HL (#FFFF: not known)
esp_elapsed:
    ld hl,(esp_st + ST_RATE)
    ld a,h : or l
    ld hl,#FFFF
    ret z
    ld a,(esp_st + ST_RATE + 2)         ; rates above 65535 Hz: both / 4
    or a
    ld hl,(esp_st + ST_PLAYED) : ld (dvd),hl
    ld hl,(esp_st + ST_PLAYED + 2) : ld (dvd+2),hl
    ld bc,(esp_st + ST_RATE)
    jr z,.div
    ld hl,(esp_st + ST_RATE + 1)        ; rate / 4 (rate < 2^18)
    ld a,(esp_st + ST_RATE)
    srl h : rr l : rra
    srl h : rr l : rra
    ld b,l
    ld c,a
    ld hl,dvd+3
    srl (hl) : dec hl : rr (hl) : dec hl : rr (hl) : dec hl : rr (hl)
    ld hl,dvd+3
    srl (hl) : dec hl : rr (hl) : dec hl : rr (hl) : dec hl : rr (hl)
.div:
    call div32_16
    ld hl,(dvd)
    ld bc,(esp_base)
    add hl,bc
    ret

;; Total seconds from the ESP (WAV, FLAC): total / rate. OUT: HL, CF = 1 not known
esp_total:
    ld hl,(esp_st + ST_TOTAL)
    ld a,h : or l
    ld hl,(esp_st + ST_TOTAL + 2)
    or h : or l
    scf
    ret z
    ld hl,(esp_st + ST_TOTAL) : ld (dvd),hl
    ld hl,(esp_st + ST_TOTAL + 2) : ld (dvd+2),hl
    ld bc,(esp_st + ST_RATE)
    ld a,(esp_st + ST_RATE + 2)
    or a
    jr z,.div
    ld hl,(esp_st + ST_RATE + 1)
    ld a,(esp_st + ST_RATE)
    srl h : rr l : rra
    srl h : rr l : rra
    ld b,l
    ld c,a
    ld hl,dvd+3
    srl (hl) : dec hl : rr (hl) : dec hl : rr (hl) : dec hl : rr (hl)
    ld hl,dvd+3
    srl (hl) : dec hl : rr (hl) : dec hl : rr (hl) : dec hl : rr (hl)
.div:
    ld a,b : or c
    scf
    ret z
    call div32_16
    ld hl,(dvd)
    or a
    ret

;; The format from the extension of fname: A = A_FMT_*
ext_fmt:
    ld hl,fname
    ld de,0                     ; DE = after the last '.'
.scan:
    ld a,(hl)
    or a
    jr z,.got
    inc hl
    cp '.'
    jr nz,.scan
    ld d,h
    ld e,l
    jr .scan
.got:
    ld a,d : or e
    ld a,A_FMT_AUTO
    ret z
    ex de,hl
    ld a,(hl) : or #20 : ld b,a
    inc hl
    ld a,(hl) : or #20 : ld c,a
    inc hl
    ld a,(hl) : or #20 : ld e,a
    ld a,b
    cp 'm' : jr nz,.w
    ld a,A_FMT_MP3 : ret
.w: cp 'w' : jr nz,.o
    ld a,A_FMT_WAV : ret
.o: cp 'o' : jr nz,.f
    ld a,A_FMT_OGG : ret
.f: cp 'f' : jr nz,.a
    ld a,A_FMT_FLAC : ret
.a: ld a,A_FMT_AUTO
    ret

;; Firmware version into DE, "ZiFi32 a.b.c, API n": OUT: DE at the 0
esp_ver:
    push de
    ld a,E_CMD_GET_VER
    call esp_run
    ld d,#02                    ; ESP_REG_API, FEAT (2), VER0..2
    ld hl,esp_tmp4
    ld b,6
    call esp_rd
    pop de
    ld hl,s_e_ver
    call sapp
    ld a,(esp_tmp4+3)
    call .dec
    ld a,'.' : ld (de),a : inc de
    ld a,(esp_tmp4+4)
    call .dec
    ld a,'.' : ld (de),a : inc de
    ld a,(esp_tmp4+5)
    call .dec
    ld hl,s_e_api
    call sapp
    ld a,(esp_tmp4)
    call .dec
    xor a
    ld (de),a
    ret
.dec:
    ld l,a
    ld h,0
    jp utoa16

s_e_ver:    db "ZiFi32 ",0
s_e_api:    db ", API ",0

;; ---------------------------------------------------------------------------
;; The window

;; Once per frame from frame_tick: when the ESP has opened the stream, the
;; stream line and the length; a failure of the ESP: say it, then go on.
esp_fmt_update:
    ld a,(esp_st + ST_STATE)
    cp A_ST_ERROR
    jr z,.err
    ld a,(esp_fmt_shown)
    or a
    ret nz
    ld a,(esp_st + ST_FMT)
    or a
    ret z
    ld a,1
    ld (esp_fmt_shown),a
    ld a,(esp_fmt)
    cp A_FMT_MP3
    ret z                       ; MP3: the line and the length of mpeg_scan
    call esp_total
    jr c,.line
    ld (total_sec),hl
.line:
    call build_fmt
    ld hl,fmtbuf
    ld de,Y_FMT*256 + 2
    ld c,WIN_W - 3
    ld a,CLR_VALUE
    call prn_fld
    jp ui_total
.err:
    ld a,(esp_fmt_shown)
    cp 2
    jr z,.wait
    ld a,2
    ld (esp_fmt_shown),a
    xor a
    ld (err_wait),a
    ld de,fmtbuf
    ld hl,s_e_fail
    call sapp
    ld a,(esp_st + ST_ERROR)
    call hex8
    xor a
    ld (de),a
    ld hl,fmtbuf
    ld de,Y_FMT*256 + 2
    ld c,WIN_W - 3
    ld a,CLR_VALUE
    jp prn_fld
.wait:
    ld hl,err_wait              ; on the screen a while, then the next file
    inc (hl)
    ld a,(hl)
    cp ERR_FRAMES
    ret c
    ld a,EXIT_END
    ld (exit_req),a
    ret

;; Stream line of WAV / FLAC / Ogg: "FLAC  44.1 kHz  16 bit  Stereo"; DE = fmtbuf
esp_build_fmt:
    ld a,(esp_st + ST_FMT)
    or a
    ld hl,s_e_wait
    jr z,.name
    ld hl,s_e_wav
    cp A_FMT_WAV
    jr z,.name
    ld hl,s_e_ogg
    cp A_FMT_OGG
    jr z,.name
    ld hl,s_e_flac
    cp A_FMT_FLAC
    jr z,.name
    ld hl,s_e_mp3
.name:
    call sapp
    ld a,(esp_st + ST_FMT)
    or a
    jr z,.end
    ld hl,s_2sp
    call sapp
    ; rate in kHz: rate / 1000, two decimals, trailing zeros dropped
    push de
    ld hl,(esp_st + ST_RATE) : ld (dvd),hl
    ld hl,(esp_st + ST_RATE + 2) : ld (dvd+2),hl
    ld bc,1000
    call div32_16
    ld c,10
    call div16_8                ; HL = hundredths 0..99
    ld a,l
    ld (tmpb),a
    pop de
    ld hl,(dvd)
    call utoa16
    ld a,(tmpb)
    or a
    jr z,.khz
    ld b,a
    ld a,'.'
    ld (de),a
    inc de
    ld a,b
    ld c,'0'-1
.t:
    inc c
    sub 10
    jr nc,.t
    add a,10+'0'
    ex de,hl
    ld (hl),c
    inc hl
    ex de,hl
    cp '0'
    jr z,.khz
    ld (de),a
    inc de
.khz:
    ld hl,s_khz
    call sapp
    ld a,(esp_st + ST_BITS)
    or a
    jr z,.ch
    ld l,a
    ld h,0
    call utoa16
    ld hl,s_e_bit
    call sapp
.ch:
    ld a,(esp_st + ST_CHANNELS)
    ld hl,s_m3                  ; Mono
    cp 1
    jr z,.chn
    ld hl,s_m0                  ; Stereo
    cp 2
    jr z,.chn
    ld l,a
    ld h,0
    call utoa16
    ld hl,s_e_ch
.chn:
    call sapp
.end:
    xor a
    ld (de),a
    ret

;; What the ESP answered, then wait for a key (from the F10 menu, or when it
;; has no player). IN: CF from probe (1 = none)
diag:
    push af
    ld hl,inf_tpl
    ld de,wnd
    ld bc,WND_SIZE
    ldir
    ld a,(WC_HEI)
    ld b,a
    sub INF_H
    srl a
    ld (wnd+3),a
    ld c,(80 - INF_W) / 2
    ld a,b
    cp 36
    jr nz,.wx
    ld c,(90 - INF_W) / 2
.wx:
    ld a,c
    ld (wnd+2),a
    WCALL WCF_GEDPL
    ld ix,wnd
    WCALL WCF_PRWOW
    ld hl,s_head
    ld de,0*256 + (INF_W - S_HEAD_LEN) / 2
    ld bc,S_HEAD_LEN
    ld a,CLR_HEAD
    call prn
    ; "ESP32 answer (AUDIO_GET_STATE): #01"
    ld de,linebuf
    ld hl,s_e_ans
    call sapp
    ld a,(esp_ans)
    call hex8
    xor a
    ld (de),a
    ld hl,linebuf
    ld de,2*256 + 2
    ld a,CLR_VALUE
    call prn_z
    pop af
    push af
    ld hl,s_e_ok
    jr nc,.why
    ld a,(esp_ans)
    ld hl,s_e_old
    cp E_ERR_INV_CMD
    jr z,.why
    ld hl,s_e_none
    cp #FF
    jr z,.why
    ld hl,s_e_odd
.why:
    ld de,3*256 + 2
    ld a,CLR_VALUE
    call prn_z
    pop af
    jr c,.key
    ld de,linebuf
    ld hl,s_d_fw
    call sapp
    call esp_ver
    ld hl,linebuf
    ld de,4*256 + 2
    ld a,CLR_VALUE
    call prn_z
    ld hl,s_e_use
    ld de,5*256 + 2
    ld a,CLR_LABEL
    call prn_z
.key:
    ld hl,s_d_key
    ld de,7*256 + 2
    ld a,CLR_KEYS
    call prn_z
    call wait_key
    WCALL WCF_USPO
    ld ix,wnd
    WCALL WCF_RRESB
    ret

s_e_wait:   db "Waiting for the ESP32 to open the stream",0
s_e_wav:    db "WAV",0
s_e_ogg:    db "Ogg Vorbis",0
s_e_flac:   db "FLAC",0
s_e_mp3:    db "MPEG audio",0
s_e_bit:    db " bit  ",0
s_e_ch:     db " channels",0
s_e_fail:   db "The ESP32 cannot play this file, error ",0
s_e_ans:    db "ESP32 answer (AUDIO_GET_STATE): #",0
s_e_ok:     db "Audio player of ZiFi32 found",0
s_e_old:    db "No audio player in this ZiFi32: update the ESP32",0
s_e_none:   db "No answer: no ESP32 on the SPI of the core",0
s_e_odd:    db "Unexpected answer: the ESP32 is busy or hangs",0
s_e_use:    db "Press Enter on a .mp3 .wav .ogg .flac file to play it",0
