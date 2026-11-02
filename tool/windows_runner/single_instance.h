// One SARCADE per Windows session (card "Windows : pastille de liaison grise
// alors que le Diagnostic dit Tout fonctionne", lot 19, points 1 and 6).
// Copied into windows/runner/ by tool/patch_windows.py.
//
// The second process is refused by the native runner, first thing in
// wWinMain: before the start window and before the Flutter engine. It brings
// the SARCADE window already open to the front and returns from wWinMain,
// without message and without ending the process abruptly (a second process
// ended by exit(0) while its start window and engine were running crashed
// with 0xc0000409 in ucrtbase.dll). The lock of the Dart code
// (acquireSingleInstance) stays as a safety net.
#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

namespace single_instance {

// Takes the named system lock of SARCADE. False when another SARCADE
// process of this session holds it (also when that one runs as
// administrator and the lock cannot be opened).
bool Acquire();

// Brings the window of the SARCADE already running to the front: its
// application window when shown, else its start window.
void ShowExisting();

}  // namespace single_instance

#endif  // RUNNER_SINGLE_INSTANCE_H_
