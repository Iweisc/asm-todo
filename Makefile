NASM := nasm -f elf64 -w+all -w+error -w-reloc-rel-dword -w-reloc-abs-qword -w-reloc-abs-dword -I src/common/ -I src/client/ -I src/server/
LD := ld -static -nostdlib -z noexecstack
COMMON := $(wildcard src/common/*.asm src/common/*.inc src/common/crypto/*.asm)

all: build/todo-server build/todo-client

build/todo-server: src/server/*.asm $(COMMON)
	@mkdir -p build
	$(NASM) src/server/server.asm -o build/server.o
	$(LD) build/server.o -o $@

build/todo-client: src/client/*.asm $(COMMON)
	@mkdir -p build
	$(NASM) src/client/client.asm -o build/client.o
	$(LD) build/client.o -o $@

build/crypto-test: tests/crypto_test.asm $(COMMON)
	@mkdir -p build
	$(NASM) tests/crypto_test.asm -o build/crypto-test.o
	$(LD) build/crypto-test.o -o $@

build/ui-test: tests/ui_test.asm tests/ui_messages.asm tests/ui_controls.asm src/client/*.asm $(COMMON)
	@mkdir -p build
	$(NASM) tests/ui_test.asm -o build/ui-test.o
	$(LD) build/ui-test.o -o $@

build/png-test: tests/png_test.asm tests/images/* src/client/inflate.asm src/client/png.asm $(COMMON)
	@mkdir -p build
	$(NASM) tests/png_test.asm -o build/png-test.o
	$(LD) build/png-test.o -o $@

build/font-preview: tests/font_preview.asm src/client/font.asm src/client/draw.asm src/client/text.asm src/client/shapes.asm src/client/icons.asm $(COMMON)
	@mkdir -p build
	$(NASM) tests/font_preview.asm -o build/font-preview.o
	$(LD) build/font-preview.o -o $@

# Renders every text style and icon to build/preview.ppm.
preview: build/font-preview
	./build/font-preview > build/preview.ppm

test: build/crypto-test build/ui-test build/png-test
	./build/crypto-test
	./build/ui-test
	./build/png-test

# Starts the server with ./issues.db, opens a window pinned to that server's key,
# and stops the server when the window closes.
run: all
	@./build/todo-server issues.db & server=$$!; \
	while [ ! -s issues.db.pub ]; do kill -0 $$server 2>/dev/null || exit 1; sleep 0.1; done; \
	./build/todo-client $$(cat issues.db.pub); kill $$server

# Fails on a new function over 150 lines, file over 1500 lines or function
# without a comment above it. tests/lint-baseline lists what was already over.
lint:
	tests/lint.sh

clean:
	rm -rf build

.PHONY: all test preview run lint clean
