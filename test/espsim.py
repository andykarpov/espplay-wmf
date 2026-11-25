"""ESP32 (ZiFi32 audio stream player) on the SPI of TS-Conf, for ESPPLAY.WMF.

The register protocol of ZiFi32 (ports #77 chip select, #57 data; SPI
commands WR_REGS / RD_REGS / WR_DATA / W_END) and a model of the player of
pentevo/esp32/src/main/audio_stream.cpp (tslabs/zx-evo): a 512 KB input ring that the decoder drains
at the byte rate of the stream, the state block of AUDIO_GET_STATE.
"""
import struct

from wcsim import Sim

SPI_DATA, SPI_CTRL = 0x57, 0x77
CS_ON, CS_OFF = 0x13, 0x03
WR_REGS, RD_REGS, WR_DATA, W_END = 1, 2, 3, 7

ST_IDLE, ST_READY, ST_BUSY, ST_M2S = 0, 1, 2, 3
ERR_INV_COMMAND, ERR_INV_STATE, ERR_INV_SIZE = 0x80, 0x82, 0x84

A_IDLE, A_WAIT, A_PLAY, A_DRAIN, A_ENDED, A_ERROR = range(6)
IN_SIZE = 512 * 1024


class EspSim(Sim):
    def __init__(self, wmf, data, name=b"test.mp3", esp=True, audio=True,
                 rate=44100, channels=2, bits=0, total=0, byte_rate=None,
                 seekable=True, busy_polls=2, fmt_found=None, fail=0, late_push=(), late_polls=70000,
                 lost_wend=(), rearm=False, bitrate=0,
                 radio_meta=None, radio_fail=0, connect_frames=10, net=2, wifi=None, **kw):
        self.esp = esp                  # an ESP answers on the SPI at all
        self.audio = audio              # its firmware has the audio player
        self.rate = rate
        self.channels = channels
        self.bits_ = bits
        self.total = total
        self.byte_rate = byte_rate or 16000
        self.seekable = seekable
        self.busy_polls = busy_polls
        # the receiver task of the ESP arms its DMA late on these PUSHes (0 = the
        # first): M2S only after late_polls status reads, data sent before that
        # is lost, and a PUSH while the DMA is armed gets no M2S (one RX at a time)
        self.late_push = set(late_push)
        self.late_polls = late_polls
        self.pushes = 0
        self.lost_wend = set(lost_wend)     # the W_END of these PUSHes is not seen (once)
        self.wends = 0
        self.arm_in = 0
        self.armed = False
        self.queued = None              # size of a PUSH queued behind the armed DMA
        # the firmware of 0d4e52c: a PUSH while the DMA is armed gets M2S again and
        # the armed DMA takes its data (type and size read at the W_END)
        self.rearm = rearm
        self.fmt_found = fmt_found
        self.bitrate = bitrate          # ESP_REG_AUDIO_BITRATE (AAC)
        # radio: {frame after AUDIO_URL: (station, title)} (UTF-8), the error of a dead URL
        self.radio_meta = radio_meta or {}
        self.radio_fail = radio_fail
        self.connect_frames = connect_frames
        self.radio = False
        self.radio_t = 0
        self.urls = []
        self.url = b""
        self.xfer = None
        self.meta = [b"", b""]
        self.meta_seq = 0
        self.net = net                  # NETSTATE: 2 connected
        self.wifi = wifi                # (ssid, password) AP_CONNECT accepts
        self.ap = [b"", b""]
        self.joins = []
        self.fail = fail                # an error code: the decoder refuses the stream
        self.regs = bytearray(64)
        self.cs = False
        self.spi = bytearray()          # bytes of the current CS frame (out)
        self.rd_ptr = None
        self.data_rx = None
        self.busy_left = 0
        self.a_state = A_IDLE
        self.a_fmt = 0
        self.a_end = False
        self.paused = False
        self.atten = 0
        self.ring = 0                   # bytes buffered
        self.consumed = 0               # bytes decoded since START / FLUSH
        self.played = 0
        self.esp_streams = []           # (offset of FLUSH or None, bytes) per START / FLUSH
        self.cur = None
        self.cmds = []
        self.vols = []
        self.start_fmts = []
        self.refused = 0
        self.opened = False
        self.underruns = 0              # the ring ran empty while playing, before END
        super().__init__(wmf, data, name=name, **kw)

    # -- ports ------------------------------------------------------------
    def port_in(self, port):
        if (port & 0xFF) == SPI_DATA:
            if not self.esp or not self.cs:
                return 0xFF
            if self.rd_ptr is None:
                return 0xFF                # a dummy read
            if self.rd_skip:
                self.rd_skip -= 1
                return 0xFF
            r = self.read_reg(self.rd_ptr)
            self.rd_ptr += 1
            return r
        return super().port_in(port)

    def port_out(self, port, value):
        p = port & 0xFF
        if p == SPI_CTRL:
            on = value == CS_ON
            if self.cs and not on:
                self.cs_end()
            if on and not self.cs:
                self.spi = bytearray()
                self.rd_ptr = None
                self.rd_skip = 0
            self.cs = on
            return
        if p == SPI_DATA:
            if not self.cs or not self.esp:
                return
            self.spi.append(value)
            if len(self.spi) == 2 and self.spi[0] == RD_REGS:
                self.rd_ptr = self.spi[1]
                self.rd_skip = 2          # the two dummy reads of RD_REGS
            return
        return super().port_out(port, value)

    def read_reg(self, r):
        if r == 1 and self.arm_in > 0:
            self.arm_in -= 1
            if not self.arm_in:
                self.armed = True
                self.regs[1] = ST_M2S
            return self.regs[1]
        if r == 1 and self.busy_left > 0:
            self.busy_left -= 1
            return ST_BUSY
        return self.regs[r & 63]

    def cs_end(self):
        outs = self.spi
        if not outs:
            return
        cmd = outs[0]
        if cmd == WR_REGS and len(outs) >= 2:
            a = outs[1]
            for i, v in enumerate(outs[2:]):
                self.regs[(a + i) & 63] = v
            if a == 0 and len(outs) >= 3:
                self.command(outs[2])
        elif cmd == WR_DATA:
            self.data_rx = bytes(outs[1:])
        elif cmd == W_END:
            k = self.wends
            self.wends += 1
            if k in self.lost_wend:
                return                  # missed: the DMA stays armed, status M2S
            self.push_done()

    # -- the player -------------------------------------------------------
    def status(self, s):
        self.regs[1] = s
        self.busy_left = self.busy_polls

    def put_state(self):
        r = self.regs
        flags = (1 if self.seekable and self.opened and not self.radio else 0) | (2 if self.paused else 0) | \
            (4 if self.a_end else 0) | (8 if self.radio else 0) | \
            (0x10 if self.radio and self.a_state == A_WAIT else 0)
        r[0x10] = self.a_state
        r[0x11] = (self.fmt_found or self.a_fmt) if self.opened else 0
        r[0x12] = self.channels if self.opened else 0
        r[0x13] = flags
        struct.pack_into("<IIIII", r, 0x14, IN_SIZE - self.ring, self.rate if self.opened else 0,
                         self.played & 0xFFFFFFFF, self.total if self.opened else 0, self.ring)
        struct.pack_into("<HBBIB", r, 0x28, 0, self.regs[0x2A] if self.a_state == A_ERROR else 0,
                         self.bits_ if self.opened else 0, self.bitrate if self.opened else 0,
                         self.meta_seq & 0xFF)

    def command(self, c):
        self.cmds.append(c)
        if self.arm_in:                 # the late DMA got armed before this command came
            self.arm_in = 0
            self.armed = True
        if not self.audio and 0x90 <= c <= 0x97:
            self.status(ERR_INV_COMMAND)
            return
        if c in (0x90, 0x96, 0x98):                      # START / STOP / URL end a radio
            self.radio = False
            self.meta = [b"", b""]
            self.meta_seq += 1
        if c in (0x13, 0x14):                            # SET_AP_NAME / PWD
            n = self.regs[2]
            self.ap[c - 0x13] = bytes(self.regs[3:3 + n])
            self.status(ST_READY)
            return
        if c == 0x16:                                    # AP_CONNECT
            self.joins.append(tuple(self.ap))
            if self.wifi and tuple(x.encode() for x in self.wifi) == tuple(self.ap):
                self.net = 2
            self.status(ST_READY)
            return
        if c == 0x11:                                    # NETSTATE
            self.regs[2] = self.net
            self.status(ST_READY)
            return
        if c == 0x18:                                    # SET_URL: DMA like PUSH
            self.push_n = struct.unpack_from("<I", self.regs, 3)[0]
            self.xfer = "url"
            self.regs[1] = ST_M2S
            self.busy_left = self.busy_polls
            return
        if c == 0x98:                                    # AUDIO_URL
            assert self.url, "AUDIO_URL without a URL"
            if self.net != 2:
                self.radio_fail = self.radio_fail or 0xC2
            self.urls.append(self.url)
            self.start_fmts.append(self.regs[2])
            self.a_state = A_WAIT
            self.ring = self.consumed = self.played = 0
            self.a_end = self.paused = False
            self.opened = False
            self.radio = True
            self.radio_t = 0
            self.cur = [None, bytearray()]
            self.esp_streams.append(self.cur)
            self.put_state()
            self.status(ST_READY)
            return
        if c == 0x99:                                    # GET_META
            m = self.meta[1 if self.regs[2] else 0][:56]
            self.regs[2] = len(m)
            self.regs[3:3 + len(m)] = m
            self.status(ST_READY)
            return
        if c == 0x90:                                    # START
            self.a_fmt = self.regs[2]
            self.start_fmts.append(self.a_fmt)
            self.a_state = A_WAIT
            self.ring = self.consumed = self.played = 0
            self.a_end = self.paused = False
            self.opened = False
            self.cur = [None, bytearray()]
            self.esp_streams.append(self.cur)
        elif c == 0x91:                                  # PUSH
            n = struct.unpack_from("<I", self.regs, 3)[0]
            if self.a_state not in (A_WAIT, A_PLAY) or self.a_end:
                self.put_state()
                self.status(ERR_INV_STATE)
                return
            if not 0 < n <= 16384 or n > IN_SIZE - self.ring:
                self.refused += 1
                self.put_state()
                self.status(ERR_INV_SIZE)
                return
            if self.rearm and self.armed:
                self.push_n = n
                self.data_rx = None
                self.regs[1] = ST_M2S
                return
            if self.armed or self.arm_in:
                # queued behind the armed DMA (the rx queue of 2e9589d): the
                # command handler says BUSY over the M2S of the armed one; it
                # arms when that one is done
                self.queued = n
                self.regs[1] = ST_BUSY
                return
            self.push_n = n
            k = self.pushes
            self.pushes += 1
            if k in self.late_push:
                self.arm_in = self.late_polls
                return
            self.armed = True
            self.regs[1] = ST_M2S
            self.busy_left = self.busy_polls
            return
        elif c == 0x92:                                  # END
            self.a_end = True
        elif c == 0x93:                                  # FLUSH
            off = struct.unpack_from("<I", self.regs, 7)[0]
            self.ring = self.consumed = self.played = 0
            self.a_state = A_WAIT
            self.a_end = False
            self.cur = [off, bytearray()]
            self.esp_streams.append(self.cur)
        elif c == 0x94:                                  # PAUSE
            self.paused = bool(self.regs[2])
        elif c == 0x95:                                  # VOLUME
            self.atten = self.regs[2]
            self.vols.append(self.atten)
        elif c == 0x96:                                  # STOP
            self.a_state = A_IDLE
            self.ring = 0
        elif c == 0x97:                                  # GET_STATE
            pass
        elif c == 0x02:                                  # GET_VER
            self.regs[2] = 1
            self.regs[3:5] = b"\x0a\x00"
            self.regs[5:8] = bytes([0, 6, 4])
        else:
            self.status(ERR_INV_COMMAND)
            return
        self.put_state()
        self.status(ST_READY)

    def push_done(self):
        if not self.armed or self.data_rx is None:
            if not self.armed:
                self.data_rx = None     # nothing armed: the data is lost
            return
        self.armed = False
        d = self.data_rx[:self.push_n]
        if self.xfer == "url":
            self.xfer = None
            assert len(self.data_rx) == (self.push_n + 3) & ~3, "SET_URL not padded to 4"
            self.url = bytes(d)
            self.data_rx = None
            self.status(ST_READY)
            return
        assert len(d) == self.push_n, ("PUSH: %d bytes sent, %d announced" % (len(self.data_rx), self.push_n))
        # the DMA of the ESP32-S3 takes words: the host pads to a multiple of 4
        assert len(self.data_rx) == (self.push_n + 3) & ~3, ("PUSH of %d bytes sent as %d" % (self.push_n, len(self.data_rx)))
        self.cur[1] += d
        self.ring += len(d)
        self.data_rx = None
        self.put_state()
        if self.queued is not None:
            self.push_n = self.queued
            self.queued = None
            self.pushes += 1
            self.armed = True
            self.regs[1] = ST_M2S
            return
        self.status(ST_READY)

    def new_frame(self):
        super().new_frame()
        f = getattr(self, "on_frame", {}).get(self.frame)
        if f:
            f()
        if self.radio and not self.paused:
            self.radio_t += 1
            if self.a_state == A_WAIT and self.radio_t >= self.connect_frames:
                if self.radio_fail:
                    self.a_state = A_ERROR
                    self.regs[0x2A] = self.radio_fail
                    self.put_state()
                    return
                self.a_state = A_PLAY
                self.opened = True
            if self.radio_t in self.radio_meta:
                st, ti = self.radio_meta[self.radio_t]
                self.meta = [st.encode(), ti.encode()]
                self.meta_seq += 1
            if self.a_state == A_PLAY:
                self.played += self.rate // 50
            return
        if self.a_state in (A_WAIT, A_PLAY, A_DRAIN) and not self.paused:
            if self.a_state == A_WAIT and self.a_end and not self.ring:
                self.fail = self.fail or 0xC1   # the ESP: no headers, the decoder refuses
            if self.a_state == A_WAIT and self.fail and (self.ring >= 4096 or self.a_end):
                self.a_state = A_ERROR
                self.regs[0x2A] = self.fail
                self.put_state()
                return
            if self.a_state == A_WAIT and self.ring >= 4096 or (self.a_state == A_WAIT and self.a_end and self.ring):
                self.a_state = A_PLAY
                self.opened = True
            if self.a_state in (A_PLAY, A_DRAIN):
                if self.ring < self.byte_rate // 50 and not self.a_end and self.a_state == A_PLAY:
                    self.underruns += 1
                d = min(self.ring, self.byte_rate // 50)
                self.ring -= d
                self.consumed += d
                self.played = self.consumed * self.rate // self.byte_rate
                if self.ring == 0 and self.a_end:
                    self.a_state = A_ENDED
