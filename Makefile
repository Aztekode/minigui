PORT_NAME := minigui
PRIV_DIR := priv
C_SRC := c_src/minigui_port.c

UNAME_S := $(shell uname -s 2>/dev/null || echo unknown)

.PHONY: all port gleam demo clean

all: port gleam

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

port: $(PRIV_DIR)
ifeq ($(UNAME_S),Linux)
	$(CC) -O2 -Wall -Wextra -o $(PRIV_DIR)/$(PORT_NAME) $(C_SRC) $$(pkg-config --cflags --libs gtk+-3.0) -pthread
else ifeq ($(UNAME_S),Darwin)
	@echo "macOS: por ahora no hay backend nativo. Usa el modo headless (MINIGUI_HEADLESS=1) o implementa Cocoa."
	$(CC) -O2 -Wall -Wextra -o $(PRIV_DIR)/$(PORT_NAME) $(C_SRC)
else
	@echo "Sistema no reconocido. Compila manualmente c_src/minigui_port.c para tu plataforma."
endif

	@# Compatibilidad con el nombre anterior durante desarrollo
	@if [ -f "$(PRIV_DIR)/minigui" ]; then cp -f "$(PRIV_DIR)/minigui" "$(PRIV_DIR)/minigui_port"; fi

gleam:
	gleam build

demo: port
	gleam run -m demo

clean:
	rm -rf build $(PRIV_DIR)
