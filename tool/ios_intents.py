"""Siri module of SARCADE: Intents extension « SarcadeIntents » added to the
committed Xcode project (card « Siri : messages SARCADE par un module Siri
séparé et lecture des notifications », validated on 9 Nov 2026, choice 1).

No Mac on the team: the target is written into project.pbxproj by this
script (called by tool/patch_ios.py), with fixed object identifiers so that
running it again changes nothing. The sources are in ios/SarcadeIntents/.

The extension and the application share their data through the App Group
group.org.sarcade.sarcadeApp (UserDefaults of the group): the car data
written by the application (conversations), the actions written by Siri
(« reply », « read »), taken by the application like the ones of CarPlay.
"""
from pathlib import Path

NAME = "SarcadeIntents"
BUNDLE_ID = "org.sarcade.sarcadeApp.SarcadeIntents"
APP_GROUP = "group.org.sarcade.sarcadeApp"
INTENTS = ["INSendMessageIntent", "INSetMessageAttributeIntent"]
DIR = Path("ios") / NAME

# Fixed identifiers (24 hexadecimal digits, unique in the project).
ID = {k: "5A4C1A00000000000000" + v for k, v in {
    "target": "00A1", "product": "00A2", "handler": "00A3", "plist": "00A4", "entitlements": "00A5",
    "xcconfig": "00A6", "group": "00A7", "sources": "00A8", "frameworks": "00A9", "resources": "00AA",
    "handler_build": "00AB", "embed_build": "00AC", "embed_phase": "00AD", "proxy": "00AE",
    "dependency": "00AF", "debug": "00B1", "release": "00B2", "profile": "00B3", "configs": "00B4",
}.items()}

RUNNER_TARGET = "97C146ED1CF9000F007C117D"
PROJECT = "97C146E61CF9000F007C117D"
MAIN_GROUP_LINE = "\t\t\t\t97C146EF1CF9000F007C117D /* Products */,\n"
PRODUCTS_LINE = "\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,\n"
THIN_BINARY_LINE = "\t\t\t\t3B06AD1E1E4923F5004D2608 /* Thin Binary */,\n"
TARGETS_LINE = "\t\t\t\t97C146ED1CF9000F007C117D /* Runner */,\n"
TARGET_ATTRIBUTES_LINE = "\t\t\t\t\t97C146ED1CF9000F007C117D = {\n"

INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>SARCADE</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>IntentsRestrictedWhileLocked</key>
			<array/>
			<key>IntentsSupported</key>
			<array>
%INTENTS%
			</array>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.intents-service</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).IntentHandler</string>
	</dict>
</dict>
</plist>
""".replace("%INTENTS%", "\n".join(f"\t\t\t\t<string>{i}</string>" for i in INTENTS))

ENTITLEMENTS = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key><array><string>{APP_GROUP}</string></array>
</dict></plist>
"""

# Build number and version of the application (CFBundleVersion of the
# extension must be the one of the application); not the Pods settings.
XCCONFIG = '#include? "../Flutter/Generated.xcconfig"\n'


def _settings(debug: bool) -> str:
    lines = [
        "APPLICATION_EXTENSION_API_ONLY = YES;",
        f"CODE_SIGN_ENTITLEMENTS = {NAME}/{NAME}.entitlements;",
        "CODE_SIGN_STYLE = Automatic;",
        "CURRENT_PROJECT_VERSION = \"$(FLUTTER_BUILD_NUMBER)\";",
        "DEVELOPMENT_TEAM = 34785R7XLK;",
        "GENERATE_INFOPLIST_FILE = NO;",
        f"INFOPLIST_FILE = {NAME}/Info.plist;",
        "IPHONEOS_DEPLOYMENT_TARGET = 15.0;",
        "LD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t\t\"@executable_path/Frameworks\",\n"
        "\t\t\t\t\t\"@executable_path/../../Frameworks\",\n\t\t\t\t);",
        "MARKETING_VERSION = \"$(FLUTTER_BUILD_NAME)\";",
        f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "SKIP_INSTALL = YES;",
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "SWIFT_VERSION = 5.0;",
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
    ]
    if debug:
        lines += ["SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;", "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";"]
    return "".join(f"\t\t\t\t{l}\n" for l in sorted(lines))


def _config(key: str, name: str) -> str:
    return (f"\t\t{ID[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbaseConfigurationReference = {ID['xcconfig']} /* {NAME}.xcconfig */;\n"
            f"\t\t\tbuildSettings = {{\n{_settings(name == 'Debug')}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")


SECTIONS = {
    "PBXBuildFile": (
        f"\t\t{ID['handler_build']} /* IntentHandler.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {ID['handler']} /* IntentHandler.swift */; }};\n"
        f"\t\t{ID['embed_build']} /* {NAME}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {ID['product']} /* {NAME}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"),
    "PBXContainerItemProxy": (
        f"\t\t{ID['proxy']} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;\n\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {ID['target']};\n\t\t\tremoteInfo = {NAME};\n\t\t}};\n"),
    "PBXCopyFilesBuildPhase": (
        f"\t\t{ID['embed_phase']} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n"
        f"\t\t\tfiles = (\n\t\t\t\t{ID['embed_build']} /* {NAME}.appex in Embed Foundation Extensions */,\n\t\t\t);\n"
        "\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"),
    "PBXFileReference": (
        f"\t\t{ID['product']} /* {NAME}.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = {NAME}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
        f"\t\t{ID['handler']} /* IntentHandler.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IntentHandler.swift; sourceTree = \"<group>\"; }};\n"
        f"\t\t{ID['plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};\n"
        f"\t\t{ID['entitlements']} /* {NAME}.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {NAME}.entitlements; sourceTree = \"<group>\"; }};\n"
        f"\t\t{ID['xcconfig']} /* {NAME}.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {NAME}.xcconfig; sourceTree = \"<group>\"; }};\n"),
    "PBXFrameworksBuildPhase": (
        f"\t\t{ID['frameworks']} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"),
    "PBXGroup": (
        f"\t\t{ID['group']} /* {NAME} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        f"\t\t\t\t{ID['handler']} /* IntentHandler.swift */,\n\t\t\t\t{ID['plist']} /* Info.plist */,\n"
        f"\t\t\t\t{ID['entitlements']} /* {NAME}.entitlements */,\n\t\t\t\t{ID['xcconfig']} /* {NAME}.xcconfig */,\n"
        f"\t\t\t);\n\t\t\tpath = {NAME};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"),
    "PBXNativeTarget": (
        f"\t\t{ID['target']} /* {NAME} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {ID['configs']} /* Build configuration list for PBXNativeTarget \"{NAME}\" */;\n"
        f"\t\t\tbuildPhases = (\n\t\t\t\t{ID['sources']} /* Sources */,\n\t\t\t\t{ID['frameworks']} /* Frameworks */,\n"
        f"\t\t\t\t{ID['resources']} /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n"
        f"\t\t\tname = {NAME};\n\t\t\tproductName = {NAME};\n\t\t\tproductReference = {ID['product']} /* {NAME}.appex */;\n"
        "\t\t\tproductType = \"com.apple.product-type.app-extension\";\n\t\t};\n"),
    "PBXResourcesBuildPhase": (
        f"\t\t{ID['resources']} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"),
    "PBXSourcesBuildPhase": (
        f"\t\t{ID['sources']} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n\t\t\t\t{ID['handler_build']} /* IntentHandler.swift in Sources */,\n\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"),
    "PBXTargetDependency": (
        f"\t\t{ID['dependency']} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {ID['target']} /* {NAME} */;\n\t\t\ttargetProxy = {ID['proxy']} /* PBXContainerItemProxy */;\n\t\t}};\n"),
    "XCBuildConfiguration": _config("debug", "Debug") + _config("release", "Release") + _config("profile", "Profile"),
    "XCConfigurationList": (
        f"\t\t{ID['configs']} /* Build configuration list for PBXNativeTarget \"{NAME}\" */ = {{\n\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n\t\t\t\t{ID['debug']} /* Debug */,\n\t\t\t\t{ID['release']} /* Release */,\n"
        f"\t\t\t\t{ID['profile']} /* Profile */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n"
        "\t\t\tdefaultConfigurationName = Release;\n\t\t};\n"),
}


def _insert_before(text: str, anchor: str, new: str) -> str:
    if text.count(anchor) != 1:
        raise ValueError(f"anchor not found once in project.pbxproj: {anchor.strip()}")
    return text.replace(anchor, new + anchor)


def _insert_after(text: str, anchor: str, new: str) -> str:
    if text.count(anchor) != 1:
        raise ValueError(f"anchor not found once in project.pbxproj: {anchor.strip()}")
    return text.replace(anchor, anchor + new)


def patch_project(proj: str) -> str:
    """The project with the extension target; unchanged if already there."""
    if ID["target"] in proj:
        return proj
    for section, block in SECTIONS.items():
        end = f"/* End {section} section */\n"
        if end not in proj:
            # Section absent from the template: created empty first.
            proj = proj.replace("/* Begin PBXFileReference section */",
                                f"/* Begin {section} section */\n{end}\n/* Begin PBXFileReference section */", 1)
        proj = _insert_before(proj, end, block)
    # Group of the extension and its product.
    proj = _insert_after(proj, MAIN_GROUP_LINE, f"\t\t\t\t{ID['group']} /* {NAME} */,\n")
    proj = _insert_after(proj, PRODUCTS_LINE, f"\t\t\t\t{ID['product']} /* {NAME}.appex */,\n")
    # Runner embeds the extension before « Thin Binary » (else a build cycle).
    proj = _insert_before(proj, THIN_BINARY_LINE, f"\t\t\t\t{ID['embed_phase']} /* Embed Foundation Extensions */,\n")
    runner = proj.index(f"{RUNNER_TARGET} /* Runner */ = {{\n\t\t\tisa = PBXNativeTarget;")
    deps = proj.index("\t\t\tdependencies = (\n", runner) + len("\t\t\tdependencies = (\n")
    proj = proj[:deps] + f"\t\t\t\t{ID['dependency']} /* PBXTargetDependency */,\n" + proj[deps:]
    proj = _insert_after(proj, TARGETS_LINE, f"\t\t\t\t{ID['target']} /* {NAME} */,\n")
    proj = _insert_before(proj, TARGET_ATTRIBUTES_LINE,
                          f"\t\t\t\t\t{ID['target']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t}};\n")
    return proj


def write_files() -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    (DIR / "Info.plist").write_text(INFO_PLIST, newline="\n")
    (DIR / f"{NAME}.entitlements").write_text(ENTITLEMENTS, newline="\n")
    (DIR / f"{NAME}.xcconfig").write_text(XCCONFIG, newline="\n")
