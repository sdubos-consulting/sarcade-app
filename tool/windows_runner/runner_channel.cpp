// Channel "sarcade/runner": see runner_channel.h.
// Built with the Flutter runner settings (/W4 /WX, UNICODE): keep it free of
// warnings. Plain ASCII source.
#include "runner_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>
#include <variant>

#include "splash_window.h"

namespace runner_channel {
namespace {

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
HWND g_window = nullptr;
int g_exit_code = 0;

void HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "quit") {
    result->NotImplemented();
    return;
  }
  int code = 0;
  const flutter::EncodableValue* arguments = call.arguments();
  if (arguments != nullptr) {
    if (const int32_t* value = std::get_if<int32_t>(arguments)) {
      code = static_cast<int>(*value);
    }
  }
  g_exit_code = code;
  char line[160];
  snprintf(line, sizeof(line),
           "natif : arr\xC3\xAA" "t demand\xC3\xA9 par SARCADE (code %d), "
           "fen\xC3\xAA" "tre de d\xC3\xA9" "marrage ferm\xC3\xA9" "e d'abord",
           code);
  splash_window::Log(line);
  // The start window first: no thread of it left when the process ends.
  splash_window::Stop();
  result->Success();
  if (g_window != nullptr) {
    PostMessageW(g_window, WM_CLOSE, 0, 0);
  } else {
    PostQuitMessage(code);
  }
}

}  // namespace

void Register(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "sarcade/runner",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(HandleCall);
}

void Release() {
  if (g_channel) {
    g_channel->SetMethodCallHandler(nullptr);
  }
  g_channel.reset();
  g_window = nullptr;
}

int ExitCode() { return g_exit_code; }

}  // namespace runner_channel
