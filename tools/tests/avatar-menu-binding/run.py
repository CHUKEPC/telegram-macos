from pathlib import Path
import argparse
import re
import subprocess
import tempfile


def declaration(source, marker):
    assert source.count(marker) == 1, marker
    start = source.index(marker)
    masked = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m.group()), source, flags=re.S)
    opening = masked.index('{', start)
    if 'func ' in marker:
        parameter_start = masked.index('(', start)
        parentheses = 1
        parameter_end = parameter_start + 1
        while parentheses:
            parentheses += (masked[parameter_end] == '(') - (masked[parameter_end] == ')')
            parameter_end += 1
        opening = masked.index('{', parameter_end)
    depth = 1
    for index in range(opening + 1, len(masked)):
        depth += (masked[index] == '{') - (masked[index] == '}')
        if depth == 0:
            return source[start:index + 1]
    raise AssertionError(marker)


parser = argparse.ArgumentParser()
parser.add_argument('--negative-control', action='store_true', help='Restore unconditional token rotation to reproduce the reviewed bug.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatAvatarView.swift').read_text()
tests = (root / 'packages/ChatUI/Tests/ChatUITests/ChatAvatarMenuBindingTests.swift').read_text()
tests = re.sub(r'^(?:@testable )?import .*\n', '', tests, flags=re.M)
tests = tests.replace(declaration(tests, '    private func peer('), '''    private func peer(_ id: Int64 = 2) -> Peer { Peer(id: PeerId(id), canBan: false) }''')
tests = tests.replace(declaration(tests, '    private func channel('), '''    private func channel(canBan: Bool) -> Peer { Peer(id: PeerId(3), canBan: canBan) }''')
context = declaration(source, '    struct MenuContext: Equatable')
update = declaration(source, '    func updateContextMenu(')
if args.negative_control:
    update = update.replace('if factory == nil || context == nil || menuContext != context {', 'if true {')
models = '''import Cocoa
import XCTest
struct PeerId: Equatable { let value: Int64; init(_ value: Int64) { self.value = value } }
struct MessageId: Equatable { let peerId: PeerId; let namespace: Int32; let id: Int32 }
enum Namespaces { enum Message { static let Cloud: Int32 = 0 } }
enum ChatMode: Equatable { case history, pinned }
final class Peer {
    let id: PeerId
    let canBan: Bool
    init(id: PeerId, canBan: Bool) { self.id = id; self.canBan = canBan }
    func isEqual(_ other: Peer) -> Bool { id == other.id && canBan == other.canBan }
}
final class ContextMenu: NSMenu { convenience init() { self.init(title: "") } }
final class ContextMenuItem: NSMenuItem {
    var handler: (() -> Void)?
    init(_ title: String, handler: (() -> Void)? = nil) { self.handler = handler; super.init(title: title, action: nil, keyEquivalent: "") }
    required init(coder: NSCoder) { fatalError() }
}
enum UITestBootstrap { static func install() {} }
final class ChatAvatarView {
    init(frame: NSRect) {}
    var contextMenu: (() -> ContextMenu?)?
    private var menuBinding = UUID()
    private var menuContext: MenuContext?
    private var isMenuContextCurrent: () -> Bool = { false }
'''
methods = re.findall(r'    func (test\w+)\(', tests)
with tempfile.TemporaryDirectory(prefix='avatar-menu-binding-') as temporary:
    directory = Path(temporary)
    (directory / 'Tests').mkdir()
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AvatarMenuBinding", platforms: [.macOS(.v10_13)], targets: [.testTarget(name: "AvatarMenuBindingTests", path: "Tests")])
''')
    program = directory / 'Tests/AvatarMenuBindingTests.swift'
    program.write_text(models + context + '\n' + update + '\n}\n' + tests)
    result = subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4'])
    if result.returncode:
        raise SystemExit(result.returncode)
context_factory = declaration(source, '    private static func menuContext(')
assert 'stableVersion' not in context_factory
assert 'ObjectIdentifier(interaction.interactionContext.account)' in context_factory
assert 'rowId: item.stableId' in context_factory and 'messageId: item.message?.id' in context_factory
assert 'chatPeer: interaction.peer' in context_factory
binding = declaration(source, '    public func setPeer(')
assert 'context: menuContext, isCurrent: { [weak item]' in binding
assert 'Self.menuContext(item, peer: peer) == menuContext' in binding
assert 'self.updateContextMenu(nil)' in binding
print(f'PASS {len(methods)} XCTest cases; extracted production context equality and action binding; real NSMenu with model/TGUIKit adapters; source checks for setPeer wiring.')
