;; Play lists: .m3u / .m3u8 (lines, #EXTINF titles) and .pls (FileN= /
;; TitleN=). The entries are paths relative to the folder of the list, with
;; '/' or '\' (".." works: a FAT folder has it), opened by name with
;; WC's FENTRY + GFILE. The list itself is the file WC passed to the plugin:
;; GIPAGPL always rewinds to it, so it is read again from its start for
;; every entry (pl_scan), nothing of it is kept but the index.
;; Text: UTF-8 if the line is valid UTF-8 (or the file starts with a BOM),
;; else CP1251; both to CP866 (the WC font, the FAT long names of WC).

PL_M3U          equ 1
PL_PLS          equ 2
LINE_MAX        equ 255

;; From the name in fname: a play list? Then pl_mode, pl_size, pl_count.
;; OUT: Z = not a list; NZ = a list: CF = 1 it has no entries
pl_check:
    xor a
    ld (pl_mode),a
    ld (rd_entry),a
    call ext_ptr                ; HL = after the last '.', Z = none
    ret z
    ld a,(hl) : or #20 : ld b,a
    inc hl
    ld a,(hl) : or #20 : ld c,a
    inc hl
    ld a,(hl) : or #20 : ld e,a
    ld a,b
    cp 'm'
    jr nz,.pls
    ld a,c : cp '3' : jr nz,.no
    ld a,e : cp 'u' : jr nz,.no
    ld a,PL_M3U
    jr .list
.pls:
    cp 'p' : jr nz,.no
    ld a,c : cp 'l' : jr nz,.no
    ld a,e : cp 's' : jr nz,.no
    ld a,PL_PLS
    jr .list
.no:
    xor a                       ; Z: not a list
    ret
.list:
    ld (pl_mode),a
    ld hl,(file_size) : ld (pl_size),hl
    ld hl,(file_size+2) : ld (pl_size+2),hl
    ld hl,0
    ld (pl_idx),hl
    ld hl,#FFFF                 ; count them all
    call pl_scan
    ld hl,(pl_found)
    ld (pl_count),hl
    ld a,h : or l
    ld a,1
    jr z,.empty
    or a                        ; NZ, CF = 0
    ret
.empty:
    or a
    scf                         ; NZ, CF = 1
    ret

;; Open the entry pl_idx (or the next one that exists): fname = its path,
;; pe_buf = the FENTRY argument, file_size; the WC stream on it.
;; OUT: CF = 1 when the list is over
pl_open:
    ld hl,(pl_idx)
    ld de,(pl_count)
    or a
    sbc hl,de
    ccf
    ret c
    ld hl,(pl_idx)
    call pl_scan
    jr c,.skip
    ld hl,pe_buf + 1            ; an address (radio): not yet
    call has_url
    jr z,.skip
    xor a
    ld (pe_buf),a               ; FENTRY flag: a file
    ld hl,pe_buf
    WCALL WCF_FENTRY
    jr z,.skip                  ; not found
    ld (file_size),hl
    ld (file_size+2),de
    WCALL WCF_GFILE
    ld a,1
    ld (rd_entry),a             ; rewinds: FENTRY + GFILE
    ld hl,pe_buf + 1
    ld de,fname
    ld bc,256
    ldir
    or a
    ret
.skip:
    ld hl,(pl_idx)
    inc hl
    ld (pl_idx),hl
    jr pl_open

;; Rewind the stream of the file played: the file WC passed (GIPAGPL), or
;; the play list entry (FENTRY + GFILE again: GFILE only once per FENTRY)
rd_rewind:
    ld a,(rd_entry)
    or a
    jr nz,.entry
    ld ix,(panel_ix)
    WCALL WCF_GIPAGPL
    ret
.entry:
    ld hl,pe_buf
    WCALL WCF_FENTRY
    ret z
    WCALL WCF_GFILE
    ret

;; Read the list from its start up to entry HL (#FFFF: all of them).
;; OUT: CF = 0 found: pe_buf + 1 = its path, pe_title = its title (CP866);
;;      CF = 1 not there. pl_found = entries seen.
pl_scan:
    ld (pl_want),hl
    xor a
    ld (rd_entry),a             ; the stream of the list (GIPAGPL)
    ld (pe_title),a
    ld (pl_hit),a
    ld (pl_bom),a
    ld hl,0
    ld (pl_found),hl
    ld hl,(pl_size) : ld (file_size),hl
    ld hl,(pl_size+2) : ld (file_size+2),hl
    call rd_init
    ; a UTF-8 BOM: the whole file is UTF-8
    call rd_getbyte : jr c,.nobom : cp #EF : jr nz,.nobom
    call rd_getbyte : jr c,.nobom : cp #BB : jr nz,.nobom
    call rd_getbyte : jr c,.nobom : cp #BF : jr nz,.nobom
    ld a,1
    ld (pl_bom),a
    jr .lines
.nobom:
    ld hl,0
    ld de,0
    call rd_seek
.lines:
    call pl_line
    jp c,.eof
    ld a,(lbuf)
    or a
    jr z,.lines
    ld a,(pl_mode)
    cp PL_PLS
    jr z,.pls
    ; M3U
    ld a,(lbuf)
    cp '#'
    jr nz,.entry
    ld hl,lbuf
    ld de,s_extinf
    call prefix
    jr nz,.lines
    ld a,(pl_hit)
    or a
    jr nz,.lines
    ld hl,lbuf + 8              ; "#EXTINF:" -> the title after the first ','
.comma:
    ld a,(hl)
    or a
    jr z,.lines
    inc hl
    cp ','
    jr nz,.comma
    call pl_title
    jr .lines
.pls:
    ld hl,lbuf
    ld de,s_file
    call prefix
    jr z,.pfile
    ld hl,lbuf
    ld de,s_title
    call prefix
    jr nz,.lines
    ld a,(pl_hit)               ; TitleN after the FileN found
    or a
    jr z,.lines
    call after_eq
    call pl_title
    jr .done
.pfile:
    ld a,(pl_hit)
    or a
    jr nz,.done                 ; the next FileN: no title for the one found
    call after_eq
    jr .take
.entry:
    ld hl,lbuf
.take:
    ; HL = the entry text
    ld a,(pl_hit)
    or a
    jr nz,.done
    push hl
    ld hl,(pl_found)
    ld de,(pl_want)
    or a
    sbc hl,de
    pop hl
    jr z,.hit
    ld de,(pl_found)
    inc de
    ld (pl_found),de
    xor a
    ld (pe_title),a             ; an #EXTINF belongs to the next entry only
    jp .lines
.hit:
    ld de,pe_buf + 1
    ld b,LINE_MAX
    call pl_conv
    ld hl,(pl_found)
    inc hl
    ld (pl_found),hl
    ld a,1
    ld (pl_hit),a
    ld a,(pl_mode)
    cp PL_PLS
    jp z,.lines                 ; its TitleN may follow
.done:
    or a
    ret
.eof:
    ld a,(pl_hit)
    or a
    ret nz                      ; CF = 0
    scf
    ret

;; HL = text: the title of the entry (CP866) into pe_title
pl_title:
    ld de,pe_title
    ld b,FLD_LEN
    ; fall through

;; HL = raw text (0-terminated) -> DE, at most B chars, CP866
pl_conv:
    ld (lptr),hl
    ld (rt_dst),de
    xor a
    ld (de),a
    ld (rt_len),a
    ld a,b
    ld (rt_max),a
    ld de,lbyte
    ld (rt_src),de
    ld a,(pl_bom)
    or a
    jr nz,.utf8
    call utf8_ok
    jp nz,read_text.cp1251
.utf8:
    jp read_text.utf8

;; The next byte of the text at (lptr); 0 at its end. Keeps B, DE, HL.
lbyte:
    push hl
    ld hl,(lptr)
    ld a,(hl)
    or a
    jr z,.end
    inc hl
    ld (lptr),hl
.end:
    pop hl
    or a                        ; CF = 0
    ret

;; HL = 0-terminated text: Z if it is valid UTF-8 (ASCII is)
utf8_ok:
    ld a,(hl)
    or a
    ret z
    inc hl
    cp #80
    jr c,utf8_ok
    ld b,1
    cp #C2
    jr c,.bad
    cp #E0
    jr c,.cont
    inc b
    cp #F0
    jr c,.cont
    inc b
    cp #F5
    jr nc,.bad
.cont:
    ld a,(hl)
    and #C0
    cp #80
    jr nz,.bad
    inc hl
    djnz .cont
    jr utf8_ok
.bad:
    or 1                        ; NZ
    ret

;; One line of the list into lbuf (0-terminated, CR / LF / CR LF; longer
;; lines cut). OUT: CF = 1 at the end of the file with nothing read
pl_line:
    ld hl,lbuf
    ld c,0                      ; something read
.loop:
    call rd_getbyte
    jr c,.eof
    ld c,1
    cp 10
    jr z,.end
    cp 13
    jr z,.end
    ld b,a
    ld a,l
    cp LINE_MAX
    jr nc,.loop                 ; full: the rest of the line is dropped
    ld (hl),b
    inc hl
    jr .loop
.eof:
    ld (hl),0
    ld a,c
    or a
    ret nz                      ; the last line without an end
    scf
    ret
.end:
    ld (hl),0
    ; trailing spaces off
.trim:
    ld a,l
    or a
    ret z
    dec hl
    ld a,(hl)
    cp ' '+1
    jr nc,.kept
    ld (hl),0
    jr .trim
.kept:
    or a
    ret

;; HL = text, DE = lower-case prefix: Z if the text starts with it (any case)
prefix:
    ld a,(de)
    or a
    ret z
    ld b,a
    ld a,(hl)
    or #20
    cp b
    ret nz
    inc hl
    inc de
    jr prefix

;; HL = "FileN=x" -> HL = x
after_eq:
    ld a,(hl)
    or a
    ret z
    inc hl
    cp '='
    ret z
    jr after_eq

;; HL = text: Z if it holds "://"
has_url:
    ld a,(hl)
    or a
    jr z,.no
    inc hl
    cp ':'
    jr nz,has_url
    ld a,(hl)
    cp '/'
    jr nz,has_url
    inc hl
    ld a,(hl)
    cp '/'
    ret z
    jr has_url
.no:
    or 1
    ret

;; HL = after the last '.' of fname; Z if there is none
ext_ptr:
    ld hl,fname
    ld de,0
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
    ex de,hl
    ld a,h
    or l
    ret

s_extinf:   db "#extinf:",0
s_file:     db "file",0
s_title:    db "title",0
