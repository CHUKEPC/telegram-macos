from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def declaration(source, marker):
    if source.count(marker) != 1:
        raise ValueError(f"Expected exactly one declaration: {marker}")
    start = source.index(marker)
    masked = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', lambda match: " " * len(match.group()), source, flags=re.S)
    opening = masked.index("{", start)
    depth = 1
    for index in range(opening + 1, len(masked)):
        depth += (masked[index] == "{") - (masked[index] == "}")
        if depth == 0:
            return source[start:index + 1]
    raise ValueError(f"Unclosed declaration: {marker}")


def check_wiring(controller, builtin, animated):
    search = controller[controller.index("if let search = state.search"):controller.index("let hasAnimatedRecent =")]
    search_calls = [line for line in search.splitlines() if "return EBlockItem(" in line]
    assert len(search_calls) == 1 and "segment: .Recent" in search_calls[0]
    assert "removeRecent:" not in search_calls[0]
    assert all("removeRecent:" not in line for line in search.splitlines() if "return EmojiesSectionRowItem(" in line)
    builtin_scope = declaration(controller, "if arguments.mode == .emoji || arguments.mode == .stories {\n                struct Tuple")
    assert "if key == .Recent {" in builtin_scope
    assert "removeRecent = nil" in builtin_scope
    assert "removeUsedEmoji(emoji, postbox: arguments.context.account.postbox).startStandalone()" in builtin_scope
    assert "removeRecent: removeRecent" in builtin_scope
    animated_scope = declaration(controller, "if key == .Recent, !recentAnimated.isEmpty, hasAnimatedRecent {")
    assert "if arguments.mode == .emoji || arguments.mode == .stories {" in animated_scope
    assert "removeRecent = nil" in animated_scope
    assert "removeAnimatedUsedEmoji(id, postbox: arguments.context.account.postbox).startStandalone()" in animated_scope
    assert "removeRecent: removeRecent" in animated_scope
    assert controller.count("removeRecent: removeRecent") == 2
    assert "removeRecent: ((String) -> Void)? = nil" in builtin
    assert "removeRecent: ((MediaId) -> Void)? = nil" in animated
    assert "private struct State : Equatable" in controller
    assert "ValuePromise<State>(ignoreRepeated: true)" in controller
    assert "current.recent = recentEmoji" in controller
    assert "recentUsedEmoji(postbox: context.account.postbox)" in controller
    assert "let lines = seg[key] ?? []" in builtin_scope
    print("PASS source wiring: search/category defaults, Recent emoji/stories guards, transaction calls, equality refresh chain", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Focused recent-emoji regression tests using real Cocoa, Strings and SwiftSignalKit.", epilog="Postbox transactions, preference storage, MediaId and UI row state are adapters; no live database, full UI dispatch, server or app build is verified.")
    parser.add_argument("--signal-kit", type=Path, required=True)
    parser.add_argument("--compatibility-ref", default="upstream/pr117")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    dependency = args.signal_kit.resolve()
    if not (dependency / "Package.swift").is_file():
        parser.error("Missing SSignalKit package")
    model_path = "packages/InAppSettings/Sources/InAppSettings/RecentUsedEmoji.swift"
    strings_path = "packages/Strings/Sources/Strings/Strings.swift"
    ui = root / "packages/EntertainmentUI/Sources/EntertainmentUI"
    model = (root / model_path).read_text()
    builtin = (ui / "EBlockItem.swift").read_text()
    animated = (ui / "EmojiesSectionRowItem.swift").read_text()
    controller = (ui / "EmojiesController.swift").read_text()
    check_wiring(controller, builtin, animated)
    renderer = declaration(controller, "private func segments(").removeprefix("private ")
    segment_list = controller[controller.index("    var seglist = seg.map"):controller.index("    let isPremium = state.peer?.peer.isPremium")].strip()
    replacements = {
        "__SEGMENT_LIST__": segment_list,
        "__SOURCE_KEY__": next(line for line in builtin.splitlines() if line.startswith("let recentEmojiSourceKey =")),
        "__BUILTIN_MENU__": declaration(builtin, "public override func menuItems(in location:").replace("public override func", "func", 1),
        "__BUILTIN_HIT__": declaration((ui / "EBlockRowView.swift").read_text(), "func emoji(at point:"),
        "__ANIMATED_REMOVAL_MENU__": declaration(animated, "if let removeRecent = removeRecent, let view = self.view as? EmojiesSectionRowView"),
        "__ANIMATED_HIT__": declaration(animated, "fileprivate func item(at point:"),
    }
    coding_key = dependency.parent / "TelegramCore/Sources/TelegramEngine/Utils/StringCodingKey.swift"
    replacements["__CODING_KEY__"] = coding_key.read_text()
    fixture = Path(__file__).with_name("RemoveRecentEmojiTests.swift.in").read_text()
    adapters = Path(__file__).with_name("Adapters.swift.in").read_text()
    for marker, source in replacements.items():
        if adapters.count(marker) != 1:
            raise ValueError(f"Expected exactly one placeholder: {marker}")
        print(f"{marker.strip('_')}: sha256 {hashlib.sha256(source.encode()).hexdigest()}", flush=True)
        adapters = adapters.replace(marker, source)
    revision = subprocess.check_output(["git", "-C", str(root), "rev-parse", args.compatibility_ref], text=True).strip()
    print(f"Compatibility source: {args.compatibility_ref} ({revision})", flush=True)
    def from_ref(path):
        return subprocess.check_output(["git", "-C", str(root), "show", f"{revision}:{path}"], text=True)
    compatible = from_ref(model_path)
    methods = "\n\n".join(declaration(model, marker) for marker in ["public func removingEmoji(", "public func removingAnimatedEmoji("])
    anchor = compatible.index("    public func encode(to encoder:", compatible.index("public class RecentUsedEmoji"))
    compatible = compatible[:anchor] + methods + "\n\n" + compatible[anchor:]
    compatible += "\n\n" + "\n\n".join(declaration(model, marker) for marker in ["public func removeUsedEmoji(", "public func removeAnimatedUsedEmoji("])
    assert declaration(compatible, "public func ==(lhs: RecentUsedEmoji,") == declaration(model, "public func ==(lhs: RecentUsedEmoji,")
    foreign_renderer = declaration(from_ref("packages/EntertainmentUI/Sources/EntertainmentUI/EmojiesController.swift"), "private func segments(")
    current_value = next(line for line in renderer.splitlines() if "let value =" in line)
    foreign_value = next(line for line in foreign_renderer.splitlines() if "let value =" in line)
    compatible_renderer = renderer.replace(current_value, foreign_value)
    variants = [("current", model, (root / strings_path).read_text(), renderer), ("pr117-composed", compatible, from_ref(strings_path), compatible_renderer)]
    status = 0
    with tempfile.TemporaryDirectory(prefix="remove-recent-emoji-") as temporary:
        directory = Path(temporary)
        (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RemoveRecentEmoji", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + json.dumps(str(dependency)) + ''')], targets: [.testTarget(name: "RemoveRecentEmojiTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
        tests = directory / "Tests"
        tests.mkdir()
        (tests / "Adapters.swift").write_text(adapters)
        for name, source, strings, segment_source in variants:
            print(f"RUN {name}; model sha256 {hashlib.sha256(source.encode()).hexdigest()}; Strings sha256 {hashlib.sha256(strings.encode()).hexdigest()}; segments sha256 {hashlib.sha256(segment_source.encode()).hexdigest()}", flush=True)
            (tests / "Segments.swift").write_text("import Cocoa\n" + segment_source)
            source = re.sub(r"^import (?:Postbox|TelegramCore|Strings)\n", "", source, flags=re.M)
            (tests / "RecentUsedEmoji.swift").write_text(source)
            (tests / "Strings.swift").write_text(strings)
            (tests / "RemoveRecentEmojiTests.swift").write_text(fixture.replace("__PR117__", str(name != "current").lower()))
            report = directory / f"{name}.xml"
            result = subprocess.run(["swift", "test", "--package-path", str(directory), "--disable-sandbox", "--jobs", "4", "--xunit-output", str(report)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            print(result.stdout, end="", flush=True)
            cases = ET.parse(report).getroot().findall(".//testcase") if report.exists() else []
            failures = [case.attrib.get("name") for case in cases if case.find("failure") is not None or case.find("error") is not None]
            if not cases:
                cases = re.findall(r"^Test Case '(.+)' (passed|failed) ", result.stdout, flags=re.M)
                failures = [case for case, outcome in cases if outcome == "failed"]
            print(f"SUMMARY {name}: {len(cases)} tests, {len(failures)} failing: {failures}", flush=True)
            status |= bool(result.returncode or failures or not cases)
    print("Scope: full production RecentUsedEmoji (module imports stripped only), full real Strings, real Cocoa/CoreText and SwiftSignalKit; JSON persistence is tested separately from the in-memory transactional adapter. Builtin menu body, segments and both hit-test helpers are extracted unchanged; font/attributed-string factory, MediaId, preferences and row/layer/menu models are adapters. Animated menu tests cover its removal branch only. Source wiring is checked, not full controller/UI execution or actual mouse dispatch. PR117 composition injects current removal methods/wrappers into that ref's whole model with its own Strings, and substitutes that ref's segments value expression; not a full merge, exhaustive PR117 review or full UI compatibility test.", flush=True)
    return int(status)


if __name__ == "__main__":
    raise SystemExit(main())
