# ESPPLAY.WMF: audio player on the ESP32 of TS-Conf

English | [Русский](README.ru.md)

A [Wild Commander](https://github.com/tslabs/zx-evo/tree/master/pentevo/soft/WC) plugin for TS-Conf
(ZX Evolution, Karabas Mini G and others with an ESP32-S3 on the SPI: ZiFi32). It plays **MP3, WAV,
Ogg Vorbis, FLAC, AAC and M4A**, play lists (**M3U, M3U8, PLS**) and **internet radio** from them.
The plugin reads the file from the SD card and pushes it to the ESP32 over the SPI. The ESP32 decodes it and plays it through its sound output, together with the tracker and
the OPL of ZiFi32.

```
+----------------- ZiFi32 Audio Player v1.1.0 -----------------+
| File:   01-kino-gruppa_krovi.mp3                             |
|--------------------------------------------------------------|
| Title:  Группа крови                                         |
| Artist: Кино                                                 |
| Album:  Группа крови                                         |
| Year:   1988      Track: 1/11       Genre: Rock              |
|--------------------------------------------------------------|
| MPEG-1 Layer III  128 kbps CBR  44.1 kHz  Joint Stereo       |
| Decoder: ESP32    Vol: █████████░ -4dB                       |
|--------------------------------------------------------------|
| ► 00:29 ██████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 01:35 |
|                                                              |
|                                                              |
| Buf ████████ 99%                                             |
|--------------------------------------------------------------|
|Spc:next P:prev <>:seek S:pause +-:vol Esc:exit               |
+--------------------------------------------------------------+
```

## What it needs

- **ZiFi32 firmware with the audio stream player** (commands `ESP_CMD_AUDIO_*` 0x90..0x97):
  [tslabs/zx-evo#97](https://github.com/tslabs/zx-evo/pull/97); AAC, M4A and radio need
  [#98](https://github.com/tslabs/zx-evo/pull/98) (0x98, 0x99) on top of it. Until they are merged, take the build
  from [andykarpov/zx-evo `karabas/esp32-release`](https://github.com/andykarpov/zx-evo/tree/karabas/esp32-release).
  For the Karabas Mini G it is in [karabas-go `firmware/esp32-s3`](https://github.com/andykarpov/karabas-go/tree/master/firmware/esp32-s3).
  The protocol is described in `pentevo/esp32/doc/esp32-audio.md` there.
- Wild Commander 1.09 or newer (plugin system `#10`).

## Install

1. Copy `ESPPLAY.WMF` into the `WC` folder of the boot drive.
2. Add it to the `[PLUGINS]` section of `WC/wc.ini`, **before** the other plugins that open MP3 or
   WAV (`GSPLAYER.WMF`, `MEGABUZZ.WMF`). WC gives a file to the first plugin in the list that has
   its extension:

   ```ini
   [PLUGINS]
   ESPPLAY.WMF
   GSPLAYER.WMF -midi_chip=2
   ```

Enter or Shift+F3 ("Play on ESP32") on a `.mp3`, `.wav`, `.ogg`, `.flac`, `.aac`, `.m4a`, `.m3u`,
`.m3u8` or `.pls` file plays it.
If there is no ESP32, or its firmware has no player, a window says so. After a key, Enter opens the
Shift+Enter menu of WC. The plugin's item in the F10 menu shows what the ESP32 answers and its
firmware version.

## Keys

| Key | Action |
|---|---|
| `Space`, `Enter` | next file |
| `P`, `Backspace` | previous file |
| `←` / `→` | seek 10 s back / forward (not in Ogg; past the end: the next file) |
| `S` | pause |
| `+` / `-`, `↑` / `↓` | volume, 2 dB steps (kept for the next track) |
| `Esc` | back to WC |

When a track has played out, the plugin goes on to the next file of the panel. After the last file
it returns to WC.

## Play lists

A `.m3u` / `.m3u8` (one entry a line, `#EXTINF` titles) or `.pls` (`FileN=`, `TitleN=`) plays its
entries in turn; Space / P go to the next / previous entry, and the row **List: n / m** shows where
it is. An entry is a file path relative to the folder of the list (`/` or `\`, `..` works) or a URL
(radio). The text may be UTF-8 or CP1251, found by itself. After the last entry the plugin goes on
with the next file of the panel. An entry that is not there: a window says so, then the next one.

## Radio

An `http://` or `https://` entry of a play list is internet radio: the ESP32 reads the stream over
Wi-Fi itself (MP3, AAC, HE-AAC; the format from the Content-Type; Ogg and FLAC streams are not
checked). **File** shows the
station, **Title** the title the station sends (ICY), and both follow changes. There is no length and
no seek; pause, volume and the keys of the list work. A dropped stream is opened again by the ESP32.
`Connecting...` is shown while it connects; the sound starts when a few seconds are buffered.

If the ESP32 is not on Wi-Fi, the plugin joins the network saved by the
[gopher](https://github.com/andykarpov/karabas-go) browser: `[zifi32]` `ssid=` / `password=` of
`/zifi/gopher.ini`.

## What it shows

- **MP3:** ID3v2.2 / 2.3 / 2.4 tags (title, artist or album artist, album, year, track, genre) in
  UTF-16, UTF-8 or single-byte text, taken as CP1251. The tags are shown in CP866. Cover pictures
  are skipped without reading them. The stream line (MPEG version, layer, bitrate, average for VBR,
  rate, channel mode) and the length come from the frames (Xing / Info / VBRI for VBR).
- **WAV, FLAC, Ogg:** the stream line (format, rate, bits, channels) as the ESP32 reports it. The
  length comes from the ESP32 too; Ogg has none (`--:--`).
- **AAC, M4A:** the stream line with the average bitrate of the ESP32; the length from it.
- The elapsed time is counted from the samples the ESP32 has played. **Buf** is how full its
  512 KB input buffer is.
- A file the ESP32 cannot decode: the error code on the screen, then the next file.

## Limits

- The plugin sends about 270 KB/s: WC reads the SD card by 512-byte sectors, then OTIR to the SPI at
  14 MHz. This covers everything up to FLAC 48 kHz / 24 bit (about 210 KB/s). FLAC 96 kHz / 24 bit
  (about 295 KB/s) runs out of data.
- Ogg Vorbis: no seek, no length. M4A: no seek; the file must have its `moov` before `mdat`
  (`ffmpeg -movflags +faststart`). AAC length is an estimate from the average bitrate.
- Radio: no HLS (`.m3u8` of segments); a play list is read from the SD card, not from a URL.
- Tags of WAV, FLAC and Ogg are not read. ID3v1 (at the end of a file) is not read.
- Minutes are shown up to 99:59.

## Build and tests

[sjasmplus](https://github.com/z00m128/sjasmplus) 1.20:

```
make            # -> ESPPLAY.WMF
```

If `LOADNONE` (`#3D`) does not work on some WC version, build
`sjasmplus --inc=src -DNO_LOADNONE src/main.asm`. Seeking and skipping cover pictures then go
through plain reads, which is slower.

`make test` runs the plugin in a simulator, in a few seconds:

- `test/wcsim.py`: the Z80 of the [z80](https://github.com/kosarev/z80) package and the WC API
  (windows, `LOAD512`, `GIPAGPL`, `LOADNONE`, keys, the 50 Hz counter);
- `test/espsim.py`: the ESP32 on the SPI, with its register protocol and a model of the player of
  ZiFi32 (the 512 KB buffer drained at the rate of the stream, the state registers, the 4-byte
  padding of the DMA).

The tests check:

- tags and encodings;
- that the data reaching the ESP32 is the file from the right offset, after a seek too;
- the commands, keys and exit codes;
- the volume;
- the error and diagnostic windows;
- the screen sizes and the colours.

The test files are made by `test/gen.sh` with `ffmpeg` (libmp3lame, libvorbis, flac). The tests need
Python with the `z80` and `mutagen` packages:

```
python3 -m venv venv && venv/bin/pip install z80 mutagen
make test PYTHON=venv/bin/python
```

The simulator does not replace a check on the hardware: the sound, the bus timing, the glyphs of
the WC font (`►`, `■`, `█`) and the colours are checked only on a real board.

## License

MIT, see [LICENSE](LICENSE). Made from the Wild Commander plugin of
[karabas-megabuzz](https://github.com/andykarpov/karabas-megabuzz) (MIT).
