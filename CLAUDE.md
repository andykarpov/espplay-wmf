# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`ESPPLAY.WMF`: a Wild Commander plugin (plugin system #10, sjasmplus) for TS-Conf with ZiFi32
(ESP32-S3 on the SPI, ports #77 / #57). It plays MP3 / WAV / Ogg / FLAC / AAC / M4A, play lists and radio on the audio stream player of
the ESP firmware (`ESP_CMD_AUDIO_*` 0x90..0x99, tslabs/zx-evo#97 + #98, `pentevo/esp32/doc/esp32-audio.md`;
our fork andykarpov/zx-evo, branch `karabas/esp32-audio` / `karabas/esp32-release`). The plugin only reads the file
and pushes it. It was made from the WC plugin of karabas-megabuzz (`firmware/src/wcplugin`,
MEGABUZZ.WMF): window, ID3 parser, MPEG scan, reader. The Megabuzz backend, clock probing, bass /
treble and the EMU build were taken out, so the two have diverged; fixes to the shared parts
(id3.asm, mpeg.asm, reader.asm, math.asm) may apply to both.

## Layout

- `src/main.asm`: header (extensions MP3 WAV OGG FLA: WC takes 3 letters of `.flac`), entry, main
  loop, keys, seek (offset = audio_start + t * alen / total_sec, then AUDIO_FLUSH with that offset),
  exit, variables (#A800, not in the file; `vol` is in the file, kept while WC keeps the plugin).
- `src/esp.asm`: SPI primitives (WR_REGS / RD_REGS / WR_DATA / W_END), the player commands, the
  stream line of WAV / FLAC / Ogg, the diagnostic window. A PUSH is padded with zeros to a multiple
  of 4 bytes: the DMA of the ESP32-S3 takes words, an odd length stalled the stream on the board.
- `src/ui.asm`: the window; `src/id3.asm`, `src/mpeg.asm` (MP3 only); `src/reader.asm` (buffered
  WC file stream, BUF 2 KB at #B000); `src/math.asm`; `src/wc*.asm` (WC API).
- `test/`: `wcsim.py` (WC), `espsim.py` (the ESP: a model of `audio_stream.cpp`; keep it in step with
  the firmware), `tags.py`, `player.py`, `common.py`, `gen.sh` (ffmpeg test files into test/work).

## Rules

- `make test` (seconds) after every change; a behaviour of the firmware the plugin relies on gets a
  model in espsim.py and a test.
- The window is user-visible UI: a changed layout is shown to the user (the text of the model) first.
- Check on the board (Karabas Mini G, SD2, hwq ticket) before a release; ask before flashing the ESP.
- Release: version in `src/main.asm` (`DEFINE VERSION`), a section in CHANGELOG.md, tag `vX.Y.Z` (CI
  publishes ESPPLAY.WMF); then copy it to karabas-go `software/` by a PR.
