"""Play lists (.m3u, .m3u8, .pls): the entries opened by name (FENTRY + GFILE of
the WC model), played one after the other, keys, titles, encodings."""
import struct
import sys

from common import t, done, raw, row
from espsim import EspSim

WMF = open(sys.argv[1], "rb").read()
wav = raw("s16.wav")            # 20 s, 44.1 kHz 16 bit stereo
mp3 = raw("cbr320.mp3")         # 30 s
flac = raw("s48.flac")
FAST = 2000000                  # plays a file out in a few frames

FILES = {
    "music/list/a.wav": wav,
    "music/list/sub/b.mp3": mp3,
    "music/c.flac": flac,
    "music/list/Тест.wav": wav,     # a Cyrillic name (CP866 as WC shows it)
}


def sim(text, name=b"list.m3u", **kw):
    a = dict(name=name, byte_rate=FAST, rate=44100, fmt_found=1, files=FILES, folder="music/list")
    a.update(kw)
    return EspSim(WMF, text, **a)


def streams(s):
    return [bytes(x[1]) for x in s.esp_streams]


# -- M3U: three entries, relative paths with '/', '\' and '..'
m3u = (b"#EXTM3U\r\n#EXTINF:20,Tone One\r\na.wav\r\n\r\n#EXTINF:30,Second\r\nsub\\b.mp3\r\n"
       b"../c.flac\r\n")
s = sim(m3u)
code = s.run()
t("M3U: the three files one after the other", streams(s) == [wav, mp3, flac], [len(x) for x in streams(s)])
t("M3U: START with the format of each entry", s.start_fmts == [1, 2, 4], s.start_fmts)
t("M3U: the list over -> the next file of the panel (2)", code == 2, code)
uniq = [p for i, p in enumerate(s.fentries) if p not in s.fentries[:i]]
t("M3U: FENTRY with the paths of the list", uniq == [b"a.wav", b"sub\\b.mp3", b"../c.flac"], s.fentries)

# the window of an entry: title of #EXTINF, the position in the list
s = sim(m3u, byte_rate=176400, keys={60: "esc"})
code = s.run(snap_at=(40,))
txt = s.snapshots[40]
t("M3U: the title of #EXTINF", "Tone One" in row(txt, "Title:"), row(txt, "Title:"))
t("M3U: the entry in File:", "a.wav" in row(txt, "File:"), row(txt, "File:"))
t("M3U: List: 1 / 3", "List: 1 / 3" in txt, txt)
t("M3U: Esc -> back to WC (0), AUDIO_STOP", code == 0 and s.cmds[-1] == 0x96, (code, s.cmds[-3:]))

# keys: Space = next entry, P = previous, at the first one: the first again
s = sim(m3u, byte_rate=176400, keys={40: "space", 90: "p", 140: "p", 190: "esc"})
code = s.run(snap_at=(70,))
t("M3U: Space -> the next entry", "List: 2 / 3" in s.snapshots[70], row(s.snapshots[70], "List"))
t("M3U: Space, P, P -> entries 1, 2, 1, 1", s.start_fmts == [1, 2, 1, 1], s.start_fmts)
t("M3U: then Esc -> WC (0)", code == 0, code)

# seek back in an entry: the stream rewound on the entry (FENTRY + GFILE again)
s = sim(m3u, byte_rate=176400, total=20 * 44100, bits=16, keys={60: "right", 80: "left", 200: "esc"})
s.run()
o, d = s.esp_streams[-1]
t("M3U: seek back in an entry: the entry's data from the offset", o is not None and bytes(d) == wav[o:o + len(d)] and len(d),
  (o, len(d)))
t("M3U: the entry opened again for it", s.fentries.count(b"a.wav") >= 2, s.fentries)

# missing files are skipped
s = sim(b"nothere.wav\na.wav\n")
code = s.run()
t("M3U: missing entries skipped", streams(s) == [wav] and code == 2, ([len(x) for x in streams(s)], code))

# -- radio: an address in the list, the ESP reads it
radio = b"#EXTINF:-1,Test FM\nhttp://radio.example:8000/stream.mp3\na.wav\n"
meta = {30: ("Test FM", "Artist - Song"), 120: ("Test FM", "Кино - Звезда")}
s = sim(radio, rate=44100, bitrate=128000, fmt_found=2, radio_meta=meta, keys={200: "space", 260: "esc"})
code = s.run(snap_at=(5, 60, 150))
t("radio: SET_URL with the address, then AUDIO_URL", s.urls == [b"http://radio.example:8000/stream.mp3"] and 0x98 in s.cmds,
  (s.urls, s.cmds[:6]))
t("radio: nothing pushed", s.esp_streams and not s.esp_streams[0][1], len(s.esp_streams[0][1]) if s.esp_streams else None)
t("radio: Connecting... at first", "Connecting" in s.snapshots[5], row(s.snapshots[5], "Conn"))
t("radio: the station in File:", "Test FM" in row(s.snapshots[60], "File:"), row(s.snapshots[60], "File:"))
t("radio: the title in Title:", "Artist - Song" in row(s.snapshots[60], "Title:"), row(s.snapshots[60], "Title:"))
t("radio: a new title (UTF-8 Cyrillic)", "Кино - Звезда" in row(s.snapshots[150], "Title:"), row(s.snapshots[150], "Title:"))
t("radio: Connecting gone", "Connecting" not in s.snapshots[60])
t("radio: no length", "--:--" in row(s.snapshots[150], " 00:"), row(s.snapshots[150], " 00:"))
t("radio: the time runs", "00:02" in row(s.snapshots[150], " 00:") or "00:01" in row(s.snapshots[150], " 00:"),
  row(s.snapshots[150], " 00:"))
t("radio: Space -> the next entry (a file)", s.start_fmts[-1:] == [1] and len(s.esp_streams) == 2, s.start_fmts)
t("radio: then Esc -> WC (0)", code == 0, code)

# a dead address: the message, then the next entry
s = sim(b"http://dead.example/\na.wav\n", radio_fail=0xC2)
code = s.run(snap_at=(40,))
t("radio: a dead address says so", "No stream" in s.snapshots[40], row(s.snapshots[40], "No stream"))
t("radio: then the next entry plays", streams(s)[-1:] == [wav] and code == 2, (code, [len(x) for x in streams(s)]))

# -- PLS: FileN= / TitleN=
pls = b"[playlist]\nFile1=sub/b.mp3\nTitle1=Song B\nLength1=30\nFile2=a.wav\nNumberOfEntries=2\nVersion=2\n"
s = sim(pls, name=b"radio.pls", byte_rate=176400, keys={300: "space", 360: "esc"})
s.run(snap_at=(250, 340))
t("PLS: the first entry", s.start_fmts[:1] == [2], s.start_fmts)
t("PLS: its TitleN shown (MP3 without a tag)", "Song B" in row(s.snapshots[250], "Title:"), row(s.snapshots[250], "Title:"))
t("PLS: Space -> File2", s.start_fmts[:2] == [2, 1] and "List: 2 / 2" in s.snapshots[340], s.start_fmts)

# -- encodings: CP1251 and UTF-8 (m3u8, BOM) names to CP866
for what, text in (("CP1251", "Тест.wav\n".encode("cp1251")),
                   ("UTF-8", "Тест.wav\n".encode("utf-8")),
                   ("UTF-8 with a BOM", b"\xef\xbb\xbf#EXTM3U\n" + "Тест.wav\n".encode("utf-8"))):
    s = sim(text, name=b"cyr.m3u8")
    s.run()
    t("M3U %s: the Cyrillic name found" % what, streams(s) == [wav], s.fentries)

# -- an empty list: a message, a key, back to WC
s = sim(b"#EXTM3U\n# nothing\n", keys={20: "enter"})
code = s.run(snap_at=(10,))
t("empty list: says so", "No files in this play list" in s.snapshots[10], s.snapshots[10])
t("empty list: back to WC (0), nothing played", code == 0 and 0x90 not in s.cmds, (code, s.cmds))

# -- the last panel file: after the list back to WC
s = sim(b"a.wav\n", index=3, count=3)
t("the list as the last panel file: then WC (0)", s.run() == 0)

done()
