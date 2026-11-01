// Native start window of SARCADE on Windows: see splash_window.h.
// Built with the Flutter runner settings (/W4 /WX, UNICODE, NOMINMAX):
// keep it free of warnings. Plain ASCII source (no /utf-8 flag): accented
// texts are written with escapes.
#include "splash_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <objbase.h>
#include <objidl.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>

#include "resource.h"

// GDI+ uses min and max, removed by NOMINMAX (set by the Flutter runner).
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#pragma warning(push, 0)
#include <gdiplus.h>
#pragma warning(pop)

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "dwmapi.lib")

namespace splash_window {
namespace {

constexpr wchar_t kClassName[] = L"SARCADE_SPLASH";
constexpr UINT_PTR kTimerId = 1;
// Size in logical pixels (96 dpi), scaled to the screen.
constexpr int kWidth = 360;
constexpr int kHeight = 240;
// Closes itself if the window of the application never shows.
constexpr ULONGLONG kMaxLifeMs = 90 * 1000;
constexpr ULONGLONG kBarPeriodMs = 1400;

std::atomic<HWND> g_window{nullptr};
std::atomic<bool> g_closed{false};
std::atomic<bool> g_started{false};
HINSTANCE g_instance = nullptr;
// Used by the thread of the start window only.
bool g_light = false;
float g_scale = 1.0f;
ULONGLONG g_shown_at = 0;
Gdiplus::Bitmap* g_logo = nullptr;
IStream* g_logo_stream = nullptr;

// Milliseconds since the process was created (the click on the icon).
long long MsSinceProcessStart() {
  FILETIME creation, exit_time, kernel, user;
  if (!GetProcessTimes(GetCurrentProcess(), &creation, &exit_time, &kernel,
                       &user)) {
    return -1;
  }
  FILETIME now;
  GetSystemTimeAsFileTime(&now);
  ULARGE_INTEGER start, end;
  start.LowPart = creation.dwLowDateTime;
  start.HighPart = creation.dwHighDateTime;
  end.LowPart = now.dwLowDateTime;
  end.HighPart = now.dwHighDateTime;
  if (end.QuadPart < start.QuadPart) {
    return 0;
  }
  return static_cast<long long>((end.QuadPart - start.QuadPart) / 10000);
}

// Appends a line (UTF-8) to the startup log of the application:
// %LOCALAPPDATA%\SARCADE\logs\demarrage.log (lib/src/platform).
void Log(const char* text) {
  wchar_t base[MAX_PATH];
  const DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    return;
  }
  std::wstring dir = std::wstring(base) + L"\\SARCADE";
  CreateDirectoryW(dir.c_str(), nullptr);
  dir += L"\\logs";
  CreateDirectoryW(dir.c_str(), nullptr);
  const std::wstring path = dir + L"\\demarrage.log";
  HANDLE file = CreateFileW(
      path.c_str(), FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  SYSTEMTIME t;
  GetLocalTime(&t);
  char line[512];
  const int len = snprintf(
      line, sizeof(line), "%04d-%02d-%02dT%02d:%02d:%02d.%03d %s\n",
      static_cast<int>(t.wYear), static_cast<int>(t.wMonth),
      static_cast<int>(t.wDay), static_cast<int>(t.wHour),
      static_cast<int>(t.wMinute), static_cast<int>(t.wSecond),
      static_cast<int>(t.wMilliseconds), text);
  if (len > 0) {
    const int size = std::min(len, static_cast<int>(sizeof(line)) - 1);
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(size), &written, nullptr);
  }
  CloseHandle(file);
}

// Same rule as the window of the application: dark unless Windows is in
// light mode for applications.
bool SystemUsesLightTheme() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  const LSTATUS result = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &value, &size);
  return result == ERROR_SUCCESS && value != 0;
}

const wchar_t* StartingText() {
  return PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_FRENCH
             ? L"Démarrage…"
             : L"Starting…";
}

// Logo of the theme, from the resources of the exe (Runner.rc).
void LoadLogo() {
  const int id = g_light ? kLogoLightId : kLogoDarkId;
  HRSRC resource = FindResourceW(g_instance, MAKEINTRESOURCEW(id), RT_RCDATA);
  if (resource == nullptr) {
    return;
  }
  HGLOBAL data = LoadResource(g_instance, resource);
  const DWORD size = SizeofResource(g_instance, resource);
  const void* bytes = data == nullptr ? nullptr : LockResource(data);
  if (bytes == nullptr || size == 0) {
    return;
  }
  HGLOBAL copy = GlobalAlloc(GMEM_MOVEABLE, size);
  if (copy == nullptr) {
    return;
  }
  void* target = GlobalLock(copy);
  if (target == nullptr) {
    GlobalFree(copy);
    return;
  }
  memcpy(target, bytes, size);
  GlobalUnlock(copy);
  if (FAILED(CreateStreamOnHGlobal(copy, TRUE, &g_logo_stream))) {
    GlobalFree(copy);
    g_logo_stream = nullptr;
    return;
  }
  g_logo = Gdiplus::Bitmap::FromStream(g_logo_stream);
  if (g_logo != nullptr && g_logo->GetLastStatus() != Gdiplus::Ok) {
    delete g_logo;
    g_logo = nullptr;
  }
}

Gdiplus::Color Rgb(DWORD rgb) {
  return Gdiplus::Color(255, static_cast<BYTE>((rgb >> 16) & 0xFF),
                        static_cast<BYTE>((rgb >> 8) & 0xFF),
                        static_cast<BYTE>(rgb & 0xFF));
}

// Colours of the SARCADE themes (lib/src/ui/theme.dart).
void Paint(HWND hwnd) {
  PAINTSTRUCT ps;
  HDC dc = BeginPaint(hwnd, &ps);
  RECT rc;
  GetClientRect(hwnd, &rc);
  const int w = rc.right - rc.left;
  const int h = rc.bottom - rc.top;
  HDC mem = CreateCompatibleDC(dc);
  HBITMAP bitmap = CreateCompatibleBitmap(dc, w, h);
  HGDIOBJ previous = SelectObject(mem, bitmap);
  {
    Gdiplus::Graphics g(mem);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    const float s = g_scale;
    const float fw = static_cast<float>(w);
    const float fh = static_cast<float>(h);
    g.Clear(Rgb(g_light ? 0xFFFFFF : 0x070B10));
    Gdiplus::Pen border(Rgb(g_light ? 0xDDE3EA : 0x1E2C38), s);
    g.DrawRectangle(&border, s / 2.0f, s / 2.0f, fw - s, fh - s);
    // Logo, 200 px wide.
    const float logo_w = 200.0f * s;
    if (g_logo != nullptr && g_logo->GetWidth() > 0) {
      const float logo_h = logo_w * static_cast<float>(g_logo->GetHeight()) /
                           static_cast<float>(g_logo->GetWidth());
      g.DrawImage(g_logo, Gdiplus::RectF((fw - logo_w) / 2.0f, 36.0f * s,
                                         logo_w, logo_h));
    }
    // « Démarrage… »
    Gdiplus::FontFamily family(L"Segoe UI");
    Gdiplus::Font font(&family, 15.0f * s, Gdiplus::FontStyleRegular,
                       Gdiplus::UnitPixel);
    Gdiplus::SolidBrush ink(Rgb(g_light ? 0x444746 : 0xB9C6D2));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    g.DrawString(StartingText(), -1, &font,
                 Gdiplus::RectF(0.0f, 152.0f * s, fw, 28.0f * s), &format,
                 &ink);
    // Animated bar: a segment going across the track.
    const float bar_w = 200.0f * s;
    const float bar_h = 4.0f * s;
    const float bar_x = (fw - bar_w) / 2.0f;
    const float bar_y = 196.0f * s;
    Gdiplus::SolidBrush track(Rgb(g_light ? 0xE9EEF6 : 0x16212B));
    g.FillRectangle(&track, bar_x, bar_y, bar_w, bar_h);
    const float segment = bar_w / 3.0f;
    const float phase =
        static_cast<float>((GetTickCount64() - g_shown_at) % kBarPeriodMs) /
        static_cast<float>(kBarPeriodMs);
    const float x0 =
        std::max(bar_x - segment + phase * (bar_w + segment), bar_x);
    const float x1 =
        std::min(bar_x - segment + phase * (bar_w + segment) + segment,
                 bar_x + bar_w);
    if (x1 > x0) {
      Gdiplus::SolidBrush accent(Rgb(g_light ? 0x0B57D0 : 0x3DD6F5));
      g.FillRectangle(&accent, x0, bar_y, x1 - x0, bar_h);
    }
  }
  BitBlt(dc, 0, 0, w, h, mem, 0, 0, SRCCOPY);
  SelectObject(mem, previous);
  DeleteObject(bitmap);
  DeleteDC(mem);
  EndPaint(hwnd, &ps);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                         LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      Paint(hwnd);
      return 0;
    case WM_TIMER:
      if (GetTickCount64() - g_shown_at > kMaxLifeMs) {
        DestroyWindow(hwnd);
      } else {
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_DESTROY:
      KillTimer(hwnd, kTimerId);
      g_window.store(nullptr);
      PostQuitMessage(0);
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

DWORD WINAPI Run(LPVOID) {
  Gdiplus::GdiplusStartupInput input;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok) {
    return 0;
  }
  g_light = SystemUsesLightTheme();
  LoadLogo();
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = g_instance;
  wc.hCursor = LoadCursorW(nullptr, IDC_APPSTARTING);
  wc.hIcon = LoadIconW(g_instance, MAKEINTRESOURCEW(IDI_APP_ICON));
  wc.lpszClassName = kClassName;
  RegisterClassExW(&wc);
  HWND hwnd = CreateWindowExW(0, kClassName, L"SARCADE", WS_POPUP, 0, 0,
                              kWidth, kHeight, nullptr, nullptr, g_instance,
                              nullptr);
  if (hwnd != nullptr) {
    // Same DPI helper as the window of the application (win32_window.cpp).
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
    const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
    const int scale_dpi = dpi == 0 ? 96 : static_cast<int>(dpi);
    g_scale = static_cast<float>(scale_dpi) / 96.0f;
    const int w = MulDiv(kWidth, scale_dpi, 96);
    const int h = MulDiv(kHeight, scale_dpi, 96);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);
    const RECT& work = info.rcWork;
    SetWindowPos(hwnd, nullptr,
                 work.left + (work.right - work.left - w) / 2,
                 work.top + (work.bottom - work.top - h) / 2, w, h,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    // Rounded corners on Windows 11 (DWMWA_WINDOW_CORNER_PREFERENCE,
    // DWMWCP_ROUND); ignored by Windows 10.
    const DWORD round = 2;
    DwmSetWindowAttribute(hwnd, 33, &round, sizeof(round));
    g_shown_at = GetTickCount64();
    SetTimer(hwnd, kTimerId, 30, nullptr);
    g_window.store(hwnd);
    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);
    const long long ms = MsSinceProcessStart();
    char line[200];
    snprintf(line, sizeof(line),
             "natif : fen\xC3\xAA" "tre de d\xC3\xA9" "marrage affich\xC3\xA9"
             "e en %lld ms (splash_ms=%lld)",
             ms, ms);
    Log(line);
    // Flutter may have drawn its first image already.
    if (g_closed.load()) {
      DestroyWindow(hwnd);
    }
    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }
  delete g_logo;
  g_logo = nullptr;
  if (g_logo_stream != nullptr) {
    g_logo_stream->Release();
    g_logo_stream = nullptr;
  }
  Gdiplus::GdiplusShutdown(token);
  return 0;
}

}  // namespace

void Start(HINSTANCE instance) {
  if (g_started.exchange(true)) {
    return;
  }
  g_instance = instance;
  HANDLE thread = CreateThread(nullptr, 0, Run, nullptr, 0, nullptr);
  if (thread != nullptr) {
    CloseHandle(thread);
  }
}

void Close() {
  if (g_closed.exchange(true)) {
    return;
  }
  const long long ms = MsSinceProcessStart();
  char line[200];
  snprintf(line, sizeof(line),
           "natif : premi\xC3\xA8" "re image de Flutter en %lld ms, fen\xC3\xAA"
           "tre de d\xC3\xA9" "marrage ferm\xC3\xA9" "e (first_frame_ms=%lld)",
           ms, ms);
  Log(line);
  HWND hwnd = g_window.load();
  if (hwnd != nullptr) {
    PostMessageW(hwnd, WM_CLOSE, 0, 0);
  }
}

}  // namespace splash_window
