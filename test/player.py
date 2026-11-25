"""ESPPLAY.WMF with the ESP model (espsim.py): what reaches the ESP, the
commands, the keys, seeking, the window, the diagnostic window."""
import struct
import sys

from mutagen.id3 import TIT2, TPE1

from common import t, done, raw, tagged, audio_start, row, syncsafe
from espsim import EspSim

WMF = open(sys.argv[1], "rb").read()

cbr = raw("cbr128.mp3")         # 95 s, 16000 B/s
c320 = raw("cbr320.mp3")        # 30 s, 40000 B/s
wav = raw("s16.wav")            # 20 s
flac = raw("s48.flac")
ogg = raw("s44.ogg")
FAST = 400000                   # a byte rate that plays a file out in a few frames


def wav_info(d):
    i = 12
    while i < len(d):
        cid, sz = d[i:i + 4], struct.unpack_from("<I", d, i + 4)[0]
        if cid == b"fmt ":
            ch, rate, _, ba = struct.unpack_from("<HIIH", d, i + 10)
        if cid == b"data":
            return sz // ba, rate, ch, ba
        i += 8 + sz + (sz & 1)


frames, rate, ch, ba = wav_info(wav)
WAV = dict(name=b"tone.wav", byte_rate=rate * ba, rate=rate, channels=ch, bits=16, total=frames, fmt_found=1)


def mp3(data=cbr, **kw):
    a = dict(name=b"song.mp3", byte_rate=16000, rate=44100, fmt_found=2)
    a.update(kw)
    return EspSim(WMF, data, **a)


# -- header
t("header: format #10", WMF[32] == 0x10, WMF[32])
t("header: extensions MP3 WAV OGG FLA AAC M4A M3U PLS", WMF[64:89] == b"MP3WAVOGGFLAAACM4AM3UPLS\0", WMF[64:89])
t("header: also from F10 and Shift+F3 (+197 = #05)", WMF[197] == 0x05, WMF[197])
t("header: Shift+F3 text", WMF[204:228] == b"Play on ESP32".ljust(24), WMF[204:228])

# -- MP3: from the frame after the tag, END at the end, next file
song = tagged(cbr, [TIT2(encoding=1, text="Группа крови"), TPE1(encoding=1, text="Кино")])
s = mp3(song, byte_rate=FAST)
code = s.run(snap_at=(30,))
txt = s.snapshots[30]
t("MP3: plays out, next file", code == 2, code)
t("MP3: the ESP got the audio after the ID3v2 tag",
  len(s.esp_streams) == 1 and bytes(s.esp_streams[0][1]) == song[audio_start(song):])
t("MP3: one AUDIO_START with the format MP3", s.start_fmts == [2], s.start_fmts)
t("MP3: AUDIO_END after the last PUSH", 0x92 in s.cmds)
t("MP3: no PUSH refused", s.refused == 0, s.refused)
t("MP3: volume -4 dB at the start", s.vols[:1] == [8], s.vols)
t("MP3: title of the tag", "Группа крови" in row(txt, "Title:"), row(txt, "Title:"))
t("MP3: stream line of mpeg_scan", "MPEG-1 Layer III  128 kbps CBR  44.1 kHz" in row(txt, "MPEG"), row(txt, "MPEG"))
t("MP3: total time of mpeg_scan", "01:3" in txt)
t("MP3: decoder ESP32, no bass / treble", "ESP32" in row(txt, "Decoder:") and "Bass" not in txt,
  row(txt, "Decoder:"))
t("window title", "ZiFi32 Audio Player" in txt)

# -- WAV: from byte 0, the stream line and the length from the ESP
s = EspSim(WMF, wav, **WAV)
code = s.run(snap_at=(120,))
txt = s.snapshots[120]
t("WAV: plays out", code == 2, code)
t("WAV: the whole file reached the ESP", bytes(s.esp_streams[0][1]) == wav)
t("WAV: stream line from the ESP", "WAV  44.1 kHz  16 bit  Stereo" in txt, row(txt, "WAV"))
t("WAV: no '(no ID3v2 tag)'", "no ID3v2" not in txt)
t("WAV: total 00:20 from the ESP", "00:20" in txt)
t("WAV: elapsed ~2 s at frame 120", "00:02" in row(txt, "00:20"), row(txt, "00:20"))

# -- the tags of the MP3 before do not stay for a WAV (the page holds old data)
s = mp3(song, byte_rate=FAST)
s.run()
s.start(wav, name=b"tone.wav")
s.__dict__.update(rate=rate, byte_rate=rate * ba, total=frames, fmt_found=1, bits=16)
s.keys = {s.frame + 40: "esc"}
s.run()
txt = s.text()
t("WAV after an MP3: no tags of the MP3", all(row(txt, l).strip("| ").rstrip(" |") == l
                                               for l in ("Title:", "Artist:", "Album:")), txt)

# -- FLAC and Ogg
s = EspSim(WMF, flac, name=b"tone.flac", byte_rate=len(flac) // 20, rate=48000, bits=16, total=48000 * 20, fmt_found=4)
code = s.run(snap_at=(100,))
txt = s.snapshots[100]
t("FLAC: the whole file, plays out", code == 2 and bytes(s.esp_streams[0][1]) == flac, code)
t("FLAC: stream line", "FLAC  48 kHz  16 bit  Stereo" in txt, row(txt, "FLAC"))
t("FLAC: START with the format FLAC", s.start_fmts == [4], s.start_fmts)
s = EspSim(WMF, ogg, name=b"tone.ogg", byte_rate=len(ogg) // 20, rate=44100, seekable=False, fmt_found=3,
           keys={60: "right", 70: "left"})
code = s.run(snap_at=(100,))
txt = s.snapshots[100]
t("Ogg: the whole file, plays out", code == 2 and bytes(s.esp_streams[0][1]) == ogg, code)
t("Ogg: stream line", "Ogg Vorbis  44.1 kHz" in txt, row(txt, "Ogg"))
t("Ogg: the arrows do not flush (not seekable)", 0x93 not in s.cmds)
t("Ogg: length not known", "--:--" in txt)

# -- the ESP arms its DMA after the plugin gave up waiting (seen on the board
# after minutes of a long file): the plugin sends the data anyway, no dead lock
s = mp3(cbr, byte_rate=FAST, late_push=(40,))
code = s.run(max_frames=3000)
t("late DMA: the file still reaches the ESP whole", code == 2 and bytes(s.esp_streams[0][1]) == cbr,
  (code, len(s.esp_streams[0][1])))

s = mp3(cbr, byte_rate=FAST, lost_wend=(30,))
code = s.run(max_frames=3000)
t("a missed W_END: sent again, the file whole", code == 2 and bytes(s.esp_streams[0][1]) == cbr
  and s.wends == s.pushes + 1, (code, len(s.esp_streams[0][1]), s.pushes, s.wends))
# every W_END of a PUSH lost (the resends too): the plugin gives up and sends the
# block again; the firmware of 2e9589d then lags one behind for good, 0d4e52c
# (M2S again on a PUSH while armed) takes the block, the file whole
s = mp3(cbr, byte_rate=FAST, lost_wend=(30, 31, 32, 33), rearm=True)
code = s.run(max_frames=3000)
t("all W_ENDs of a PUSH lost, ESP 0d4e52c: the block again, the file whole",
  code == 2 and bytes(s.esp_streams[0][1]) == cbr, (code, len(s.esp_streams[0][1])))
s = mp3(cbr, byte_rate=FAST, lost_wend=(30, 31, 32, 33), keys={1500: "esc"})
code = s.run(max_frames=3000)
t("all W_ENDs of a PUSH lost, ESP 2e9589d: lags, Esc still works", code == 0, code)

# after all the waits (an ESP stalled for seconds): the firmware of 2e9589d then
# lags one PUSH behind for good (the PUSH queued behind says BUSY over the M2S);
# the player is slow but still takes keys
s = mp3(cbr, byte_rate=FAST, late_push=(40,), late_polls=400000, keys={1500: "esc"})
code = s.run(max_frames=3000)
t("very late DMA (after all the waits): Esc still works", code == 0 and s.cmds[-1] == 0x96, (code, s.cmds[-3:]))
s = mp3(cbr, byte_rate=FAST, late_push=(40,), late_polls=400000, rearm=True)
code = s.run(max_frames=3000)
t("very late DMA, ESP 0d4e52c: the file whole", code == 2 and bytes(s.esp_streams[0][1]) == cbr,
  (code, len(s.esp_streams[0][1])))
# -- AAC (ADTS): the length from the bitrate, seek; M4A: no seek
aac = raw("s44.aac")
s = EspSim(WMF, aac, name=b"tone.aac", byte_rate=16000, rate=44100, fmt_found=5, bitrate=128000,
           keys={150: "right", 300: "esc"})
code = s.run(snap_at=(100,))
txt = s.snapshots[100]
t("AAC: START with the format AAC", s.start_fmts == [5], s.start_fmts)
t("AAC: stream line with the bitrate", "AAC  128 kbps  44.1 kHz  Stereo" in txt, row(txt, "AAC"))
t("AAC: length from the bitrate", "00:%02d" % (len(aac) // 16000) in row(txt, "00:"), row(txt, "00:"))
t("AAC: seek -> FLUSH, the data from the offset",
  len(s.esp_streams) == 2 and bytes(s.esp_streams[1][1]) == aac[s.esp_streams[1][0]:s.esp_streams[1][0] + len(s.esp_streams[1][1])],
  [x[0] for x in s.esp_streams])
# the ESP's first bitrate is off (one frame), the average comes later
s = EspSim(WMF, aac, name=b"tone.aac", byte_rate=16000, rate=44100, fmt_found=5, bitrate=94000,
           keys={300: "esc"})
s.on_frame = {150: lambda: setattr(s, "bitrate", 130000)}
s.run(snap_at=(100, 250))
t("AAC: the length follows the bitrate of the ESP",
  "00:27" in row(s.snapshots[100], "00:") and "00:20" in row(s.snapshots[250], "00:"),
  (row(s.snapshots[100], "00:"), row(s.snapshots[250], "00:")))
t("AAC: the stream line follows the bitrate", "130 kbps" in row(s.snapshots[250], "AAC"), row(s.snapshots[250], "AAC"))
m4a = raw("s44.m4a")
s = EspSim(WMF, m4a, name=b"tone.m4a", byte_rate=16000, rate=44100, fmt_found=6, bitrate=128000, seekable=False,
           keys={100: "right", 200: "esc"})
code = s.run(snap_at=(90,))
txt = s.snapshots[90]
t("M4A: START with the format M4A", s.start_fmts == [6], s.start_fmts)
t("M4A: stream line", "M4A (AAC)  128 kbps  44.1 kHz  Stereo" in txt, row(txt, "M4A"))
t("M4A: no seek", 0x93 not in s.cmds)

# -- the ESP refuses the stream: the error on the screen, then the next file
s = EspSim(WMF, wav, fail=0xC0, **WAV)
code = s.run(snap_at=(40,))
t("ESP error: says it", "cannot play this file, error #C0" in s.snapshots[40] and "##" not in s.snapshots[40], row(s.snapshots[40], "error"))
t("ESP error: next file after a while", code == 2 and s.frame >= 100, (code, s.frame))

# -- keys: exit codes
s = mp3(keys={100: "esc"})
code = s.run()
t("Esc: back to WC (0), AUDIO_STOP", code == 0 and s.cmds[-1] == 0x96, (code, s.cmds[-3:]))
t("Space: next (2)", mp3(keys={50: "space"}).run() == 2)
t("Enter: next (2)", mp3(keys={50: "enter"}).run() == 2)
t("Space on the last file: back to WC (0)", mp3(index=3, count=3, keys={50: "space"}).run() == 0)
t("played out on the last file: back to WC (0)", mp3(c320, byte_rate=FAST, index=3, count=3).run() == 0)
t("P: previous (4)", mp3(keys={50: "p"}).run() == 4)
t("BackSpace: previous (4)", mp3(keys={50: "bspc"}).run() == 4)
s = mp3(call_type=4, keys={40: "esc"})
code = s.run(snap_at=(30,))
t("Shift+F3: plays like Enter", code == 0 and "Decoder:" in s.snapshots[30] and s.start_fmts == [2], code)

# -- time, pause
s = mp3(keys={520: "esc"})
s.run(snap_at=(510,))
line = s.line(s.snapshots[510], 11)
t("elapsed ~10 s after 500 frames", "00:09" in line or "00:10" in line, line)
t("no underrun at 128 kbps", s.underruns == 0, s.underruns)
s = mp3(keys={100: "s", 400: "s", 600: "esc"})
s.run(snap_at=(300, 590))
t("S: Paused shown", "Paused" in s.snapshots[300])
p = row(s.snapshots[300], " 00:")
t("S: the time stops near 2 s", "00:01" in p or "00:02" in p, p)
t("S again: Paused gone", "Paused" not in s.snapshots[590])
t("S: AUDIO_PAUSE 1, then 0", s.cmds.count(0x94) == 2 and not s.paused)

# -- slow SD card at 320 kbps (40000 T per sector, ~175 KB/s)
s = mp3(c320, byte_rate=40000, keys={1200: "esc"})
s.sector_cost = 40000
s.run()
t("320 kbps with a slow SD card: no underrun", s.underruns == 0, s.underruns)

# -- seek (MP3): right x3 then left: ~1.2 + 30 - 10 s
s = mp3(keys={60: "right", 70: "right", 80: "right", 90: "left", 200: "esc"})
s.run(snap_at=(150,))
line = row(s.snapshots[150], " 00:")
t("seek: the time ~0:22", any(x in line for x in ("00:21", "00:22", "00:23")), line)
t("seek: one AUDIO_FLUSH per key", s.cmds.count(0x93) == 4, s.cmds.count(0x93))
o, d = s.esp_streams[-1]
t("seek: after FLUSH the file from its offset", o is not None and bytes(d) == cbr[o:o + len(d)] and len(d) > 0, o)
t("seek: offset ~21 s", abs(o - 16000 * 21) < 16000 * 2, o / 16000)
s = mp3(keys={60: "left", 100: "esc"})
s.run()
t("seek back at the start: the first frame", s.esp_streams[-1][0] == 0, s.esp_streams[-1][0])
s = mp3(keys={60 + i * 3: "right" for i in range(12)})
code = s.run()
t("seek past the end: the next file (2), sound stopped", code == 2 and s.cmds[-1] == 0x96, (code, s.cmds[-3:]))
s = mp3(song, keys={60: "left", 100: "esc"})
s.run()
t("seek back with a tag: offset = the end of the tag", s.esp_streams[-1][0] == audio_start(song),
  (s.esp_streams[-1][0], audio_start(song)))

# -- WAV seek: by the length from the ESP
s = EspSim(WMF, wav, keys={100: "right"}, **WAV)
code = s.run()
t("WAV seek: plays out", code == 2, code)
t("WAV seek: one AUDIO_FLUSH", s.cmds.count(0x93) == 1 and len(s.esp_streams) == 2)
o, d = s.esp_streams[1]
t("WAV seek: the data from the offset", bytes(d) == wav[o:])
t("WAV seek: offset ~12 s", abs(o / (rate * ba) - 12) < 1.5, o / (rate * ba))

# -- volume: 0.5 dB steps, kept for the next track
s = mp3(keys={50: "down", 60: "down", 70: "up", 80: "-", 100: "esc"})
s.run(snap_at=(90,))
t("volume: VOLUME 8, 12, 16, 12, 16", s.vols == [8, 12, 16, 12, 16], s.vols)
t("volume: -8dB shown", "-8dB" in row(s.snapshots[90], "Vol:"), row(s.snapshots[90], "Vol:"))
s.start(cbr, name=b"next.mp3")
s.keys = {s.frame + 30: "esc"}
s.run()
t("volume: the next track starts at it", s.vols[5:6] == [16], s.vols)
s = mp3(keys={i: "up" for i in range(40, 70, 5)})
s.keys[100] = "esc"
s.run(snap_at=(90,))
t("volume: up to 0 dB", s.vols[-1] == 0 and "Vol:" in s.snapshots[90] and " 0dB" in row(s.snapshots[90], "Vol:"),
  (s.vols, row(s.snapshots[90], "Vol:")))

# -- no ESP, old firmware, F10
for name, kw, want in (("no ESP", dict(esp=False), "No answer"),
                       ("ZiFi32 without the player", dict(audio=False), "No audio player")):
    s = mp3(keys={20: "enter"}, **kw)
    code = s.run(snap_at=(10,))
    t(name + ": Enter -> WC's Shift+F3 menu (1)", code == 1, code)
    t(name + ": says " + want, want in s.snapshots[10], s.snapshots[10])
    t(name + ": the answer with one '#'", "answer: #" in s.snapshots[10] and "##" not in s.snapshots[10],
      row(s.snapshots[10], "answer"))
    s = mp3(call_type=4, keys={20: "esc"}, **kw)
    t(name + ", Shift+F3: back to WC (0)", s.run() == 0)
s = mp3(call_type=3, keys={20: "esc"})
code = s.run(snap_at=(10,))
txt = s.snapshots[10]
t("F10: back to WC (0)", code == 0, code)
t("F10: the player found", "Audio player of ZiFi32 found" in txt, txt)
t("F10: firmware version", "Firmware: ZiFi32 0.6.4, API 1" in txt, row(txt, "Firmware"))
t("F10: nothing played", 0x90 not in s.cmds, s.cmds)

# -- the window on 30 and 36 lines, colours
for hei, xy in ((36, (13, 9)), (30, (8, 6))):
    s = mp3(hei=hei, keys={20: "esc"})
    s.run()
    t("%d lines: the window centred" % hei, s.win[:2] == xy, s.win)
s = mp3(song, keys={60: "esc"})
s.run(snap_at=(40,))
cols = {"title bar": (0, 20, 0xF7), "label File:": (1, 2, 0x71), "value file": (1, 10, 0x7E),
        "label Decoder:": (9, 2, 0x71), "decoder name": (9, 11, 0x7E), "time": (11, 4, 0x70),
        "progress bar": (11, 10, 0x71), "keys": (16, 1, 0x70), "separator": (2, 5, 0x7F)}
for what, (y, x, want) in cols.items():
    got = s.attr_at(y, x)
    t("colour of %s is %02X" % (what, want), got == want, "%02X" % got)

# -- v2.4 with per-frame unsync and a data length indicator
def fr4(fid, payload, flags=0):
    return fid + syncsafe(len(payload)) + b"\0" + bytes([flags]) + payload
data = b"\x00" + "яяя".encode("cp1251")          # FF FF FF in cp1251
uns = bytearray()
for b in data:
    uns.append(b)
    if b == 0xFF:
        uns.append(0)
body = fr4(b"TIT2", syncsafe(len(data)) + bytes(uns), 0x03) + fr4(b"TPE1", b"\x03" + "Тест".encode()) + bytes(16)
tag = b"ID3\x04\x00\x00" + syncsafe(len(body)) + body
s = mp3(tag + c320, byte_rate=FAST)
s.run(snap_at=(20,))
txt = s.snapshots[20]
t("v2.4 frame unsync + DLI", "яяя" in row(txt, "Title:"), row(txt, "Title:"))
t("v2.4 the frame after it", "Тест" in row(txt, "Artist:"), row(txt, "Artist:"))
t("v2.4 the stream after the tag", bytes(s.esp_streams[0][1]) == c320)

# -- the progress bar on a file over 64 MB: ~83 MB at 128 kbps = ~87 min,
# 74 seeks of 10 s = ~12:20 -> ~14 % of 46 cells
big = cbr * (83_000_000 // len(cbr) + 1)
keys = {50 + 4 * i: "right" for i in range(74)}
keys[600] = "esc"
s = mp3(big, keys=keys)
s.run(snap_at=(500,))
line = row(s.snapshots[500], "86:") or row(s.snapshots[500], "87:")
cells = line.count("█")
t("bar on an 83 MB file ~14 %", 4 <= cells <= 9, (cells, line))

done()
