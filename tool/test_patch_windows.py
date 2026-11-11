"""Tests of tool/patch_windows.py and of the native sources it copies
(card « Windows : SARCADE a cessé de fonctionner », lot 25).

    python3 -m unittest discover -s tool -p "test_*.py"
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import patch_windows  # noqa: E402

RUNNER_SOURCES = Path(__file__).resolve().parent / "windows_runner"

# Shape of windows/CMakeLists.txt written by `flutter create`.
CMAKE = """\
cmake_minimum_required(VERSION 3.14)
project(sarcade_app LANGUAGES CXX)
set(BINARY_NAME "sarcade_app")
add_subdirectory(${FLUTTER_MANAGED_DIR})
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
"""


class DelayLoadTest(unittest.TestCase):
    def test_rules_after_the_plugins(self):
        text = patch_windows.add_delay_load(CMAKE)
        self.assertIsNotNone(text)
        plugins = text.index("include(flutter/generated_plugins.cmake)")
        rules = text.index('"/DELAYLOAD:flutter_windows.dll"')
        self.assertLess(plugins, rules)
        self.assertLess(rules, text.index("# === Installation ==="))
        self.assertIn("SHARED_LIBRARY", text)
        self.assertIn("target_link_libraries(${BINARY_NAME} PRIVATE delayimp)", text)

    def test_idempotent(self):
        once = patch_windows.add_delay_load(CMAKE)
        self.assertEqual(patch_windows.add_delay_load(once), once)
        self.assertEqual(once.count("delayimp"), 1)

    def test_template_changed(self):
        self.assertIsNone(patch_windows.add_delay_load("project(x)\n"))


class NativeSourcesTest(unittest.TestCase):
    def test_plain_ascii(self):
        # Built without /utf-8: accented texts are written with escapes.
        for path in sorted(RUNNER_SOURCES.iterdir()):
            if path.suffix in (".cpp", ".h"):
                with self.subTest(path.name):
                    path.read_bytes().decode("ascii")

    def test_start_window_does_not_load_the_engine(self):
        # flutter_windows.dll is delay-loaded: the start window and the
        # single instance lock must not call it (they run before it loads).
        for name in ("splash_window.cpp", "splash_window.h", "single_instance.cpp", "single_instance.h"):
            with self.subTest(name):
                text = (RUNNER_SOURCES / name).read_text(encoding="ascii")
                self.assertNotIn("flutter_windows.h", text)
                self.assertNotIn("FlutterDesktop", text)

    def test_refusal_written_to_the_log(self):
        # The smoke test looks for these marks in demarrage.log.
        text = (RUNNER_SOURCES / "single_instance.cpp").read_text(encoding="ascii")
        self.assertIn("second_instance=refused", text)
        self.assertIn("single_instance=acquired", text)


if __name__ == "__main__":
    unittest.main()
