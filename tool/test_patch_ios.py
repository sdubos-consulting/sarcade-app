"""Tests of tool/patch_ios.py and of the committed iOS project: CarPlay in the
« Communication » category and Siri messages (Apple's agreement of 9 Nov
2026). Without a Mac, these checks are the only ones before Xcode Cloud.

    python -m unittest discover -s tool -p "test_*.py"
"""
import os
import plistlib
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))

import ios_intents  # noqa: E402
import patch_ios  # noqa: E402

SWIFT = ROOT / "third_party" / "sarcade_car" / "ios" / "Classes"


class CarPlayCommunication(unittest.TestCase):
    def setUp(self):
        self.saved = os.environ.pop("SARCADE_CARPLAY", None)

    def tearDown(self):
        os.environ.pop("SARCADE_CARPLAY", None)
        if self.saved is not None:
            os.environ["SARCADE_CARPLAY"] = self.saved

    def test_communication_entitlement_on_by_default(self):
        self.assertEqual(patch_ios.CARPLAY_ENTITLEMENT, "com.apple.developer.carplay-communication")
        self.assertTrue(patch_ios.carplay_on())
        os.environ["SARCADE_CARPLAY"] = "0"
        self.assertFalse(patch_ios.carplay_on())

    def test_scene_declared(self):
        info = {"UIApplicationSceneManifest": {"UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": []}}}
        self.assertTrue(patch_ios.patch_carplay(info))
        scenes = info["UIApplicationSceneManifest"]["UISceneConfigurations"]
        self.assertEqual(scenes[patch_ios.CARPLAY_ROLE][0]["UISceneDelegateClassName"], "SarcadeCarPlaySceneDelegate")

    def test_committed_project_is_patched(self):
        """The script was run and its output committed (Xcode Cloud does not run it)."""
        with (ROOT / "ios" / "Runner" / "Info.plist").open("rb") as f:
            info = plistlib.load(f)
        self.assertNotIn("INIntentsSupported", info, "Siri goes through the Siri module (9 Nov 2026)")
        self.assertEqual(info["INAlternativeAppNames"][0]["INAlternativeAppName"], "Sarcade")
        self.assertIn("NSSiriUsageDescription", info)
        self.assertIn(patch_ios.CARPLAY_ROLE, info["UIApplicationSceneManifest"]["UISceneConfigurations"])
        entitlements = (ROOT / "ios" / "Runner" / "Runner.entitlements").read_bytes()
        self.assertNotIn(b"\r\n", entitlements)
        with (ROOT / "ios" / "Runner" / "Runner.entitlements").open("rb") as f:
            ent = plistlib.load(f)
        self.assertTrue(ent["com.apple.developer.carplay-communication"])
        self.assertTrue(ent["com.apple.developer.siri"])
        self.assertNotIn("com.apple.developer.carplay-public-safety", ent)
        self.assertEqual(ent["com.apple.security.application-groups"], [ios_intents.APP_GROUP])

    def test_siri_module(self):
        """Siri module « SarcadeIntents » (9 Nov 2026): in the project, embedded
        in the application before « Thin Binary », same App Group and keys."""
        app = (ROOT / "ios" / "Runner" / "AppDelegate.swift").read_text(encoding="utf-8")
        self.assertNotIn("handlerFor", app, "no more Siri handled in the application")
        proj = (ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        self.assertEqual(ios_intents.patch_project(proj), proj, "already patched, nothing changes")
        self.assertEqual(proj.count("{"), proj.count("}"))
        self.assertEqual(proj.count("("), proj.count(")"))
        defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", proj, re.M))
        self.assertEqual(set(re.findall(r"\b([0-9A-F]{24})\b", proj)) - defined, set(), "every reference defined")
        self.assertIn(f"PRODUCT_BUNDLE_IDENTIFIER = {ios_intents.BUNDLE_ID};", proj)
        runner = proj[proj.index("97C146ED1CF9000F007C117D /* Runner */ = {"):]
        phases = runner[:runner.index(");")]
        self.assertLess(phases.index("Embed Foundation Extensions"), phases.index("Thin Binary"))
        handler = (ROOT / "ios" / ios_intents.NAME / "IntentHandler.swift").read_text(encoding="utf-8")
        plugin = (SWIFT / "SarcadeCarPlugin.swift").read_text(encoding="utf-8")
        for key in ("sarcade_car_screen.snapshot", "sarcade_car_screen.actions", "org.sarcade.car.actions",
                    ios_intents.APP_GROUP):
            self.assertIn(key, handler)
            self.assertIn(key, plugin)
        for intent in ios_intents.INTENTS:
            self.assertIn(f"{intent}Handling", handler)
        self.assertIn('"type": "reply"', handler, "same action as an answer dictated in Android Auto")
        with (ROOT / "ios" / ios_intents.NAME / "Info.plist").open("rb") as f:
            ext = plistlib.load(f)
        self.assertEqual(ext["NSExtension"]["NSExtensionPointIdentifier"], "com.apple.intents-service")
        self.assertEqual(ext["CFBundleVersion"], "$(FLUTTER_BUILD_NUMBER)", "same build number as the application")

    def test_only_templates_of_the_communication_category(self):
        scene = (SWIFT / "SarcadeCarPlaySceneDelegate.swift").read_text(encoding="utf-8")
        for t in ("CPInformationTemplate", "CPPointOfInterestTemplate", "CPMapTemplate", "CPSearchTemplate"):
            self.assertNotIn(t, scene)


if __name__ == "__main__":
    unittest.main()
