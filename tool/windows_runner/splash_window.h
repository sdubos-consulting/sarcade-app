// Native start window of SARCADE on Windows (card « Windows : logo SARCADE
// affiché dès le clic sur l'icône », 1 Nov 2026). Copied into
// windows/runner/ by tool/patch_windows.py: the Windows runner is generated
// by `flutter create` in the CI, never kept in the repository.
//
// A small borderless window, centred, with the SARCADE logo, « Démarrage… »
// and an animated bar. Drawn by its own thread from the first instant of the
// process, before the Flutter engine loads; closed when the window of the
// application shows its first image.
#ifndef RUNNER_SPLASH_WINDOW_H_
#define RUNNER_SPLASH_WINDOW_H_

#include <windows.h>

namespace splash_window {

// Resource ids of the two logos (Runner.rc, RCDATA).
constexpr int kLogoDarkId = 201;
constexpr int kLogoLightId = 202;

// Shows the start window (own thread, returns at once).
void Start(HINSTANCE instance);

// Closes it; called at the first image of Flutter. Safe to call twice.
void Close();

}  // namespace splash_window

#endif  // RUNNER_SPLASH_WINDOW_H_
