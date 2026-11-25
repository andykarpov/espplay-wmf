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

.PHONY: all test clean
