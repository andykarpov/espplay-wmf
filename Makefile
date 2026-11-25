# ESPPLAY.WMF: Wild Commander plugin, the player of the ESP32 of TS-Conf (ZiFi32)
SRC=$(wildcard src/*.asm)
BINARY=ESPPLAY.WMF
SJASM?=sjasmplus
# python with the z80 and mutagen packages, e.g. a venv: make test PYTHON=venv/bin/python
PYTHON?=python3

all: $(BINARY)

$(BINARY): $(SRC)
	$(SJASM) --nologo --msg=war --inc=src src/main.asm

test: $(BINARY)
	test/gen.sh
	cd test && $(PYTHON) tags.py ../$(BINARY)
	cd test && $(PYTHON) player.py ../$(BINARY)

clean:
	rm -f $(BINARY)

# the SPI stress build: PUSHes of 16 bytes, up to 64 a frame (the ESP log counts them)
stress: $(SRC)
	$(SJASM) --nologo --msg=war --inc=src -DSTRESS=16 src/main.asm
	mv $(BINARY) STRESS.WMF
	$(MAKE) -B $(BINARY)

# the recovery test build: every 200th PUSH loses all its W_ENDs
fault: $(SRC)
	$(SJASM) --nologo --msg=war --inc=src -DFAULT=200 src/main.asm
	mv $(BINARY) FAULT.WMF
	$(MAKE) -B $(BINARY)

.PHONY: all test clean stress fault
