// Channel "sarcade/runner" between the Dart code and the native runner
// (card "Windows : pastille de liaison grise alors que le Diagnostic dit
// Tout fonctionne", lot 19, point 2). Copied into windows/runner/ by
// tool/patch_windows.py.
//
// "quit" (argument: exit code, int): closes the start window, waits for its
// thread, then closes the window of the application; wWinMain then returns
// the code. Used by the Dart code instead of exit(): a second instance
// refused by the Dart lock, the end of the start test of the CI.
#ifndef RUNNER_RUNNER_CHANNEL_H_
#define RUNNER_RUNNER_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

namespace runner_channel {

// Listens on "sarcade/runner"; [window] is the window of the application.
void Register(flutter::BinaryMessenger* messenger, HWND window);

// Stops listening (the engine is going away).
void Release();

// Exit code asked by the Dart code (0 when nothing was asked).
int ExitCode();

}  // namespace runner_channel

#endif  // RUNNER_RUNNER_CHANNEL_H_
