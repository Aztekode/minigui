PORT_NAME := minigui
PRIV_DIR := priv
C_SRC := c_src/minigui_port.c

UNAME_S := $(shell uname -s 2>/dev/null || echo unknown)
IS_WINDOWS := 0
ifeq ($(OS),Windows_NT)
IS_WINDOWS := 1
endif
ifneq (,$(findstring MINGW,$(UNAME_S)))
IS_WINDOWS := 1
endif
ifneq (,$(findstring MSYS,$(UNAME_S)))
IS_WINDOWS := 1
endif
ifneq (,$(findstring CYGWIN,$(UNAME_S)))
IS_WINDOWS := 1
endif

.PHONY: all port gleam demo clean

all: port gleam

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

port: $(PRIV_DIR)
ifeq ($(IS_WINDOWS),1)
	@if command -v gcc >/dev/null 2>&1; then \
		gcc -O2 -Wall -Wextra -o $(PRIV_DIR)/$(PORT_NAME).exe $(C_SRC) -luser32 -lgdi32; \
	elif command -v cl >/dev/null 2>&1; then \
		MSYS2_ARG_CONV_EXCL="*" cl.exe /nologo /O2 /Fe:$(PRIV_DIR)/$(PORT_NAME).exe $(C_SRC) user32.lib gdi32.lib; \
	else \
		echo "Windows: install MSVC (cl) or MinGW (gcc) to build the port."; \
		exit 1; \
	fi
else ifeq ($(UNAME_S),Linux)
	$(CC) -O2 -Wall -Wextra -o $(PRIV_DIR)/$(PORT_NAME) $(C_SRC) $$(pkg-config --cflags --libs gtk+-3.0) -pthread
else ifeq ($(UNAME_S),Darwin)
	@echo "macOS: there is no native backend yet. Use headless mode (MINIGUI_HEADLESS=1) or implement Cocoa."
	$(CC) -O2 -Wall -Wextra -o $(PRIV_DIR)/$(PORT_NAME) $(C_SRC)
else
	@echo "Unknown system. Compile c_src/minigui_port.c manually for your platform."
endif

	@# Compatibility with the previous name during development
	@if [ -f "$(PRIV_DIR)/minigui" ]; then cp -f "$(PRIV_DIR)/minigui" "$(PRIV_DIR)/minigui_port" 2>/dev/null || true; fi
	@if [ -f "$(PRIV_DIR)/minigui.exe" ]; then cp -f "$(PRIV_DIR)/minigui.exe" "$(PRIV_DIR)/minigui_port.exe" 2>/dev/null || true; fi

gleam:
	gleam build

demo: port
	gleam run -m demo

clean:
	rm -rf build $(PRIV_DIR)
