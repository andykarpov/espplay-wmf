# Changelog

## 1.1.0 (2026-11-26)

Needs the ESP firmware of [tslabs/zx-evo#98](https://github.com/tslabs/zx-evo/pull/98) (on top of #97)
for AAC, M4A and radio; MP3 / WAV / Ogg / FLAC and play lists of files work with #97 alone.

- AAC (ADTS: AAC-LC, HE-AAC, HE-AACv2) and M4A: the stream line and the length from the average
  bitrate of the ESP; AAC seeks, M4A does not.
- Play lists `.m3u`, `.m3u8`, `.pls`: entries opened by name relative to the list, `#EXTINF` /
  `TitleN` titles, UTF-8 or CP1251, the row `List: n / m`, Space / P through the list.
- Internet radio: an `http://` / `https://` entry is played by the ESP (`SET_URL` + `AUDIO_URL`);
  the station and the title (ICY) on the screen, `Connecting...`, the error of a dead station.
- No Wi-Fi: the plugin joins the network of `/zifi/gopher.ini` (`[zifi32]` `ssid=` / `password=`).
- Diag (F10): one `#`, the status of a refused START.

## 1.0.1 (2026-11-26)

- Fixed: playback stopped after some minutes of a long file and the plugin
  no longer answered the keys. When the ESP armed its receive DMA later than
  the plugin waited for it, the plugin skipped the data, the ESP kept waiting
  for it, and no later PUSH could get through. The plugin now waits longer
  for the DMA and sends the data even after the wait times out.
- Fixed: after minutes of a long file the sound froze for seconds, then a
  piece came through, then it froze again. The ESP had missed a W_END (the end
  of a PUSH) and every later PUSH lagged one behind. The plugin now sends the
  W_END again while the ESP still waits for the data (status M2S).
- With the ESP firmware of [tslabs/zx-evo#97](https://github.com/tslabs/zx-evo/pull/97)
  from 0d4e52c on, a PUSH whose W_END was lost for good is sent again and taken
  (the ESP announces its armed DMA again): the stream goes on with the file whole.
  With older firmware such a PUSH still stops the stream (Esc works). Why the ESP
  misses a W_END after minutes is not known yet.
- Test builds: `make stress` (16-byte PUSHes, up to 64 a frame) and `make fault`
  (every 200th PUSH loses its W_ENDs).

## 1.0.0 (2026-11-25)

The first release, checked on a Karabas Mini G (TS-Conf core, ESP32-S3 with ZiFi32 and the audio
stream player of [tslabs/zx-evo#97](https://github.com/tslabs/zx-evo/pull/97)).

- Plays MP3, WAV, Ogg Vorbis and FLAC from Wild Commander (Enter, Shift+F3) on the ESP32: the
  plugin reads the file and pushes it over the SPI, the ESP decodes it.
- MP3: ID3v2.2 / 2.3 / 2.4 tags (UTF-16, UTF-8, CP1251), the stream line and the length from the
  frames (Xing / Info / VBRI for VBR). WAV / FLAC / Ogg: the stream line and the length from the ESP.
- Elapsed time from the samples the ESP has played; seek by 10 s (not Ogg), pause, volume in 2 dB
  steps (kept for the next track), next / previous file, plays the panel to its end.
- F10: what the ESP answered and its firmware version; a ZiFi32 without the player is reported.
- Based on the Wild Commander plugin of karabas-megabuzz (`MEGABUZZ.WMF`): its window, tag parser
  and MPEG scan, with the Megabuzz parts taken out.
