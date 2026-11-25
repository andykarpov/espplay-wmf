"""Helpers of the tests: the test files, ID3 tags built with mutagen, checks."""
import io
import os
import struct

from mutagen.id3 import ID3

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
MP3 = WORK

fails = 0


def t(name, cond, info=""):
    """One check: PASS / FAIL line, counted in fails."""
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(info)))
    if not cond:
        fails += 1
    return cond


def done():
    print("fails: %d" % fails)
    raise SystemExit(1 if fails else 0)


def raw(name):
    return open(os.path.join(MP3, name), "rb").read()


def tagged(stream, frames, v2_version=3, padding=256):
    t = ID3()
    for f in frames:
        t.add(f)
    buf = io.BytesIO()
    t.save(buf, v2_version=v2_version, padding=lambda info: padding)
    return buf.getvalue() + stream


def syncsafe(n):
    return bytes([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F])


def v22(stream):
    def fr(fid, text):
        body = b"\x00" + text
        return fid + struct.pack(">I", len(body))[1:] + body
    body = fr(b"TT2", b"Old tag title") + fr(b"TP1", b"Old artist") + \
        fr(b"TCO", b"(17)") + bytes(20)
    return b"ID3\x02\x00\x00" + syncsafe(len(body)) + body + stream


def unsync23(stream):
    # v2.3 tag-level unsync; the title contains 0xFF bytes (cp1251 'я')
    def fr(fid, payload):
        return fid + struct.pack(">I", len(payload)) + b"\0\0" + payload
    body = fr(b"TIT2", b"\x00" + "Моя песня я".encode("cp1251")) + \
        fr(b"APIC", b"\x00image/jpeg\x00\x03\x00" + b"\xff\xe0" * 3000) + \
        fr(b"TPE1", b"\x00" + "Ёжик".encode("cp1251"))
    out = bytearray()
    for i, b in enumerate(body):
        out.append(b)
        nxt = body[i + 1] if i + 1 < len(body) else 0
        if b == 0xFF and (nxt == 0 or nxt >= 0xE0):
            out.append(0)
    out += bytes(10)
    return b"ID3\x03\x00\x80" + syncsafe(len(out)) + bytes(out) + stream


def junk_front(stream):
    # garbage with fake syncs before the first real frame
    return b"\xff\xfb\x10\x00" + b"\x00\xff\xe3" * 200 + stream


def audio_start(data):
    if data[:3] == b"ID3":
        s = data[6:10]
        n = (s[0] << 21) | (s[1] << 14) | (s[2] << 7) | s[3]
        return 10 + n
    return 0




def row(text, label):
    for line in text.splitlines():
        if label in line:
            return line
    return ""
