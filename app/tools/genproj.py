#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
#
# Writes app/VoyagerCalc.xcodeproj (project.pbxproj + shared schemes) from the source tree,
# so the project can be made on any machine (no Xcode or XcodeGen needed).
# Run from anywhere:  python3 app/tools/genproj.py
import hashlib, os, glob

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(APP)
PROJ = os.path.join(APP, "VoyagerCalc.xcodeproj")
BUNDLE_ID = "com.josegonzalezdivasson.VoyagerCalc"

def oid(*k):
    return hashlib.md5("/".join(k).encode()).hexdigest()[:24].upper()

def q(s):
    s = str(s)
    if s and all(c.isalnum() or c in "._/$" for c in s) and not s.startswith("$(") is False:
        pass
    if s and all(c.isalnum() or c in "._/" for c in s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

def ser(v, ind=1):
    t = "\t" * ind
    if isinstance(v, dict):
        out = "{\n"
        for k, x in v.items():
            out += f"{t}{q(k)} = {ser(x, ind + 1)};\n"
        return out + "\t" * (ind - 1) + "}"
    if isinstance(v, list):
        out = "(\n"
        for x in v:
            out += f"{t}{ser(x, ind + 1)},\n"
        return out + "\t" * (ind - 1) + ")"
    return q(v)

objects = {}
def add(i, d): objects[i] = d; return i

def rel(p, base): return os.path.relpath(p, base)

swift_core = sorted(glob.glob(os.path.join(APP, "Sources/Core/*.swift")))
swift_models = sorted(glob.glob(os.path.join(APP, "Sources/Models/*.swift")))
swift_app = sorted(glob.glob(os.path.join(APP, "Sources/App/*.swift")))
swift_views = sorted(glob.glob(os.path.join(APP, "Sources/Views/*.swift")))
c_src = sorted(glob.glob(os.path.join(ROOT, "core/src/*.c")))
c_hdr = sorted(glob.glob(os.path.join(ROOT, "core/src/*.h"))) + [os.path.join(ROOT, "core/include/voyager_core.h"), os.path.join(ROOT, "core/include/module.modulemap")]
tests = sorted(glob.glob(os.path.join(APP, "Tests/KitTests/*.swift")) + glob.glob(os.path.join(APP, "Tests/AppTests/*.swift")))
faces = sorted(glob.glob(os.path.join(APP, "Resources/Faces/*.png")))   # photo faces (art/tools/make_faces.py)
fonts = sorted(glob.glob(os.path.join(APP, "Resources/Fonts/*.ttf")))   # 0.6.7: the two HP 15C Simulator fonts (art/fonts), bundled
mac_assets = os.path.join(APP, "Resources/macOS/Assets.xcassets")   # app icon (art/icon/make_appiconsets.py)
ios_assets = os.path.join(APP, "Resources/iOS/Assets.xcassets")
plists = [os.path.join(APP, p) for p in ["Resources/macOS/Info.plist", "Resources/iOS/Info.plist", "Resources/macOS/VoyagerCalc.entitlements"]]

def ftype(p):
    e = os.path.splitext(p)[1]
    return {".swift": "sourcecode.swift", ".c": "sourcecode.c.c", ".h": "sourcecode.c.h", ".plist": "text.plist.xml",
            ".entitlements": "text.plist.entitlements", ".modulemap": "sourcecode.module-map", ".png": "image.png", ".ttf": "file", ".xcassets": "folder.assetcatalog"}.get(e, "text")

fileref = {}
def fref(p):
    if p in fileref: return fileref[p]
    i = add(oid("ref", rel(p, ROOT)), {"isa": "PBXFileReference", "lastKnownFileType": ftype(p),
             "name": os.path.basename(p), "path": rel(p, APP), "sourceTree": "SOURCE_ROOT"})
    fileref[p] = i; return i

def group(name, files, children_groups=()):
    i = oid("group", name)
    add(i, {"isa": "PBXGroup", "children": list(children_groups) + [fref(f) for f in files], "name": name, "sourceTree": "<group>"})
    return i

g_core = group("Core", swift_core)
g_models = group("Models", swift_models)
g_app = group("App", swift_app)
g_views = group("Views", swift_views)
g_c = group("C core (../core)", c_src + c_hdr)
g_tests = group("Tests", tests)
g_faces = group("Faces", faces)
g_fonts = group("Fonts", fonts)
g_res = group("Resources", plists + [mac_assets, ios_assets], [g_faces, g_fonts])

products = {}
def product(name, kind, ext):
    i = add(oid("product", name), {"isa": "PBXFileReference", "explicitFileType": kind, "includeInIndex": "0",
             "path": name + ext, "sourceTree": "BUILT_PRODUCTS_DIR"})
    products[name] = i; return i

p_mac = product("VoyagerCalc", "wrapper.application", ".app")
p_ios = add(oid("product", "VoyagerCalc-iOS"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": "0",
            "path": "VoyagerCalc.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
p_test = product("VoyagerCalcTests", "wrapper.cfbundle", ".xctest")
g_products = add(oid("group", "Products"), {"isa": "PBXGroup", "children": [p_mac, p_ios, p_test], "name": "Products", "sourceTree": "<group>"})
g_main = add(oid("group", "main"), {"isa": "PBXGroup", "children": [g_app, g_views, g_core, g_models, g_c, g_tests, g_res, g_products], "sourceTree": "<group>"})

common = {
    "SWIFT_VERSION": "5.0",
    "SWIFT_INCLUDE_PATHS": "$(SRCROOT)/../core/include",
    "HEADER_SEARCH_PATHS": "$(SRCROOT)/../core/include",
    "GCC_C_LANGUAGE_STANDARD": "c11",
    "CLANG_ENABLE_MODULES": "YES",
    "MARKETING_VERSION": "0.7.1",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}

def configs(tname, extra):
    ids = []
    for cfg in ("Debug", "Release"):
        s = dict(common); s.update(extra)
        s["GCC_OPTIMIZATION_LEVEL"] = "2"          # the C core is slow without optimisation
        s["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if cfg == "Debug" else "-O"
        if cfg == "Debug":
            s["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
            s["ONLY_ACTIVE_ARCH"] = "YES"
            s["DEBUG_INFORMATION_FORMAT"] = "dwarf"
        else:
            s["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
        ids.append(add(oid("cfg", tname, cfg), {"isa": "XCBuildConfiguration", "buildSettings": s, "name": cfg}))
    return add(oid("cfglist", tname), {"isa": "XCConfigurationList", "buildConfigurations": ids,
               "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Debug"})

def target(name, product_ref, ptype, sources, settings, resources=()):
    bfs = [add(oid("bf", name, rel(f, ROOT)), {"isa": "PBXBuildFile", "fileRef": fref(f)}) for f in sources]
    rbfs = [add(oid("rbf", name, rel(f, ROOT)), {"isa": "PBXBuildFile", "fileRef": fref(f)}) for f in resources]
    src = add(oid("srcphase", name), {"isa": "PBXSourcesBuildPhase", "buildActionMask": "2147483647", "files": bfs, "runOnlyForDeploymentPostprocessing": "0"})
    fw = add(oid("fwphase", name), {"isa": "PBXFrameworksBuildPhase", "buildActionMask": "2147483647", "files": [], "runOnlyForDeploymentPostprocessing": "0"})
    res = add(oid("resphase", name), {"isa": "PBXResourcesBuildPhase", "buildActionMask": "2147483647", "files": rbfs, "runOnlyForDeploymentPostprocessing": "0"})
    return add(oid("target", name), {"isa": "PBXNativeTarget", "buildConfigurationList": configs(name, settings),
               "buildPhases": [src, fw, res], "buildRules": [], "dependencies": [], "name": name,
               "productName": "VoyagerCalc" if "Tests" not in name else name, "productReference": product_ref, "productType": ptype})

app_sources = swift_app + swift_views + swift_core + swift_models + c_src
lib_sources = [f for f in app_sources if not f.endswith("VoyagerCalcApp.swift")]

t_mac = target("VoyagerCalc-macOS", p_mac, "com.apple.product-type.application", app_sources, {
    "PRODUCT_NAME": "VoyagerCalc", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID, "SDKROOT": "macosx",
    "SUPPORTED_PLATFORMS": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "INFOPLIST_FILE": "Resources/macOS/Info.plist", "CODE_SIGN_ENTITLEMENTS": "Resources/macOS/VoyagerCalc.entitlements",
    "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-", "DEVELOPMENT_TEAM": "",
    "ENABLE_HARDENED_RUNTIME": "YES", "COMBINE_HIDPI_IMAGES": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"}, faces + fonts + [mac_assets])
t_ios = target("VoyagerCalc-iOS", p_ios, "com.apple.product-type.application", app_sources, {
    "PRODUCT_NAME": "VoyagerCalc", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID, "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "TARGETED_DEVICE_FAMILY": "1,2",
    "INFOPLIST_FILE": "Resources/iOS/Info.plist", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"}, faces + fonts + [ios_assets])
t_test = target("VoyagerCalcTests", p_test, "com.apple.product-type.bundle.unit-test", lib_sources + tests, {
    "PRODUCT_NAME": "VoyagerCalcTests", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".tests", "SDKROOT": "macosx",
    "SUPPORTED_PLATFORMS": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "GENERATE_INFOPLIST_FILE": "YES",
    "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-", "DEVELOPMENT_TEAM": "",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks"}, faces + fonts)

proj_cfgs = []
for cfg in ("Debug", "Release"):
    s = {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
         "GCC_NO_COMMON_BLOCKS": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES"}
    if cfg == "Debug": s.update({"ENABLE_TESTABILITY": "YES", "GCC_PREPROCESSOR_DEFINITIONS": "DEBUG=1 $(inherited)"})
    else: s.update({"SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})
    proj_cfgs.append(add(oid("pcfg", cfg), {"isa": "XCBuildConfiguration", "buildSettings": s, "name": cfg}))
plist_list = add(oid("pcfglist"), {"isa": "XCConfigurationList", "buildConfigurations": proj_cfgs,
                 "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release"})
root = add(oid("project"), {"isa": "PBXProject", "attributes": {"BuildIndependentTargetsInParallel": "1", "LastSwiftUpdateCheck": "1500",
           "LastUpgradeCheck": "1500"}, "buildConfigurationList": plist_list, "compatibilityVersion": "Xcode 14.0",
           "developmentRegion": "en", "hasScannedForEncodings": "0", "knownRegions": ["en", "Base"], "mainGroup": g_main,
           "productRefGroup": g_products, "projectDirPath": "", "projectRoot": "", "targets": [t_mac, t_ios, t_test]})

os.makedirs(PROJ, exist_ok=True)
doc = {"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": dict(sorted(objects.items())), "rootObject": root}
with open(os.path.join(PROJ, "project.pbxproj"), "w") as f:
    f.write("// !$*UTF8*$!\n" + ser(doc) + "\n")

# shared schemes
sd = os.path.join(PROJ, "xcshareddata", "xcschemes"); os.makedirs(sd, exist_ok=True)
def ref(tid, name, product): return f'''<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tid}" BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:VoyagerCalc.xcodeproj"></BuildableReference>'''
def scheme(name, tid, product, test=None, env=None):
    testables = f'''<Testables><TestableReference skipped = "NO">{ref(test, "VoyagerCalcTests", "VoyagerCalcTests.xctest")}</TestableReference></Testables>''' if test else "<Testables></Testables>"
    envs = ""
    if env:
        envs = "<EnvironmentVariables>" + "".join(f'<EnvironmentVariable key = "{k}" value = "{v}" isEnabled = "YES"></EnvironmentVariable>' for k, v in env.items()) + "</EnvironmentVariables>"
    runnable = f'<BuildableProductRunnable runnableDebuggingMode = "0">{ref(tid, name, product)}</BuildableProductRunnable>' if product.endswith(".app") else ""
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref(tid, name, product)}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "NO">
      {envs}
      {testables}
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      {runnable}
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      {runnable}
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
open(os.path.join(sd, "VoyagerCalc-macOS.xcscheme"), "w").write(scheme("VoyagerCalc-macOS", t_mac, "VoyagerCalc.app", test=t_test))
open(os.path.join(sd, "VoyagerCalc-iOS.xcscheme"), "w").write(scheme("VoyagerCalc-iOS", t_ios, "VoyagerCalc.app"))
open(os.path.join(sd, "VoyagerCalcTests.xcscheme"), "w").write(scheme("VoyagerCalcTests", t_test, "VoyagerCalcTests.xctest", test=t_test))
print("wrote", PROJ, "with", len(objects), "objects")
