"""MP3 tags and stream lines: the ID3v2 parser and mpeg_scan of the plugin, and
the stream that reaches the ESP (the audio after the tag, from the first frame)."""
import sys

from mutagen.id3 import TIT2, TPE1, TALB, TYER, TDRC, TRCK, TCON, APIC, TPE2

from common import t, done, raw, tagged, v22, unsync23, junk_front, audio_start, row
from espsim import EspSim

WMF = open(sys.argv[1], "rb").read()
CASES = []


def case(name, data, expect, **kw):
    CASES.append((name, data, expect, kw))


cbr = raw("cbr128.mp3")
vbr = raw("vbr.mp3")
mono = raw("mono22.mp3")
c320 = raw("cbr320.mp3")

case("v2.3 UTF-16 cyrillic, APIC 300 KB, genre (17)",
     tagged(cbr, [TIT2(encoding=1, text="Группа крови"),
                  TPE1(encoding=1, text="Кино"),
                  TALB(encoding=1, text="Группа крови"),
                  TYER(encoding=1, text="1988"),
                  TRCK(encoding=1, text="1/11"),
                  TCON(encoding=1, text="(17)"),
                  APIC(encoding=0, mime="image/jpeg", type=3, desc="",
                       data=raw("cover.jpg"))]),
     {"Title:": "Группа крови", "Artist:": "Кино", "Album:": "Группа крови",
      "Year:": "1988", "Track:": "1/11", "Genre:": "Rock",
      "MPEG": "MPEG-1 Layer III  128 kbps CBR  44.1 kHz  Joint Stereo"})

case("v2.4 UTF-8, TDRC, VBR Xing",
     tagged(vbr, [TIT2(encoding=3, text="Ёлка — новогодняя"),
                  TPE1(encoding=3, text="Ансамбль «Тест»"),
                  TALB(encoding=3, text="Ünïcode Latin"),
                  TDRC(encoding=3, text="2001-05-01"),
                  TCON(encoding=3, text="Electronic")], v2_version=4),
     {"Title:": "Ёлка - новогодняя", "Artist:": "Ансамбль ?Тест?",
      "Album:": "?n?code Latin", "Year:": "2001", "Genre:": "Electronic",
      "MPEG": "VBR  44.1 kHz"})

case("v2.3 latin-1 frames holding CP1251, TPE2 only",
     tagged(mono, [TIT2(encoding=0, text="Привет, мир".encode("cp1251").decode("latin1")),
                   TPE2(encoding=0, text="Album Artist"),
                   TCON(encoding=0, text="(20)Indie")]),
     {"Title:": "Привет, мир", "Artist:": "Album Artist", "Genre:": "Indie",
      "MPEG": "MPEG-2 Layer III  32 kbps CBR  22.05 kHz  Mono"})

case("v2.2 tag", v22(c320),
     {"Title:": "Old tag title", "Artist:": "Old artist", "Genre:": "Rock",
      "MPEG": "MPEG-1 Layer III  320 kbps CBR  48 kHz"})

case("v2.3 tag-level unsync", unsync23(cbr),
     {"Title:": "Моя песня я", "Artist:": "Ёжик"})

case("no tag", cbr, {"Title:": "(no ID3v2 tag)",
                     "MPEG": "MPEG-1 Layer III  128 kbps CBR"})

case("very long title is cut",
     tagged(cbr, [TIT2(encoding=1, text="A" * 70)]),
     {"Title:": "A" * 52 + "~"})

case("junk before the first frame", junk_front(cbr),
     {"MPEG": "MPEG-1 Layer III  128 kbps CBR  44.1 kHz"}, start=4 + 600)

case("not audio at all", bytes(range(256)) * 64,
     {"MPEG": "No MPEG audio frames found"})


def check(name, data, expect, kw):
    start = kw.pop("start", None)
    if start is None:
        start = audio_start(data)
    s = EspSim(WMF, data, name="\u041f\u0440\u0438\u0432\u0435\u0442.mp3".encode("cp866"),
               byte_rate=400000, fmt_found=2, **kw)
    code = s.run()
    txt = s.text()                  # the window stays on the screen of the model
    bad = ["%s: want %r in %r" % (label, want, row(txt, label).strip())
           for label, want in expect.items() if want not in row(txt, label)]
    sent = bytes(s.esp_streams[0][1]) if s.esp_streams else b""
    if sent != data[start:]:
        bad.append("stream: %d bytes to the ESP, want %d from %d" % (len(sent), len(data) - start, start))
    if code != 2:
        bad.append("exit code %d" % code)
    t(name, not bad, "\n  ".join([""] + bad) + "\n" + ("" if not bad else txt))


for c in CASES:
    check(*c)
done()
