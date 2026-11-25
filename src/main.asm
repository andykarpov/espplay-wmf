;; ESPPLAY.WMF - Wild Commander plugin that plays MP3, WAV, Ogg Vorbis and
;; FLAC on the ESP32 of TS-Conf (ZiFi32 with the audio stream player,
;; ESP_CMD_AUDIO_*): the plugin reads the file and pushes it over the SPI, the
;; ESP decodes it and mixes it into its sound output.
;;
;; Build: sjasmplus --inc=src src/main.asm  ->  ESPPLAY.WMF

    DEFINE VERSION "1.0.1"

CPU_CLOCK       equ 2           ; TURBOPL: 0 = 3.5, 1 = 7, 2 = 14 MHz
SEEK_SEC        equ 10          ; seconds per <- / ->
VOL_STEP        equ 4           ; 2 dB
VOL_START       equ 8           ; -4 dB
ERR_FRAMES      equ 100         ; an error of the ESP stays on the screen 2 s

    include "wcdefs.asm"

    OUTPUT "ESPPLAY.WMF"

;; ---------------------------------------------------------------------------
;; Plugin header, 512 bytes (plugin system #10)
;; ---------------------------------------------------------------------------
    ORG 0
header:
    ds 16                                   ; +0
    db "WildCommanderMDL"                   ; +16
    db #10                                  ; +32 format version
    db 0                                    ; +33
    db 1                                    ; +34 pages
    db 0                                    ; +35 page at #8000
    db 0, (code_end - #8000 + 511) / 512    ; +36 block: page 0, 512-byte sectors
    ds 5*2                                  ;     no more blocks
    ds 15                                   ; +48
    db 0                                    ; +63 run by ENTER and F3
    db "MP3", "WAV", "OGG", "FLA"           ; +64 extensions (FLA: what WC takes of .flac)
    ds 28*3
    db 0                                    ; +160
    dd #FFFFFFFF                            ; +161 any file size
name_start:
    db "ZiFi32 Audio Player v", VERSION     ; +165 name, 32 chars
    ds 32 - ($ - name_start), ' '
    db #05                                  ; +197 also from F10 and Shift+F3
    ds 6                                    ; +198 F2 / F4 text (unused)
viewer_start:
    db "Play on ESP32"                      ; +204 Shift+F3 menu, 24 chars
    ds 24 - ($ - viewer_start), ' '
    ds 512 - ($ - header)
    ASSERT $ == 512

;; ---------------------------------------------------------------------------
;; Code, page 0 at #8000
;; ---------------------------------------------------------------------------
    ORG #8000

;; IN: A = call type, DEHL = file size, BC = file name, IX = panel,
;;     DE' = files in the panel, HL' = this file's number (from 1)
entry:
    ld (entry_sp),sp
    ld (panel_ix),ix
    ld (file_size),hl
    ld (file_size+2),de
    ld (name_ptr),bc
    exx
    ld (wc_count),de
    ld (wc_index),hl
    exx
    ld (call_type),a
    or a
    jr z,.byext
    cp 4
    jr z,.byext                 ; chosen in the Shift+F3 menu
    ; from the F10 menu: show what the ESP answers
    call probe
    call diag
    xor a                       ; WCX_ESC
    ret
.byext:
    ; copy the name before any WC call can move it
    ld hl,(name_ptr)
    ld de,fname
    ld bc,255
.name:
    ld a,(hl)
    ld (de),a
    or a
    jr z,.named
    inc hl
    inc de
    dec bc
    ld a,b
    or c
    jr nz,.name
    xor a
    ld (de),a
.named:
    call probe
    jr nc,.found
    call diag                   ; say why
    ld a,(call_type)
    or a
    ld a,WCX_NOTMINE            ; Enter: WC opens its Shift+F3 menu
    ret z
    xor a                       ; WCX_ESC
    ret
.found:
    ; code and data stay loaded between runs: set everything up again
    xor a
    ld (paused),a
    ld (eof),a
    ld (err_wait),a
    ld (exit_req),a
    ld (fcnt),a
    ld hl,wnd_tpl
    ld de,wnd
    ld bc,WND_SIZE
    ldir
    ld a,(WC_HEI)
    ld b,a
    sub WIN_H
    srl a
    ld (wnd+3),a
    ld a,(90 - WIN_W) / 2       ; the 36-line mode is 90 columns wide
    ld c,a
    ld a,b
    cp 36
    jr z,.wx
    ld c,(80 - WIN_W) / 2
.wx:
    ld a,c
    ld (wnd+2),a

    xor a
    ld (esp_fmt_shown),a
    call esp_start
    jr nc,.started
    call diag                   ; the ESP refused the stream: say what it answered
    xor a                       ; WCX_ESC
    ret
.started:
    call rd_init
    ; tags and frames: MP3 only; the others go to the ESP from byte 0
    xor a
    ld (id3_found),a
    ld (fmt_ok),a
    ld hl,0
    ld (bps),hl
    ld (total_sec),hl
    ld (audio_start),hl
    ld (audio_start+2),hl
    ld (f_title),a              ; no tags unless an MP3 has them
    ld (f_artist),a
    ld (f_aartist),a
    ld (f_album),a
    ld (f_year),a
    ld (f_track),a
    ld (f_genre),a
    ld a,(esp_fmt)
    cp A_FMT_MP3
    jr z,.mp3
    ld hl,(file_size) : ld (alen),hl
    ld hl,(file_size+2) : ld (alen+2),hl
    jr .seekst
.mp3:
    call id3_parse
    ; alen = file_size - audio_start, kept if no frame is found
    ld hl,(file_size) : ld bc,(audio_start) : or a : sbc hl,bc : ld (alen),hl
    ld hl,(file_size+2) : ld bc,(audio_start+2) : sbc hl,bc : ld (alen+2),hl
    jr nc,.alen
    ld hl,0
    ld (alen),hl
    ld (alen+2),hl
    ld hl,(file_size) : ld (audio_start),hl
    ld hl,(file_size+2) : ld (audio_start+2),hl
.alen:
    call mpeg_scan
.seekst:
    ld hl,(audio_start)
    ld de,(audio_start+2)
    call rd_seek

    WCALL WCF_GEDPL
    call ui_draw_all
    WCALL WCF_USPO              ; the ENTER that started us must be released
    ld hl,(WC_TMN)
    ld (last_tmn),hl

;; ---------------------------------------------------------------------------
main_loop:
    ei
    ld a,(exit_req)
    or a
    jp nz,do_exit
    ld a,(paused)
    ld b,a
    ld a,(eof)
    or b
    jr nz,.idle
    call feed
    jr nc,.idle
    ld a,1
    ld (eof),a
    call ui_status
.idle:
    ld hl,(WC_TMN)
    ld de,(last_tmn)
    or a
    sbc hl,de
    jr z,main_loop
    add hl,de
    ld (last_tmn),hl
    call keys
    call frame_tick
    jr main_loop

;; Once per frame: redraw a part of the window, watch the end of the track
frame_tick:
    call esp_tick
    ld hl,fcnt
    inc (hl)
    ld a,(hl)
    cp 5
    call z,ui_buf
    ld a,(fcnt)
    cp 10
    jr c,.end
    xor a
    ld (fcnt),a
    call ui_prog
.end:
    call esp_fmt_update         ; the stream line once the ESP knows the format
    ld a,(eof)
    or a
    ret z
    call esp_end                ; once: the ESP plays out what it holds
    ld a,(esp_ended)
    or a
    ret z
    ld a,EXIT_END
    ld (exit_req),a
    ret

;; Push as much of the buffer to the ESP as it has room for.
;; OUT: CF = 1 when the whole file has been sent
feed:
    call esp_free               ; HL = bytes the ESP takes, 0..BUFSZ
    ld a,h : or l
    ret z
    ld (feed_max),hl
.again:
    ld hl,(buf_len)
    ld de,(rd_off)
    or a
    sbc hl,de
    jr nz,.have
    call rd_refill
    jr nz,.again
    scf
    ret
.have:
    ex de,hl                    ; DE = bytes left in the buffer
    ld hl,(feed_max)
    or a
    sbc hl,de
    add hl,de
    jr c,.n                     ; HL = min(free, left)
    ex de,hl
.n:
    ld b,h
    ld c,l
    ld hl,(rd_off)
    push hl
    add hl,bc
    ld (rd_off),hl
    pop hl
    ld de,BUF
    add hl,de
    ld d,b
    ld e,c
    push bc
    call esp_push
    pop bc
    jr nc,.sent
    ld hl,(rd_off)              ; refused: send it again later
    or a
    sbc hl,bc
    ld (rd_off),hl
.sent:
    or a
    ret

;; Find the ESP and its player, at 14 MHz (the SPI of TS-Conf runs at any clock)
;; OUT: CF = 1 if there is none
probe:
    ld bc,CPU_CLOCK             ; B = 0: set the clock
    WCALL WCF_TURBOPL
    jp esp_detect

;; Wait for Esc, Enter, Space or a letter
wait_key:
    WCALL WCF_USPO
.loop:
    ei
    call key_esc   : ret nz
    call key_enter : ret nz
    call key_space : ret nz
    call key_char  : ret nz
    jr .loop

;; ---------------------------------------------------------------------------
;; Keys, polled once per frame
;; ---------------------------------------------------------------------------
keys:
    call key_esc   : jp nz,.esc
    call key_space : jp nz,.next
    call key_enter : jp nz,.next
    call key_bspc  : jp nz,.prev
    call key_left  : jp nz,seek_back
    call key_right : jp nz,seek_fwd
    call key_up    : jp nz,vol_up
    call key_down  : jp nz,vol_down
    call key_char
    ret z
    cp 'p' : jr z,.prev
    cp 's' : jr z,pause
    cp '+' : jp z,vol_up
    cp '=' : jp z,vol_up
    cp '-' : jp z,vol_down
    ret
.esc:
    ld a,EXIT_ESC
    jr .set
.next:
    ld a,EXIT_NEXT
    jr .set
.prev:
    ld a,EXIT_PREV
.set:
    ld (exit_req),a
    ret

pause:
    ld a,(paused)
    xor 1
    ld (paused),a
    call esp_pause
    call ui_status
    jp ui_prog

vol_up:
    ld a,(vol)
    sub VOL_STEP
    jr nc,vol_set
    xor a
    jr vol_set
vol_down:
    ld a,(vol)
    add a,VOL_STEP
    jr c,.max
    cp #FE
    jr c,vol_set
.max:
    ld a,#FE
vol_set:
    ld (vol),a
    call esp_volume
    jp ui_dec

;; ---------------------------------------------------------------------------
;; Seeking: SEEK_SEC seconds from the time the ESP has played; the byte offset
;; in proportion: audio_start + t * alen / total_sec. Not for Ogg (the ESP
;; says what it can seek) or without a length.
;; ---------------------------------------------------------------------------
;; OUT: CF = 1 no seek
esp_can_seek:
    ld a,(esp_st + ST_FLAGS)
    and A_FLAG_SEEKABLE
    scf
    ret z
    ld hl,(total_sec)
    ld a,h : or l
    scf
    ret z
    or a
    ret

;; OUT: HL = seconds played (0 if not known)
esp_now:
    call esp_elapsed
    ld a,h : and l
    inc a
    ret nz
    ld hl,0
    ret

seek_fwd:
    call esp_can_seek
    ret c
    call esp_now
    ld bc,SEEK_SEC
    add hl,bc
    ld bc,(total_sec)
    or a
    sbc hl,bc
    add hl,bc
    jr c,esp_seek_to
    ld a,EXIT_NEXT              ; past the end: the next file
    ld (exit_req),a
    ret

seek_back:
    call esp_can_seek
    ret c
    call esp_now
    ld bc,SEEK_SEC
    or a
    sbc hl,bc
    jr nc,esp_seek_to
    ld hl,0
;; HL = seconds
esp_seek_to:
    ld (esp_base),hl
    ld (step),hl                ; t
    ; q = alen / total, r = alen % total
    ld hl,(alen) : ld (dvd),hl
    ld hl,(alen+2) : ld (dvd+2),hl
    ld bc,(total_sec)
    call div32_16
    ld (tmpw),hl                ; r
    ld hl,(dvd) : ld (m32),hl
    ld hl,(dvd+2) : ld (m32+2),hl
    ld bc,(step)
    call mul32_16               ; DEHL = q * t
    ld (ppos),hl
    ld (ppos+2),de
    ld hl,(tmpw) : ld (m32),hl
    ld hl,0 : ld (m32+2),hl
    ld bc,(step)
    call mul32_16               ; DEHL = r * t
    call st_dvd
    ld bc,(total_sec)
    call div32_16               ; (dvd) = r * t / total
    ld hl,(ppos) : ld bc,(dvd) : add hl,bc
    ex de,hl
    ld hl,(ppos+2) : ld bc,(dvd+2) : adc hl,bc
    ex de,hl
    ld bc,(audio_start) : add hl,bc
    ex de,hl
    ld bc,(audio_start+2) : adc hl,bc
    ex de,hl
    push hl
    push de
    call esp_flush              ; DEHL = the file offset of the next data
    pop de
    pop hl
    call rd_seek
    xor a
    ld (eof),a
    call ui_status
    jp ui_prog

;; OUT: DEHL = bytes played, from audio_start: sent minus what the ESP holds
play_pos:
    call rd_tell
    ld bc,(esp_st + ST_BUFFERED) : or a : sbc hl,bc
    ex de,hl
    ld bc,(esp_st + ST_BUFFERED + 2) : sbc hl,bc
    ex de,hl
    jr c,.zero
    ld bc,(audio_start) : or a : sbc hl,bc
    ex de,hl
    ld bc,(audio_start+2) : sbc hl,bc
    ex de,hl
    ret nc
.zero:
    ld hl,0
    ld d,h
    ld e,l
    ret


;; ---------------------------------------------------------------------------
;; Leave the plugin
;; ---------------------------------------------------------------------------
EXIT_ESC        equ 1
EXIT_NEXT       equ 2
EXIT_END        equ 3
EXIT_PREV       equ 4

do_exit:
    ld a,(exit_req)
    cp EXIT_END
    call nz,esp_stop            ; stop the sound unless the track played out
    ld ix,wnd
    WCALL WCF_RRESB
    ld a,(exit_req)
    cp EXIT_PREV
    ld b,WCX_PREV
    jr z,.ret
    cp EXIT_ESC
    ld b,WCX_ESC
    jr z,.ret
    ; next track, unless this is the last file of the panel
    ld hl,(wc_index)
    ld de,(wc_count)
    or a
    sbc hl,de
    ld b,WCX_ESC
    jr nc,.ret
    ld b,WCX_NEXT
.ret:
    ld a,b
    ld sp,(entry_sp)
    ret

    include "wc.asm"
    include "esp.asm"
    include "math.asm"
    include "reader.asm"
    include "id3.asm"
    include "mpeg.asm"
    include "ui.asm"

;; Kept while WC keeps the plugin loaded: the volume of the last track
vol         db VOL_START

code_end:
    ds (512 - ($ & 511)) & 511
    OUTEND

;; ---------------------------------------------------------------------------
;; Variables and buffers: not in the file, set up at run time
;; ---------------------------------------------------------------------------
    ORG #A800
    ASSERT code_end <= $
vars:
entry_sp    ds 2
call_type   ds 1
panel_ix    ds 2
name_ptr    ds 2
wc_count    ds 2
wc_index    ds 2
file_size   ds 4
file_pos    ds 4
buf_base    ds 4
buf_len     ds 2
rd_off      ds 2
seek_tgt    ds 4
seek_sec    ds 4
seek_in     ds 2
esp_ans     ds 1
paused      ds 1
eof         ds 1
err_wait    ds 1
exit_req    ds 1
fcnt        ds 1
feed_max    ds 2
last_tmn    ds 2
step        ds 4
ppos        ds 4
tmpw        ds 2
tmpb        ds 1
dvd         ds 4
m32         ds 4
utoa_st     ds 1
; ESP: the state block of AUDIO_GET_STATE (registers #10..#2B)
esp_st      ds 28
ST_STATE    equ 0
ST_FMT      equ 1
ST_CHANNELS equ 2
ST_FLAGS    equ 3
ST_FREE     equ 4
ST_RATE     equ 8
ST_PLAYED   equ 12
ST_TOTAL    equ 16
ST_BUFFERED equ 20
ST_UNDER    equ 24
ST_ERROR    equ 26
ST_BITS     equ 27
ESP_ST_LEN  equ 28
esp_fmt     ds 1
esp_wtry    ds 1
esp_ended   ds 1
esp_sent_end ds 1
esp_fmt_shown ds 1
esp_base    ds 2
esp_tmp4    ds 6
; ID3
id3_found   ds 1
id3_ver     ds 1
id3_flg     ds 1
tag_unsync  ds 1
v4_all_unsync ds 1
frame_unsync ds 1
prev_raw    ds 1
prev_f      ds 1
fflag2      ds 1
fid         ds 4
tag_end     ds 4
frame_left  ds 4
rt_dst      ds 2
rt_max      ds 1
rt_len      ds 1
; MPEG
audio_start ds 4
alen        ds 4
fmt_ok      ds 1
is_vbr      ds 1
scan_cnt    ds 2
cand        ds 4
h1          ds 1
h2          ds 1
h3          ds 1
m_ver       ds 1
m_lay       ds 1
m_bri       ds 1
m_sri       ds 1
m_pad       ds 1
m_mode      ds 1
m_br        ds 2
m_sr        ds 2
m_spf       ds 2
m_flen      ds 2
m_frames    ds 4
bps         ds 2
total_sec   ds 2
tmp4        ds 4
; text
wnd         ds 16
tbuf        ds 16
linebuf     ds 80
fmtbuf      ds 80
fname       ds 256
f_title     ds FLD_LEN+1
f_artist    ds FLD_LEN+1
f_aartist   ds FLD_LEN+1
f_album     ds FLD_LEN+1
f_year      ds 5
f_track     ds 9
f_genre     ds 21
vars_end:
    ASSERT vars_end <= BUF

BUF         equ #B000
    ASSERT BUF + BUFSZ <= #C000
