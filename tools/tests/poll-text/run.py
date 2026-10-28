import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def source(path):
    return (root / path).read_text()


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


poll = source('packages/ChatUI/Sources/ChatUI/ChatPollItem.swift')
selection = source('packages/ChatUI/Sources/ChatUI/ChatSelectText.swift')
results = source('packages/PollResultsUI/Sources/PollResultsUI/PollResultController.swift')
sticky = source('packages/PollResultsUI/Sources/PollResultsUI/PollResultStickItem.swift')
peer = source('packages/TelegramUtils/Sources/TelegramUtils/PeerExtras.swift')
text = source('packages/TGUIKit/Sources/TextView.swift')
entities = source('packages/ChatUI/Sources/ChatUI/ChatMessageItem.swift')

assert 'ignoreLinks: !object.additionalData.canHighlightLinks && isIncoming' in poll
assert 'nameLayout.interactions = LinkHooks.shared.globalLinkExecutor()' not in poll
assert 'self.titleText.interactions = LinkHooks.shared.globalLinkExecutor()' not in poll
assert 'contentNode.update(with: item, animated: animated)\n        updateTextSelection()' in poll
assert 'super.notify(with: value, oldValue: oldValue, animated: animated)\n        updateTextSelection()' in poll
assert 'if chatTextSelectionDidDrag(from: start, to: location)' in selection
assert 'InputDataEquatable(canCopy)' in results
assert 'canCopyText: { copyPermission.with { $0 } }' in results
assert 'lhs.isTextSelectable == rhs.isTextSelectable' in source('packages/InputDataUI/Sources/InputDataUI/InputDataControllerEntries.swift')
assert 'view.isSelectable = canCopy' in poll
assert 'self.textView.textView.isSelectable = item.canCopy' in sticky
assert 'self.textView.textView.userInteractionEnabled = item.canCopy' in sticky
assert 'self.textView.userInteractionEnabled = item.canCopy' in sticky
assert 'self.descriptionText = layout' in poll

fixture = Path(__file__).with_name('PollTextTests.swift.in').read_text()
blocks = {
    '__THRESHOLD__': section(selection, 'func chatTextSelectionDidDrag(', 'public class ChatSelectText'),
    '__GESTURE__': section(poll, '    private var startMouseDownPoint:', '    private var option: PollOption?'),
    '__CLICK__': section(poll, '        set(handler: { [weak self] control in', '    required init?(coder: NSCoder) {').rsplit('    }', 1)[0],
    '__COPY_POLICY__': section(poll, '    fileprivate var canCopyText: Bool', '    public override init('),
    '__PEER_POLICY__': section(peer, '    func isCopyProtected(cachedData:', '    var maybePremiumRequired:'),
    '__INVALIDATE__': section(poll, '    private func updateTextSelection()', '    public override func canStartTextSelecting'),
    '__RESULT_POLICY__': section(results, '        let peer = peerViewMainPeer(peerView)', '        return pollResultEntries'),
    '__QUESTION_COPY__': section(results, '    let interactions =', '    entries.append(.desc'),
    '__OPTION_INTERACTIONS__': section(sticky, '        self.leftLayout.interactions =', '        self.leftAdditionLayout ='),
    '__OPTION_MENU__': section(sticky, '    public override func menuItems(', '    public required init(_ initialSize:'),
    '__TEXT_COPY__': section(text, '    @objc public func copy(_ sender:', '    public func checkEmbeddedUnderSpoiler').replace('@objc public ', ''),
    '__DESCRIPTION_COPY__': section(poll, '            layout.interactions = LinkHooks.shared.globalLinkExecutor()', '            self.descriptionText = layout'),
    '__ENTITY_FILTER__': section(entities, '        entities = concatMessageAttributes(entities).filter(', '        for entity in resolvedEntities'),
}
for key, value in blocks.items():
    fixture = fixture.replace(key, value)
assert '__' not in fixture

cases = ['click-selection', 'context-selection', 'radial-threshold', 'drag-return', 'intercepted-drag', 'accessibility', 'copy-policy', 'live-protection', 'result-permission', 'question-clipboard', 'option-clipboard', 'description-actions', 'incoming-entities']
with tempfile.TemporaryDirectory(prefix='poll-text-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    failed = 0
    for case in cases:
        result = subprocess.run([str(binary), case], capture_output=True, text=True)
        passed = result.returncode == 0
        failed += not passed
        print(f'{"PASS" if passed else "FAIL"} {case}')
        if not passed:
            print(result.stdout + result.stderr)
    print(f'{len(cases) - failed} passed; {failed} failed (extracted production code with Foundation adapters; no application/UI session)')
    raise SystemExit(bool(failed))
