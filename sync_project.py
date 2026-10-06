#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sync_project.py —— 根据 Sources/ 目录里的实际文件重建 EmbyDanmaku.xcodeproj/project.pbxproj

为什么需要它：
    仓库里提交的是一份「写死了文件清单」的 Xcode 工程。只要新增 / 删除 / 重命名
    了 .swift 文件，工程文件就必须同步，否则云端 xcodebuild 不会编译新文件
    （也不会报错，只是功能静默缺失）。本脚本让这件事自动化：云端构建前跑一次即可。

用法：
    python3 sync_project.py
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SOURCES = "Sources"
RESOURCES = "Resources"
PROJECT = "EmbyDanmaku.xcodeproj"
APP_NAME = "EmbyDanmaku"
BUNDLE_ID = "com.emby.danmaku"


def uid(key):
    """由路径派生稳定的 24 位十六进制 ID（Xcode 风格）"""
    return hashlib.md5(key.encode("utf-8")).hexdigest().upper()[:24]


def collect():
    """返回 {相对目录: [文件名]}，目录按 Sources 下的子路径"""
    tree = {}
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, SOURCES)):
        dirnames.sort()
        swift = sorted(f for f in filenames if f.endswith(".swift"))
        if not swift:
            continue
        rel = os.path.relpath(dirpath, ROOT).replace(os.sep, "/")
        tree[rel] = swift
    return tree


def main():
    tree = collect()
    if not tree:
        print("× 没有在 %s 下找到任何 .swift 文件" % SOURCES)
        return 1

    total = sum(len(v) for v in tree.values())
    print("扫描到 %d 个目录、%d 个 Swift 文件" % (len(tree), total))

    # ---- 收集所有 swift 文件（按目录排序，保证输出稳定）----
    swift_files = []
    for d in sorted(tree.keys()):
        for f in tree[d]:
            swift_files.append((d, f))

    L = []
    a = L.append
    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {")
    a("\t};")
    a("\tobjectVersion = 56;")
    a("\tobjects = {")
    a("")

    # ---------- PBXBuildFile ----------
    a("/* Begin PBXBuildFile section */")
    res_build_id = uid("build:Resources/Assets.xcassets")
    res_ref_id = uid("file:Resources/Assets.xcassets")
    a("\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };"
      % (res_build_id, res_ref_id))
    for d, f in swift_files:
        a("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
          % (uid("build:" + d + "/" + f), f, uid("file:" + d + "/" + f), f))
    a("/* End PBXBuildFile section */")
    a("")

    # ---------- PBXFileReference ----------
    a("/* Begin PBXFileReference section */")
    app_ref = uid("product:EmbyDanmaku.app")
    a('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; '
      'includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };'
      % (app_ref, APP_NAME, APP_NAME))
    for d, f in swift_files:
        a('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
          'path = "%s"; sourceTree = "<group>"; };' % (uid("file:" + d + "/" + f), f, f))
    a('\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; '
      'path = Info.plist; sourceTree = "<group>"; };' % uid("file:Resources/Info.plist"))
    a('\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = '
      'folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };' % res_ref_id)
    a("/* End PBXFileReference section */")
    a("")

    # ---------- PBXFrameworksBuildPhase ----------
    fw_id = uid("phase:Frameworks")
    a("/* Begin PBXFrameworksBuildPhase section */")
    a("\t\t%s /* Frameworks */ = {" % fw_id)
    a("\t\t\tisa = PBXFrameworksBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXFrameworksBuildPhase section */")
    a("")

    # ---------- PBXGroup ----------
    def walk_group(path, depth):
        pad = "\t" * depth
        name = os.path.basename(path)
        gid = uid("group:" + path)
        entries = sorted(os.listdir(os.path.join(ROOT, path)))
        dirs = [e for e in entries
                if os.path.isdir(os.path.join(ROOT, path, e))
                and any(fn.endswith(".swift")
                        for _, _, fs in os.walk(os.path.join(ROOT, path, e)) for fn in fs)]
        files = [e for e in entries
                 if os.path.isfile(os.path.join(ROOT, path, e)) and e.endswith(".swift")]
        out = []
        out.append("%s%s /* %s */ = {" % (pad, gid, name))
        out.append("%s\tisa = PBXGroup;" % pad)
        out.append("%s\tchildren = (" % pad)
        for d in dirs:
            out.append("%s\t\t%s /* %s */," % (pad, uid("group:" + path + "/" + d), d))
        for f in files:
            out.append("%s\t\t%s /* %s */," % (pad, uid("file:" + path + "/" + f), f))
        out.append("%s\t);" % pad)
        out.append('%s\tpath = "%s";' % (pad, name))
        out.append('%s\tsourceTree = "<group>";' % pad)
        out.append("%s};" % pad)
        for d in dirs:
            out.extend(walk_group(path + "/" + d, depth))
        return out

    a("/* Begin PBXGroup section */")
    a("\t\t%s /* Sources */ = {" % uid("group:Sources"))
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    top_entries = sorted(os.listdir(os.path.join(ROOT, SOURCES)))
    top_dirs = [e for e in top_entries
                if os.path.isdir(os.path.join(ROOT, SOURCES, e))
                and any(fn.endswith(".swift")
                        for _, _, fs in os.walk(os.path.join(ROOT, SOURCES, e)) for fn in fs)]
    top_files = [e for e in top_entries
                 if os.path.isfile(os.path.join(ROOT, SOURCES, e)) and e.endswith(".swift")]
    for d in top_dirs:
        a("\t\t\t\t%s /* %s */," % (uid("group:Sources/" + d), d))
    for f in top_files:
        a("\t\t\t\t%s /* %s */," % (uid("file:Sources/" + f), f))
    a("\t\t\t);")
    a('\t\t\tpath = "Sources";')
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    for d in top_dirs:
        a("\n".join(walk_group(SOURCES + "/" + d, 2)))
    # Resources
    a("\t\t%s /* Resources */ = {" % uid("group:Resources"))
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a("\t\t\t\t%s /* Info.plist */," % uid("file:Resources/Info.plist"))
    a("\t\t\t\t%s /* Assets.xcassets */," % res_ref_id)
    a("\t\t\t);")
    a('\t\t\tpath = "Resources";')
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    # Products
    prod_id = uid("group:Products")
    a("\t\t%s /* Products */ = {" % prod_id)
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a("\t\t\t\t%s /* %s.app */," % (app_ref, APP_NAME))
    a("\t\t\t);")
    a('\t\t\tname = "Products";')
    a("\t\t\tsourceTree = \"<group>\";")
    a("\t\t};")
    # Root
    root_id = uid("group:__root__")
    a("\t\t%s /* %s */ = {" % (root_id, APP_NAME))
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a("\t\t\t\t%s /* Sources */," % uid("group:Sources"))
    a("\t\t\t\t%s /* Resources */," % uid("group:Resources"))
    a("\t\t\t\t%s /* Products */," % prod_id)
    a("\t\t\t);")
    a('\t\t\tname = "%s";' % APP_NAME)
    a("\t\t\tsourceTree = \"<group>\";")
    a("\t\t};")
    a("/* End PBXGroup section */")
    a("")

    # ---------- PBXNativeTarget ----------
    src_phase = uid("phase:Sources")
    res_phase = uid("phase:Resources")
    target_id = uid("target:EmbyDanmaku")
    tgt_cfg_list = uid("cfglist:target")
    a("/* Begin PBXNativeTarget section */")
    a("\t\t%s /* %s */ = {" % (target_id, APP_NAME))
    a("\t\t\tisa = PBXNativeTarget;")
    a("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "
      '"%s" */;' % (tgt_cfg_list, APP_NAME))
    a("\t\t\tbuildPhases = (")
    a("\t\t\t\t%s /* Sources */," % src_phase)
    a("\t\t\t\t%s /* Frameworks */," % fw_id)
    a("\t\t\t\t%s /* Resources */," % res_phase)
    a("\t\t\t);")
    a("\t\t\tbuildRules = (")
    a("\t\t\t);")
    a("\t\t\tdependencies = (")
    a("\t\t\t);")
    a("\t\t\tname = %s;" % APP_NAME)
    a("\t\t\tproductName = %s;" % APP_NAME)
    a("\t\t\tproductReference = %s /* %s.app */;" % (app_ref, APP_NAME))
    a('\t\t\tproductType = "com.apple.product-type.application";')
    a("\t\t};")
    a("/* End PBXNativeTarget section */")
    a("")

    # ---------- PBXProject ----------
    proj_id = uid("project:EmbyDanmaku")
    proj_cfg_list = uid("cfglist:project")
    a("/* Begin PBXProject section */")
    a("\t\t%s /* Project object */ = {" % proj_id)
    a("\t\t\tisa = PBXProject;")
    a("\t\t\tattributes = {")
    a("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    a("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    a("\t\t\t\tLastUpgradeCheck = 1500;")
    a("\t\t\t\tTargetAttributes = {")
    a("\t\t\t\t\t%s = {" % target_id)
    a("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    a("\t\t\t\t\t};")
    a("\t\t\t\t};")
    a("\t\t\t};")
    a("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "
      '"%s" */;' % (proj_cfg_list, APP_NAME))
    a('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    a("\t\t\tdevelopmentRegion = en;")
    a("\t\t\thasScannedForEncodings = 0;")
    a("\t\t\tknownRegions = (")
    a("\t\t\t\ten,")
    a("\t\t\t\tBase,")
    a("\t\t\t);")
    a("\t\t\tmainGroup = %s;" % root_id)
    a("\t\t\tproductRefGroup = %s;" % prod_id)
    a('\t\t\tprojectDirPath = "";')
    a('\t\t\tprojectRoot = "";')
    a("\t\t\ttargets = (")
    a("\t\t\t\t%s /* %s */," % (target_id, APP_NAME))
    a("\t\t\t);")
    a("\t\t};")
    a("/* End PBXProject section */")
    a("")

    # ---------- PBXResourcesBuildPhase ----------
    a("/* Begin PBXResourcesBuildPhase section */")
    a("\t\t%s /* Resources */ = {" % res_phase)
    a("\t\t\tisa = PBXResourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a("\t\t\t\t%s /* Assets.xcassets in Resources */," % res_build_id)
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXResourcesBuildPhase section */")
    a("")

    # ---------- PBXSourcesBuildPhase ----------
    a("/* Begin PBXSourcesBuildPhase section */")
    a("\t\t%s /* Sources */ = {" % src_phase)
    a("\t\t\tisa = PBXSourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    for d, f in swift_files:
        a("\t\t\t\t%s /* %s in Sources */," % (uid("build:" + d + "/" + f), f))
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXSourcesBuildPhase section */")
    a("")

    # ---------- XCBuildConfiguration ----------
    proj_debug = uid("cfg:project:Debug")
    proj_release = uid("cfg:project:Release")
    tgt_debug = uid("cfg:target:Debug")
    tgt_release = uid("cfg:target:Release")

    def common(dt, extra_before=None, extra_after=None):
        out = []
        out.append("\t\t\tbuildSettings = {")
        out.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        out.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
        out.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
        out.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
        out.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
        out.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
        out.append("\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;")
        out.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
        out.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;")
        out.append("\t\t\t\tSDKROOT = iphoneos;")
        out.append('\t\t\t\tSWIFT_VERSION = 5.9;')
        out.append('\t\t\t\tSWIFT_STRICT_CONCURRENCY = minimal;')
        if extra_before:
            out.extend(extra_before)
        if extra_after:
            out.extend(extra_after)
        out.append("\t\t\t};")
        return out

    dbg_extra = [
        "\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;",
        "\t\t\t\tENABLE_TESTABILITY = YES;",
        "\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;",
        "\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (",
        '\t\t\t\t\t\t"DEBUG=1",',
        '\t\t\t\t\t\t"$(inherited)",',
        "\t\t\t\t\t);",
        "\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
        "\t\t\t\tONLY_ACTIVE_ARCH = YES;",
        "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
        '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";',
    ]
    rel_extra = [
        '\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
        "\t\t\t\tENABLE_NS_ASSERTIONS = NO;",
        "\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;",
        "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;",
        '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";',
        "\t\t\t\tVALIDATE_PRODUCT = YES;",
    ]
    tgt_extra = [
        "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
        "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;",
        "\t\t\t\tINFOPLIST_FILE = Resources/Info.plist;",
        "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (",
        "\t\t\t\t\t\"$(inherited)\",",
        '\t\t\t\t\t"@executable_path/Frameworks",',
        "\t\t\t\t\t);",
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = %s;" % BUNDLE_ID,
        "\t\t\t\tPRODUCT_NAME = %s;" % APP_NAME,
        '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";',
    ]

    a("/* Begin XCBuildConfiguration section */")
    a("\t\t%s /* Debug */ = {" % proj_debug)
    a("\t\t\tisa = XCBuildConfiguration;")
    a("\n".join(common("Debug", extra_before=dbg_extra)))
    a("\t\t\tname = Debug;")
    a("\t\t};")
    a("\t\t%s /* Release */ = {" % proj_release)
    a("\t\t\tisa = XCBuildConfiguration;")
    a("\n".join(common("Release", extra_before=rel_extra)))
    a("\t\t\tname = Release;")
    a("\t\t};")
    a("\t\t%s /* Debug */ = {" % tgt_debug)
    a("\t\t\tisa = XCBuildConfiguration;")
    a("\n".join(common("Debug", extra_before=dbg_extra, extra_after=tgt_extra)))
    a("\t\t\tname = Debug;")
    a("\t\t};")
    a("\t\t%s /* Release */ = {" % tgt_release)
    a("\t\t\tisa = XCBuildConfiguration;")
    a("\n".join(common("Release", extra_before=rel_extra, extra_after=tgt_extra)))
    a("\t\t\tname = Release;")
    a("\t\t};")
    a("/* End XCBuildConfiguration section */")
    a("")

    # ---------- XCConfigurationList ----------
    a("/* Begin XCConfigurationList section */")
    a('\t\t%s /* Build configuration list for PBXProject "%s" */ = {' % (proj_cfg_list, APP_NAME))
    a("\t\t\tisa = XCConfigurationList;")
    a("\t\t\tbuildConfigurations = (")
    a("\t\t\t\t%s /* Debug */," % proj_debug)
    a("\t\t\t\t%s /* Release */," % proj_release)
    a("\t\t\t);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
    a('\t\t%s /* Build configuration list for PBXNativeTarget "%s" */ = {' % (tgt_cfg_list, APP_NAME))
    a("\t\t\tisa = XCConfigurationList;")
    a("\t\t\tbuildConfigurations = (")
    a("\t\t\t\t%s /* Debug */," % tgt_debug)
    a("\t\t\t\t%s /* Release */," % tgt_release)
    a("\t\t\t);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
    a("/* End XCConfigurationList section */")
    a("\t};")
    a("\trootObject = %s /* Project object */;" % proj_id)
    a("}")

    pbx = os.path.join(ROOT, PROJECT, "project.pbxproj")
    os.makedirs(os.path.dirname(pbx), exist_ok=True)
    with open(pbx, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")

    print("✓ 已重建 %s/project.pbxproj（%d 个源文件）" % (PROJECT, len(swift_files)))
    for d in sorted(tree.keys()):
        print("    %s  (%d)" % (d, len(tree[d])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
