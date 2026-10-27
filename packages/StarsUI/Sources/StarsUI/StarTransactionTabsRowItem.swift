import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows

final class StarTransactionTabsRowItem: GeneralRowItem {
    let items: [ScrollableSegmentItem]
    let callback: (Int64) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, items: [ScrollableSegmentItem], viewType: GeneralViewType, callback: @escaping (Int64) -> Void) {
        self.items = items
        self.callback = callback
        super.init(initialSize, height: GlassSegmentView.height + 16, stableId: stableId, viewType: viewType)
    }

    override var hasBorder: Bool {
        return false
    }

    override func viewClass() -> AnyClass {
        return StarTransactionTabsRowView.self
    }

    override var accessibilityLabel: String? {
        return items.first(where: { $0.selected })?.title ?? items.first?.title
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return items.map { item in
            NSAccessibilityCustomAction(name: item.title, handler: { [weak self] in
                guard let self else { return false }
                self.callback(item.uniqueId)
                return true
            })
        }
    }
}

private final class StarTransactionTabsRowView: GeneralContainableRowView {
    private let scrollView = HorizontalScrollView(frame: .zero)
    private let documentView = View()
    private let segments = GlassSegmentView(frame: .zero)
    private var focusSelection = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scrollView)
        scrollView.documentView = documentView
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.contentView.drawsBackground = false
        documentView.addSubview(segments)
        segments.didSelect = { [weak self] index in
            guard let item = self?.item as? StarTransactionTabsRowItem, item.items.indices.contains(index) else {
                return
            }
            item.callback(item.items[index].uniqueId)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? StarTransactionTabsRowItem else { return }
        let selected = item.items.firstIndex(where: { $0.selected })
        focusSelection = segments.selectedIndex != selected || segments.titles != item.items.map { $0.title }
        segments.updateLocalizationAndTheme(theme: theme)
        segments.set(titles: item.items.map { $0.title }, selected: selected, animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        needsLayout = true
    }

    override func updateColors() {
        super.updateColors()
        segments.updateLocalizationAndTheme(theme: theme)
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        needsLayout = true
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        let contentSize = segments.contentSize
        let width = max(0, containerView.bounds.width - 16)
        let viewportWidth = min(width, contentSize.width)
        let frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (containerView.bounds.width - viewportWidth) / 2), 8, viewportWidth, contentSize.height)
        transition.updateFrame(view: scrollView, frame: frame)
        documentView.setFrameSize(contentSize)
        segments.frame = NSRect(origin: .zero, size: contentSize)
        let maxOffset = max(0, contentSize.width - viewportWidth)
        var offset = min(max(0, scrollView.clipView.bounds.minX), maxOffset)
        if focusSelection, let selected = segments.selectedIndex {
            offset = maxOffset * CGFloat(selected) / CGFloat(max(1, segments.titles.count - 1))
        }
        focusSelection = false
        scrollView.clipView.scroll(to: NSPoint(x: offset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.clipView)
    }
}
