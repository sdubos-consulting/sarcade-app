// One SARCADE per Windows session: see single_instance.h.
// Built with the Flutter runner settings (/W4 /WX, UNICODE): keep it free of
// warnings. Plain ASCII source: accented texts are written with escapes.
#include "single_instance.h"

#include <cstdio>
#include <cwchar>

#include "splash_window.h"

namespace single_instance {
namespace {

// "Local\" : one lock per Windows session, as the Dart lock (per user).
constexpr wchar_t kMutexName[] = L"Local\\SARCADE-sarcade_app-single-instance";
// Window classes of the runner (win32_window.cpp) and of the start window
// (splash_window.cpp); title set by tool/patch_windows.py.
constexpr wchar_t kAppClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kSplashClass[] = L"SARCADE_SPLASH";
constexpr wchar_t kTitle[] = L"SARCADE";

// Kept for the life of the process; Windows releases it at the end.
HANDLE g_mutex = nullptr;

struct Found {
  HWND app;
  HWND splash;
};

BOOL CALLBACK FindWindows(HWND hwnd, LPARAM lparam) {
  Found* found = reinterpret_cast<Found*>(lparam);
  wchar_t name[64] = {0};
  if (GetClassNameW(hwnd, name, 64) == 0) {
    return TRUE;
  }
  if (wcscmp(name, kAppClass) == 0 && found->app == nullptr) {
    wchar_t title[64] = {0};
    GetWindowTextW(hwnd, title, 64);
    if (wcscmp(title, kTitle) == 0) {
      found->app = hwnd;
    }
  } else if (wcscmp(name, kSplashClass) == 0 && found->splash == nullptr) {
    found->splash = hwnd;
  }
  return TRUE;
}

}  // namespace

bool Acquire() {
  HANDLE mutex = CreateMutexW(nullptr, FALSE, kMutexName);
  const DWORD error = GetLastError();
  if (mutex == nullptr) {
    // Held by a SARCADE started as administrator: refused as well. Any other
    // failure lets this one start (the Dart lock still applies).
    if (error == ERROR_ACCESS_DENIED) {
      return false;
    }
    char line[160];
    snprintf(line, sizeof(line),
             "natif : verrou d'instance unique indisponible (erreur %lu, "
             "pid %lu), d\xC3\xA9" "marrage quand m\xC3\xAA" "me",
             static_cast<unsigned long>(error),
             static_cast<unsigned long>(GetCurrentProcessId()));
    splash_window::Log(line);
    return true;
  }
  if (error == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    return false;
  }
  g_mutex = mutex;
  // Which process won, when two start in the same second (lot 25, owner's
  // crash of 2 Nov 2026): one line per start, before the engine loads.
  char line[120];
  snprintf(line, sizeof(line),
           "natif : verrou d'instance unique pris (pid %lu, "
           "single_instance=acquired)",
           static_cast<unsigned long>(GetCurrentProcessId()));
  splash_window::Log(line);
  return true;
}

void ShowExisting() {
  Found found{nullptr, nullptr};
  EnumWindows(FindWindows, reinterpret_cast<LPARAM>(&found));
  // The window of the application stays hidden until the first image of
  // Flutter: until then, the start window is the one shown.
  HWND target = nullptr;
  if (found.app != nullptr && IsWindowVisible(found.app)) {
    target = found.app;
  } else if (found.splash != nullptr && IsWindowVisible(found.splash)) {
    target = found.splash;
  }
  if (target != nullptr) {
    if (IsIconic(target)) {
      ShowWindow(target, SW_RESTORE);
    }
    SetForegroundWindow(target);
  }
  char line[200];
  snprintf(line, sizeof(line), "%s (pid %lu, second_instance=refused)",
           target != nullptr
               ? "natif : deuxi\xC3\xA8" "me instance refus\xC3\xA9" "e, "
                 "fen\xC3\xAA" "tre SARCADE existante remise au premier plan"
               : "natif : deuxi\xC3\xA8" "me instance refus\xC3\xA9" "e, "
                 "aucune fen\xC3\xAA" "tre SARCADE visible",
           static_cast<unsigned long>(GetCurrentProcessId()));
  splash_window::Log(line);
}

}  // namespace single_instance
