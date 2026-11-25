# Changelog

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
