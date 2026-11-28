;; Player window. Coordinates are inside the window: (0,0) is the frame
;; corner, the text area is x = 1..WIN_W-2, y = 1..WIN_H-2.

WIN_W           equ 64
WIN_H           equ 18
WIN_X           equ (80 - WIN_W) / 2

Y_FILE          equ 1
Y_TITLE         equ 3
Y_ARTIST        equ 4
Y_ALBUM         equ 5
Y_YEAR          equ 6
Y_FMT           equ 8
Y_DEC           equ 9
Y_PROG          equ 11
Y_STAT          equ 12          ; rows 12 and 13 are kept for the L/R peaks
Y_BUF           equ 14
Y_KEYS          equ 16

X_VAL           equ 10          ; values of File / Title / Artist / Album
W_VAL           equ WIN_W - 1 - X_VAL
X_BAR           equ 10
W_BAR           equ 46
X_TOTAL         equ X_BAR + W_BAR + 1

; colours: paper in bits 7:4, ink in bits 3:0 (the GS Player look)
CLR_WIN         equ %01111111
CLR_HEAD        equ %11110111
CLR_LABEL       equ %01110001
CLR_VALUE       equ %01111110
CLR_TIME        equ %01110000
CLR_BAR         equ %01110001
CLR_KEYS        equ %01110000

CH_FULL         equ #DB         ; CP866 block characters
CH_EMPTY        equ #B0
CH_LINE         equ #C4
ICON_PLAY       equ #10
ICON_PAUSE      equ #BA
ICON_END        equ #FE

;; HL = text, D = y, E = x, BC = length, A = colour
prn:
    push af
    ld ix,wnd
    WCALL WCF_PRSRW
    pop af
    ex af,af'
    WCALL WCF_PRIAT
    ret

;; HL = 0-terminated text, D = y, E = x, A = colour
prn_z:
    push af
    call strlen
    ld a,b
    or c
    jr z,.none
    pop af
    jr prn
.none:
    pop af
    ret

;; HL = 0-terminated text, D = y, E = x, C = field width, A = colour.
;; Pads with spaces, marks a cut with '~'.
prn_fld:
    push af
    push de
    ld de,linebuf
    ld b,c
.copy:
    ld a,(hl)
    or a
    jr z,.pad
    ld (de),a
    inc hl
    inc de
    djnz .copy
    ld a,(hl)
    or a
    jr z,.out
    dec de
    ld a,'~'
    ld (de),a
    jr .out
.pad:
    ld a,' '
.padl:
    ld (de),a
    inc de
    djnz .padl
.out:
    pop de
    pop af
    ld hl,linebuf
    ld b,0
    jr prn

;; A = filled cells, C = width -> bar in linebuf, then printed at D, E
prn_bar:
    push de
    ld hl,linebuf
    ld b,c
    ld e,a
.loop:
    ld a,e
    or a
    ld a,CH_EMPTY
    jr z,.put
    dec e
    ld a,CH_FULL
.put:
    ld (hl),a
    inc hl
    djnz .loop
    pop de
    ld hl,linebuf
    ld b,0
    ld a,CLR_BAR
    jr prn

ui_draw_all:
    ld ix,wnd
    WCALL WCF_PRWOW
    ld hl,s_head
    ld de,0*256 + (WIN_W - S_HEAD_LEN) / 2
    ld bc,S_HEAD_LEN
    ld a,CLR_HEAD
    call prn
    ld b,4
    ld hl,sep_rows
.sep:
    push bc
    push hl
    ld d,(hl)
    ld e,1
    ld hl,s_line
    ld bc,WIN_W-2
    ld a,CLR_WIN
    call prn
    pop hl
    pop bc
    inc hl
    djnz .sep
    ; labels
    ld hl,labels
.lab:
    ld a,(hl)
    cp #FF
    jr z,.vals
    ld d,a
    inc hl
    ld e,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    push hl
    ld h,b
    ld l,c
    ld a,CLR_LABEL
    call prn_z
    pop hl
    jr .lab
.vals:
    ld hl,fname
    ld de,Y_FILE*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_title
    ld a,(id3_found)
    or a
    jr nz,.tit
    ld hl,s_notag
    ld a,(esp_fmt)
    cp A_FMT_MP3
    jr z,.tit
    ld hl,s_empty               ; WAV / Ogg / FLAC: no ID3v2 to miss
.tit:
    ld de,Y_TITLE*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_artist
    ld a,(hl)
    or a
    jr nz,.art
    ld hl,f_aartist
.art:
    ld de,Y_ARTIST*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_album
    ld de,Y_ALBUM*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_year
    ld de,Y_YEAR*256 + 10
    ld c,4
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_track
    ld de,Y_YEAR*256 + 27
    ld c,8
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_genre
    ld de,Y_YEAR*256 + 45
    ld c,WIN_W - 1 - 45
    ld a,CLR_VALUE
    call prn_fld
    call build_fmt
    ld hl,fmtbuf
    ld de,Y_FMT*256 + 2
    ld c,WIN_W - 3
    ld a,CLR_VALUE
    call prn_fld
    ld hl,s_keys
    ld de,Y_KEYS*256 + 1
    ld a,CLR_KEYS
    call prn_z
    call ui_list
    ; total time
ui_total:
    ld hl,(total_sec)           ; 0: not known (yet)
    ld a,h : or l
    jr nz,.tt
    ld hl,#FFFF
.tt:
    ld de,tbuf
    call fmt_time
    ld hl,tbuf
    ld de,Y_PROG*256 + X_TOTAL
    ld bc,5
    ld a,CLR_TIME
    call prn
    ld a,(esp_fmt_shown)        ; ui_total from esp_fmt_update: only that
    or a
    ret nz
    call ui_dec
    call ui_status
    call ui_prog
    jp ui_buf

;; Decoder and volume
ui_dec:
    ld hl,s_esp
    ld de,Y_DEC*256 + 11
    ld c,7
    ld a,CLR_VALUE
    call prn_fld
    ; volume bar: 10 cells, one per 4 dB
    ld a,(vol)
    rrca : rrca : rrca
    and #1F
    cp 10
    jr c,.vb
    ld a,10
.vb:
    ld b,a
    ld a,10
    sub b
    ld de,Y_DEC*256 + 25
    ld c,10
    call prn_bar
    ; "-N.5dB"
    ld de,tbuf
    ld a,(vol)
    or a
    jr z,.v0
    ld a,'-'
    ld (de),a
    inc de
    ld a,(vol)
    srl a
    ld l,a
    ld h,0
    call utoa16
    ld a,(vol)
    rrca
    jr nc,.db
    ld a,'.' : ld (de),a : inc de
    ld a,'5' : ld (de),a : inc de
    jr .db
.v0:
    ld a,'0' : ld (de),a : inc de
.db:
    ld a,'d' : ld (de),a : inc de
    ld a,'B' : ld (de),a : inc de
    xor a
    ld (de),a
    ld hl,tbuf
    ld de,Y_DEC*256 + 36
    ld c,7
    ld a,CLR_VALUE
    jp prn_fld

;; Play list: "List: 3 / 12" under the status
ui_list:
    ld a,(pl_mode)
    or a
    ret z
    ld de,lstbuf
    ld hl,s_list
    call sapp
    ld hl,(pl_idx)
    inc hl
    call utoa16
    ld hl,s_of
    call sapp
    ld hl,(pl_count)
    call utoa16
    xor a
    ld (de),a
    ld hl,lstbuf
    ld de,(Y_STAT+1)*256 + 2
    ld c,30
    ld a,CLR_LABEL
    jp prn_fld

;; Paused / end of track / connecting message
ui_status:
    ld hl,s_empty
    ld a,(eof)
    or a
    jr z,.c
    ld hl,s_end
.c:
    ld a,(radio)
    or a
    jr z,.p
    ld a,(esp_st + ST_FLAGS)
    and A_FLAG_CONNECT
    jr z,.p
    ld hl,s_conn
.p:
    ld a,(paused)
    or a
    jr z,.out
    ld hl,s_paused
.out:
    ld de,Y_STAT*256 + 2
    ld c,30
    ld a,CLR_VALUE
    jp prn_fld

;; Icon, elapsed time and the progress bar
ui_prog:
    ld a,ICON_PLAY
    ld b,a
    ld a,(paused)
    or a
    jr z,.np
    ld b,ICON_PAUSE
.np:
    ld a,(eof)
    or a
    jr z,.ne
    ld b,ICON_END
.ne:
    ld a,b
    ld (tbuf),a
    ld hl,tbuf
    ld de,Y_PROG*256 + 2
    ld bc,1
    ld a,CLR_TIME
    call prn
    ; elapsed: from the samples the ESP has played
    call play_pos
    ld (ppos),hl
    ld (ppos+2),de
    call esp_elapsed
    ld (step),hl
    ld de,tbuf
    call fmt_time
    ld hl,tbuf
    ld de,Y_PROG*256 + 4
    ld bc,5
    ld a,CLR_TIME
    call prn
    ; bar = elapsed * W_BAR / total_sec, or by the bytes without a length
    ld hl,(total_sec)
    ld a,h : or l
    jr z,.bytes
    ld hl,(step)
    ld a,h : and l
    inc a
    ld a,0
    jr z,.ebar
    ld (m32),hl
    ld hl,0
    ld (m32+2),hl
    ld bc,W_BAR
    call mul32_16
    call st_dvd
    ld bc,(total_sec)
    call div32_16
    ld a,(dvd)
    cp W_BAR
    jr c,.ebar
    ld a,W_BAR
.ebar:
    ld de,Y_PROG*256 + X_BAR
    ld c,W_BAR
    jp prn_bar
.bytes:
    ; bar = ppos * W_BAR / alen; both are shifted right together
    ; until alen fits in 16 bits (files of any size up to 4 GB)
.bar_bytes:
    ld hl,(ppos) : ld (m32),hl
    ld hl,(ppos+2) : ld (m32+2),hl
    ld hl,(alen)
    ld de,(alen+2)
.norm:
    ld a,d : or e
    jr z,.normd
    srl d : rr e : rr h : rr l
    ld a,(m32+3) : srl a : ld (m32+3),a
    ld a,(m32+2) : rra : ld (m32+2),a
    ld a,(m32+1) : rra : ld (m32+1),a
    ld a,(m32) : rra : ld (m32),a
    jr .norm
.normd:
    ld a,h : or l
    ld a,0
    jr z,.bar
    ; position far past the end (m32 * W_BAR would overflow): full bar
    ld a,(m32+3)
    or a
    ld a,W_BAR
    jr nz,.bar
    push hl
    ld bc,W_BAR
    call mul32_16
    call st_dvd
    pop bc
    call div32_16
    ld a,(dvd+1)
    or a
    ld a,W_BAR
    jr nz,.bar
    ld a,(dvd)
    cp W_BAR
    jr c,.bar
    ld a,W_BAR
.bar:
    ld de,Y_PROG*256 + X_BAR
    ld c,W_BAR
    jp prn_bar

;; Buffer of the ESP: bar of 8 cells and percent
ui_buf:
    call esp_fill
    ld (tmpb),a
    add a,8
    rrca : rrca : rrca : rrca
    and #0F
    cp 9
    jr c,.b
    ld a,8
.b:
    ld de,Y_BUF*256 + 6
    ld c,8
    call prn_bar
    ld a,(tmpb)
    call pct
    ld de,tbuf
    call utoa16
    ld a,'%'
    ld (de),a
    inc de
    xor a
    ld (de),a
    ld hl,tbuf
    ld de,Y_BUF*256 + 15
    ld c,4
    ld a,CLR_VALUE
    jp prn_fld

;; A = used blocks (0..128) -> HL = A * 100 / 128
pct:
    ld l,a
    ld h,0
    ld d,h
    ld e,l
    add hl,hl                   ; *2
    add hl,hl                   ; *4
    add hl,de                   ; *5
    ld d,h
    ld e,l
    add hl,hl                   ; *10
    add hl,hl                   ; *20
    add hl,de                   ; *25
    srl h : rr l                ; /2
    srl h : rr l                ; /4
    srl h : rr l                ; /8
    srl h : rr l                ; /16
    srl h : rr l                ; /32  -> used * 25 / 32
    ret

;; Stream line: "MPEG-1 Layer III  192 kbps CBR  44.1 kHz  Joint Stereo"
build_fmt:
    ld de,fmtbuf
    ld a,(esp_fmt)
    cp A_FMT_MP3
    jp nz,esp_build_fmt
    ld a,(fmt_ok)
    or a
    jr nz,.ok
    ld hl,s_nofmt
    call sapp
    xor a
    ld (de),a
    ret
.ok:
    ld hl,s_mpeg
    call sapp
    ld a,(m_ver)
    ld hl,s_v25
    or a
    jr z,.v
    ld hl,s_v2
    cp 2
    jr z,.v
    ld hl,s_v1
.v:
    call sapp
    ld hl,s_layer
    call sapp
    ld a,(m_lay)
    ld hl,s_l3
    cp 1
    jr z,.l
    ld hl,s_l2
    cp 2
    jr z,.l
    ld hl,s_l1
.l:
    call sapp
    ld hl,s_2sp
    call sapp
    ; bitrate: the header one, or the average for VBR
    ld hl,(m_br)
    ld a,(is_vbr)
    or a
    jr z,.br
    push de
    ld hl,(bps)
    ld (dvd),hl
    ld hl,0
    ld (dvd+2),hl
    ld bc,125
    call div32_16
    ld hl,(dvd)
    pop de
.br:
    call utoa16
    ld hl,s_kbps
    call sapp
    ld hl,s_cbr
    ld a,(is_vbr)
    or a
    jr z,.c
    ld hl,s_vbr
.c:
    call sapp
    ld hl,s_2sp
    call sapp
    ; sample rate in kHz, trailing zeros dropped
    push de
    ld hl,(m_sr)
    ld (dvd),hl
    ld hl,0
    ld (dvd+2),hl
    ld bc,1000
    call div32_16               ; HL = remainder, 0..999
    ld c,10
    call div16_8                ; HL = two decimal digits, 0..99
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
    add a,10+'0'                ; A = hundredths, C = tenths
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
    ld a,(m_mode)
    add a,a
    ld c,a
    ld b,0
    ld hl,mode_names
    add hl,bc
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    call sapp
    xor a
    ld (de),a
    ret

;; ---------------------------------------------------------------------------
;; Diagnostic window (diag in esp.asm): what the ESP answered
;; ---------------------------------------------------------------------------
INF_W           equ 58
INF_H           equ 9

;; HL = a message in the small window, then a key; back to WC (WCX_ESC)
pl_fail:
    push hl
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
    pop hl
    ld de,2*256 + 2
    ld a,CLR_VALUE
    call prn_z
    ld hl,s_d_key
    ld de,7*256 + 2
    ld a,CLR_KEYS
    call prn_z
    call wait_key
    call keys_up
    ld ix,wnd
    WCALL WCF_RRESB
    xor a                       ; WCX_ESC
    ret

s_pl_empty: db "No files in this play list",0

inf_tpl:
    db 0, 0, 0, 0, INF_W, INF_H, CLR_WIN, 0
    dw 0
    db 0, 0, 1, 0, 0, 0

s_d_key:    db "Press any key",0
s_d_fw:     db "Firmware: ",0

;; Window: type 0, frame, no cursor. Copied to wnd before every run.
wnd_tpl:
    db 0, 0, WIN_X, 0, WIN_W, WIN_H, CLR_WIN, 0
    dw 0
    db 0, 0, 1, 0, 0, 0
WND_SIZE        equ $ - wnd_tpl

sep_rows:   db 2, 7, 10, 15

labels:
    db Y_FILE,   2 : dw s_l_file
    db Y_TITLE,  2 : dw s_l_title
    db Y_ARTIST, 2 : dw s_l_artist
    db Y_ALBUM,  2 : dw s_l_album
    db Y_YEAR,   2 : dw s_l_year
    db Y_YEAR,  20 : dw s_l_track
    db Y_YEAR,  38 : dw s_l_genre
    db Y_DEC,    2 : dw s_l_dec
    db Y_DEC,   20 : dw s_l_vol
    db Y_BUF,    2 : dw s_l_buf
    db #FF

s_head:     db " ZiFi32 Audio Player v", VERSION, " "
S_HEAD_LEN  equ $ - s_head
s_line:     ds WIN_W-2, CH_LINE
s_l_file:   db "File:",0
s_l_title:  db "Title:",0
s_l_artist: db "Artist:",0
s_l_album:  db "Album:",0
s_l_year:   db "Year:",0
s_l_track:  db "Track:",0
s_l_genre:  db "Genre:",0
s_l_dec:    db "Decoder:",0
s_l_vol:    db "Vol:",0
s_l_buf:    db "Buf",0
s_list:     db "List: ",0
s_of:       db " / ",0
s_keys:     db "Spc:next P:prev <>:seek S:pause +-:vol Esc:exit",0
s_esp:      db "ESP32",0
s_notag:    db "(no ID3v2 tag)",0
s_paused:   db "Paused",0
s_conn:     db "Connecting...",0
s_end:      db "End of track",0
s_empty:    db 0
s_notime:   db "--:--"
s_nofmt:    db "No MPEG audio frames found",0
s_mpeg:     db "MPEG-",0
s_v1:       db "1",0
s_v2:       db "2",0
s_v25:      db "2.5",0
s_layer:    db " Layer ",0
s_l1:       db "I",0
s_l2:       db "II",0
s_l3:       db "III",0
s_2sp:      db "  ",0
s_kbps:     db " kbps ",0
s_cbr:      db "CBR",0
s_vbr:      db "VBR",0
s_khz:      db " kHz  ",0
mode_names: dw s_m0, s_m1, s_m2, s_m3
s_m0:       db "Stereo",0
s_m1:       db "Joint Stereo",0
s_m2:       db "Dual Channel",0
s_m3:       db "Mono",0
