// minigui_port.c (protocol v1)
// External port for Erlang/Gleam using {packet, 2}.
//
// Handshake:
//   HELLO      0x00 + u16 version
//   HELLO_ACK  0xF0 + u16 version + u32 capabilities
//
// Commands (all include request_id u32 big-endian):
//   CREATE_WINDOW 0x10 + u32 req + title utf-8
//   SET_LABEL     0x11 + u32 req + text utf-8
//   SET_TEXT      0x12 + u32 req + text utf-8
//   ADD_BUTTON    0x13 + u32 req + u8 id + label utf-8
//   RUN           0x14 + u32 req
//   QUIT          0x15 + u32 req
//
// Responses:
//   OK            0x70 + u32 req
//   ERR           0x71 + u32 req + msg utf-8
//
// Events:
//   BUTTON_CLICKED 0x81 + u8 id
//   CLOSED         0x82
//   LOG            0x83 + msg utf-8
//   TEXT_CHANGED   0x84 + text utf-8
//   KEY_DOWN       0x85 + u32 keycode
//   ERROR          0x86 + msg utf-8

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <pthread.h>
#  include <time.h>
#  include <unistd.h>
#  include <gtk/gtk.h>
#endif

#define PROTOCOL_VERSION 1

// ---------- thread-safe output ----------
#ifdef _WIN32
static CRITICAL_SECTION g_out_lock;
static void out_lock_init(void) { InitializeCriticalSection(&g_out_lock); }
static void out_lock(void) { EnterCriticalSection(&g_out_lock); }
static void out_unlock(void) { LeaveCriticalSection(&g_out_lock); }
#else
static pthread_mutex_t g_out_lock = PTHREAD_MUTEX_INITIALIZER;
static void out_lock_init(void) { (void)pthread_mutex_init(&g_out_lock, NULL); }
static void out_lock(void) { (void)pthread_mutex_lock(&g_out_lock); }
static void out_unlock(void) { (void)pthread_mutex_unlock(&g_out_lock); }
#endif

static void send_packet(const uint8_t* data, uint16_t len) {
  uint8_t header[2];
  header[0] = (uint8_t)((len >> 8) & 0xFF);
  header[1] = (uint8_t)(len & 0xFF);
  out_lock();
  (void)fwrite(header, 1, 2, stdout);
  if (len > 0) (void)fwrite(data, 1, len, stdout);
  (void)fflush(stdout);
  out_unlock();
}

static void send_ok(uint32_t req) {
  uint8_t buf[1 + 4];
  buf[0] = 0x70;
  buf[1] = (uint8_t)((req >> 24) & 0xFF);
  buf[2] = (uint8_t)((req >> 16) & 0xFF);
  buf[3] = (uint8_t)((req >> 8) & 0xFF);
  buf[4] = (uint8_t)(req & 0xFF);
  send_packet(buf, (uint16_t)sizeof(buf));
}

static void send_err(uint32_t req, const char* msg) {
  size_t msg_len = msg ? strlen(msg) : 0;
  if (msg_len > 65000) msg_len = 65000;
  uint16_t len = (uint16_t)(1 + 4 + msg_len);
  uint8_t* buf = (uint8_t*)malloc(len);
  if (!buf) return;
  buf[0] = 0x71;
  buf[1] = (uint8_t)((req >> 24) & 0xFF);
  buf[2] = (uint8_t)((req >> 16) & 0xFF);
  buf[3] = (uint8_t)((req >> 8) & 0xFF);
  buf[4] = (uint8_t)(req & 0xFF);
  if (msg_len) memcpy(buf + 5, msg, msg_len);
  send_packet(buf, len);
  free(buf);
}

static void send_log(const char* msg) {
  size_t msg_len = msg ? strlen(msg) : 0;
  if (msg_len > 65000) msg_len = 65000;
  uint16_t len = (uint16_t)(1 + msg_len);
  uint8_t* buf = (uint8_t*)malloc(len);
  if (!buf) return;
  buf[0] = 0x83;
  if (msg_len) memcpy(buf + 1, msg, msg_len);
  send_packet(buf, len);
  free(buf);
}

static void send_error_event(const char* msg) {
  size_t msg_len = msg ? strlen(msg) : 0;
  if (msg_len > 65000) msg_len = 65000;
  uint16_t len = (uint16_t)(1 + msg_len);
  uint8_t* buf = (uint8_t*)malloc(len);
  if (!buf) return;
  buf[0] = 0x86;
  if (msg_len) memcpy(buf + 1, msg, msg_len);
  send_packet(buf, len);
  free(buf);
}

static void send_button_clicked(uint8_t id) {
  uint8_t buf[2] = {0x81, id};
  send_packet(buf, 2);
}

static void send_closed(void) {
  uint8_t buf[1] = {0x82};
  send_packet(buf, 1);
}

static void terminate_self(void) {
#ifdef _WIN32
  ExitProcess(0);
#else
  exit(0);
#endif
}

static void send_text_changed(const char* text) {
  size_t n = text ? strlen(text) : 0;
  if (n > 65000) n = 65000;
  uint16_t len = (uint16_t)(1 + n);
  uint8_t* buf = (uint8_t*)malloc(len);
  if (!buf) return;
  buf[0] = 0x84;
  if (n) memcpy(buf + 1, text, n);
  send_packet(buf, len);
  free(buf);
}

static void send_key_down(uint32_t keycode) {
  uint8_t buf[1 + 4];
  buf[0] = 0x85;
  buf[1] = (uint8_t)((keycode >> 24) & 0xFF);
  buf[2] = (uint8_t)((keycode >> 16) & 0xFF);
  buf[3] = (uint8_t)((keycode >> 8) & 0xFF);
  buf[4] = (uint8_t)(keycode & 0xFF);
  send_packet(buf, (uint16_t)sizeof(buf));
}

// ---------- read ----------
static int read_exact(uint8_t* out, size_t len) {
  size_t got = 0;
  while (got < len) {
    size_t n = fread(out + got, 1, len - got, stdin);
    if (n == 0) return 0;
    got += n;
  }
  return 1;
}

static int read_packet(uint8_t** out_buf, uint16_t* out_len) {
  uint8_t header[2];
  if (!read_exact(header, 2)) return 0;
  uint16_t len = (uint16_t)((header[0] << 8) | header[1]);
  uint8_t* buf = (uint8_t*)malloc(len ? len : 1);
  if (!buf) return 0;
  if (len && !read_exact(buf, len)) {
    free(buf);
    return 0;
  }
  *out_buf = buf;
  *out_len = len;
  return 1;
}

static uint32_t read_u32be(const uint8_t* p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static uint16_t read_u16be(const uint8_t* p) {
  return (uint16_t)(((uint16_t)p[0] << 8) | (uint16_t)p[1]);
}

static char* dup_bytes_as_cstr(const uint8_t* bytes, size_t len) {
  char* s = (char*)malloc(len + 1);
  if (!s) return NULL;
  memcpy(s, bytes, len);
  s[len] = '\0';
  return s;
}

static int is_headless_forced(void) {
  const char* v = getenv("MINIGUI_HEADLESS");
  return v && (strcmp(v, "1") == 0 || strcmp(v, "true") == 0 || strcmp(v, "TRUE") == 0);
}

// ---------- shared state ----------
typedef struct {
  char* title;
  char* label;
  char* text;
  uint8_t button_id;
  char* button_label;
  int running;
  int ui_started;
} gui_state_t;

static void state_init(gui_state_t* st) {
  st->title = NULL;
  st->label = NULL;
  st->text = NULL;
  st->button_id = 1;
  st->button_label = NULL;
  st->running = 1;
  st->ui_started = 0;
}

static void state_free(gui_state_t* st) {
  free(st->title);
  free(st->label);
  free(st->text);
  free(st->button_label);
}

#ifdef _WIN32
// ---------------- Windows (Win32) ----------------
static gui_state_t* g_state = NULL;
static HWND g_hwnd = NULL;
static HWND g_label = NULL;
static HWND g_edit = NULL;
static HWND g_button = NULL;

#define WM_MINIGUI_APPLY (WM_APP + 1)

static wchar_t* utf8_to_wide(const char* s) {
  if (!s) {
    wchar_t* w = (wchar_t*)calloc(1, sizeof(wchar_t));
    return w;
  }
  int needed = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  if (needed <= 0) return NULL;
  wchar_t* w = (wchar_t*)malloc((size_t)needed * sizeof(wchar_t));
  if (!w) return NULL;
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, needed);
  return w;
}

static void win_apply_state(void) {
  if (!g_hwnd) return;
  wchar_t* wtitle = utf8_to_wide(g_state->title ? g_state->title : "minigui");
  SetWindowTextW(g_hwnd, wtitle ? wtitle : L"minigui");
  free(wtitle);

  wchar_t* wlabel = utf8_to_wide(g_state->label ? g_state->label : "");
  SetWindowTextW(g_label, wlabel ? wlabel : L"");
  free(wlabel);

  wchar_t* wtext = utf8_to_wide(g_state->text ? g_state->text : "");
  SetWindowTextW(g_edit, wtext ? wtext : L"");
  free(wtext);

  wchar_t* wbtn = utf8_to_wide(g_state->button_label ? g_state->button_label : "OK");
  SetWindowTextW(g_button, wbtn ? wbtn : L"OK");
  free(wbtn);
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  switch (msg) {
    case WM_MINIGUI_APPLY:
      win_apply_state();
      return 0;
    case WM_COMMAND: {
      if (HIWORD(wparam) == BN_CLICKED && (HWND)lparam == g_button) {
        send_button_clicked(g_state ? g_state->button_id : 1);
        return 0;
      }
      if (HIWORD(wparam) == EN_CHANGE && (HWND)lparam == g_edit) {
        int len = GetWindowTextLengthW(g_edit);
        wchar_t* wbuf = (wchar_t*)malloc((size_t)(len + 1) * sizeof(wchar_t));
        if (wbuf) {
          GetWindowTextW(g_edit, wbuf, len + 1);
          int needed = WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, NULL, 0, NULL, NULL);
          char* utf8 = (char*)malloc((size_t)needed);
          if (utf8) {
            WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, utf8, needed, NULL, NULL);
            send_text_changed(utf8);
            free(utf8);
          }
          free(wbuf);
        }
        return 0;
      }
      break;
    }
    case WM_KEYDOWN:
      send_key_down((uint32_t)wparam);
      break;
    case WM_DESTROY:
      send_closed();
      PostQuitMessage(0);
      terminate_self();
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static DWORD WINAPI ui_thread_proc(LPVOID param) {
  g_state = (gui_state_t*)param;
  HINSTANCE hinst = GetModuleHandleW(NULL);
  const wchar_t* class_name = L"MiniGuiWindowClassV1";

  WNDCLASSW wc;
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = WndProc;
  wc.hInstance = hinst;
  wc.lpszClassName = class_name;
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
  RegisterClassW(&wc);

  g_hwnd = CreateWindowExW(0, class_name, L"minigui", WS_OVERLAPPEDWINDOW,
                          CW_USEDEFAULT, CW_USEDEFAULT, 520, 220,
                          NULL, NULL, hinst, NULL);

  g_label = CreateWindowExW(0, L"STATIC", L"", WS_VISIBLE | WS_CHILD,
                            20, 20, 460, 20, g_hwnd, NULL, hinst, NULL);

  g_edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_VISIBLE | WS_CHILD | ES_LEFT,
                           20, 50, 460, 24, g_hwnd, (HMENU)(intptr_t)2, hinst, NULL);

  g_button = CreateWindowExW(0, L"BUTTON", L"OK", WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
                             20, 90, 120, 32, g_hwnd, (HMENU)(intptr_t)1, hinst, NULL);

  win_apply_state();

  ShowWindow(g_hwnd, SW_SHOW);
  UpdateWindow(g_hwnd);

  MSG m;
  while (GetMessageW(&m, NULL, 0, 0) > 0) {
    TranslateMessage(&m);
    DispatchMessageW(&m);
  }
  return 0;
}

static void ui_start(gui_state_t* st) {
  if (st->ui_started) return;
  st->ui_started = 1;
  if (is_headless_forced()) {
    send_log("minigui_port: headless mode (windows).");
    Sleep(300);
    send_text_changed(st->text ? st->text : "");
    Sleep(300);
    send_button_clicked(st->button_id);
    Sleep(300);
    send_closed();
    return;
  }
  HANDLE th = CreateThread(NULL, 0, ui_thread_proc, st, 0, NULL);
  (void)th;
}

static void ui_quit(void) {
  if (g_hwnd) PostMessageW(g_hwnd, WM_CLOSE, 0, 0);
}

#else
// ---------------- Linux (GTK3) ----------------
static gui_state_t* g_state = NULL;
static GtkWidget* g_window = NULL;
static GtkWidget* g_label = NULL;
static GtkWidget* g_entry = NULL;
static GtkWidget* g_button = NULL;

static gboolean on_key_press(GtkWidget* _w, GdkEventKey* event, gpointer _data) {
  send_key_down((uint32_t)event->keyval);
  return FALSE;
}

static void on_button_clicked(GtkButton* _btn, gpointer _data) {
  send_button_clicked(g_state ? g_state->button_id : 1);
}

static void on_entry_changed(GtkEditable* _editable, gpointer _data) {
  const char* text = gtk_entry_get_text(GTK_ENTRY(g_entry));
  send_text_changed(text ? text : "");
}

static void on_destroy(GtkWidget* _w, gpointer _data) {
  send_closed();
  gtk_main_quit();
  terminate_self();
}

static gboolean apply_state_idle(gpointer _data) {
  if (!g_window) return G_SOURCE_REMOVE;
  gtk_window_set_title(GTK_WINDOW(g_window), g_state->title ? g_state->title : "minigui");
  gtk_label_set_text(GTK_LABEL(g_label), g_state->label ? g_state->label : "");
  gtk_entry_set_text(GTK_ENTRY(g_entry), g_state->text ? g_state->text : "");
  gtk_button_set_label(GTK_BUTTON(g_button), g_state->button_label ? g_state->button_label : "OK");
  return G_SOURCE_REMOVE;
}

static void* ui_thread_proc(void* param) {
  g_state = (gui_state_t*)param;

  if (is_headless_forced()) {
    send_log("minigui_port: headless mode (linux).");
    struct timespec ts = {0, 300 * 1000 * 1000};
    nanosleep(&ts, NULL);
    send_text_changed(g_state->text ? g_state->text : "");
    nanosleep(&ts, NULL);
    send_button_clicked(g_state->button_id);
    nanosleep(&ts, NULL);
    send_closed();
    return NULL;
  }

  int argc = 0;
  char** argv = NULL;
  gtk_init(&argc, &argv);

  g_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(g_window), 520, 220);
  g_signal_connect(g_window, "destroy", G_CALLBACK(on_destroy), NULL);

  GtkWidget* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_container_set_border_width(GTK_CONTAINER(box), 12);
  gtk_container_add(GTK_CONTAINER(g_window), box);

  g_label = gtk_label_new("");
  gtk_box_pack_start(GTK_BOX(box), g_label, FALSE, FALSE, 0);

  g_entry = gtk_entry_new();
  gtk_box_pack_start(GTK_BOX(box), g_entry, FALSE, FALSE, 0);
  g_signal_connect(g_entry, "changed", G_CALLBACK(on_entry_changed), NULL);
  g_signal_connect(g_entry, "key-press-event", G_CALLBACK(on_key_press), NULL);

  g_button = gtk_button_new_with_label("OK");
  gtk_box_pack_start(GTK_BOX(box), g_button, FALSE, FALSE, 0);
  g_signal_connect(g_button, "clicked", G_CALLBACK(on_button_clicked), NULL);

  apply_state_idle(NULL);

  gtk_widget_show_all(g_window);
  gtk_main();
  return NULL;
}

static void ui_start(gui_state_t* st) {
  if (st->ui_started) return;
  st->ui_started = 1;
  pthread_t th;
  pthread_create(&th, NULL, ui_thread_proc, st);
  pthread_detach(th);
}

static void ui_apply_async(void) {
  if (g_window) g_idle_add(apply_state_idle, NULL);
}

static void ui_quit(void) {
  if (g_window) g_idle_add((GSourceFunc)gtk_main_quit, NULL);
}
#endif

static void send_hello_ack(void) {
  uint8_t buf[1 + 2 + 4];
  buf[0] = 0xF0;
  buf[1] = 0;
  buf[2] = PROTOCOL_VERSION;
  // capabilities: bit0=window, bit1=label, bit2=textbox, bit3=button
  uint32_t caps = 0x0F;
  buf[3] = (uint8_t)((caps >> 24) & 0xFF);
  buf[4] = (uint8_t)((caps >> 16) & 0xFF);
  buf[5] = (uint8_t)((caps >> 8) & 0xFF);
  buf[6] = (uint8_t)(caps & 0xFF);
  send_packet(buf, (uint16_t)sizeof(buf));
}

int main(void) {
  out_lock_init();

  gui_state_t st;
  state_init(&st);

  for (;;) {
    uint8_t* buf = NULL;
    uint16_t len = 0;
    if (!read_packet(&buf, &len)) break;
    if (len == 0) {
      free(buf);
      continue;
    }

    uint8_t cmd = buf[0];

    if (cmd == 0x00) { // HELLO
      if (len < 3) {
        send_error_event("invalid HELLO");
      } else {
        uint16_t ver = read_u16be(buf + 1);
        if (ver != PROTOCOL_VERSION) {
          send_error_event("protocol mismatch");
        }
        send_hello_ack();
      }
      free(buf);
      continue;
    }

    if (len < 1 + 4) {
      free(buf);
      continue;
    }

    uint32_t req = read_u32be(buf + 1);
    const uint8_t* payload = buf + 5;
    size_t payload_len = (size_t)(len - 5);

    switch (cmd) {
      case 0x10: { // CREATE_WINDOW
        free(st.title);
        st.title = dup_bytes_as_cstr(payload, payload_len);
        if (!st.title) st.title = dup_bytes_as_cstr((const uint8_t*)"minigui", 6);
#ifndef _WIN32
        ui_apply_async();
#else
        if (g_hwnd) PostMessageW(g_hwnd, WM_MINIGUI_APPLY, 0, 0);
#endif
        send_ok(req);
        break;
      }
      case 0x11: { // SET_LABEL
        free(st.label);
        st.label = dup_bytes_as_cstr(payload, payload_len);
        if (!st.label) st.label = dup_bytes_as_cstr((const uint8_t*)"", 0);
#ifndef _WIN32
        ui_apply_async();
#else
        if (g_hwnd) PostMessageW(g_hwnd, WM_MINIGUI_APPLY, 0, 0);
#endif
        send_ok(req);
        break;
      }
      case 0x12: { // SET_TEXT
        free(st.text);
        st.text = dup_bytes_as_cstr(payload, payload_len);
        if (!st.text) st.text = dup_bytes_as_cstr((const uint8_t*)"", 0);
#ifndef _WIN32
        ui_apply_async();
#else
        if (g_hwnd) PostMessageW(g_hwnd, WM_MINIGUI_APPLY, 0, 0);
#endif
        send_ok(req);
        break;
      }
      case 0x13: { // ADD_BUTTON
        if (payload_len < 1) {
          send_err(req, "invalid ADD_BUTTON");
          break;
        }
        st.button_id = payload[0];
        free(st.button_label);
        st.button_label = dup_bytes_as_cstr(payload + 1, payload_len - 1);
        if (!st.button_label) st.button_label = dup_bytes_as_cstr((const uint8_t*)"OK", 2);
#ifndef _WIN32
        ui_apply_async();
#else
        if (g_hwnd) PostMessageW(g_hwnd, WM_MINIGUI_APPLY, 0, 0);
#endif
        send_ok(req);
        break;
      }
      case 0x14: { // RUN
        ui_start(&st);
        send_ok(req);
        break;
      }
      case 0x15: { // QUIT
        ui_quit();
        send_ok(req);
        st.running = 0;
        break;
      }
      default:
        send_err(req, "unknown command");
        break;
    }

    free(buf);
    if (!st.running) break;
  }

  state_free(&st);
  return 0;
}
