import Cocoa



open class TabItem: NSObject {
    let image: CGImage
    let selectedImage: CGImage
    public let controller:ViewController
    public let subNode:Node?
    public var accessibilityTitle: String?
    public let longHoverHandler:((Control)->Void)?
    public let customAction: (()->Void)?
    public init(image: CGImage, selectedImage: CGImage, controller:ViewController, subNode:Node? = nil, longHoverHandler:((Control)->Void)? = nil, customAction: (()->Void)? = nil) {
        self.image = image
        self.longHoverHandler = longHoverHandler
        self.selectedImage = selectedImage
        self.controller = controller
        self.subNode = subNode
        self.customAction = customAction
        super.init()
    }

    open func withUpdatedImages(_ image: CGImage, _ selectedImage: CGImage) -> TabItem {
        let item = TabItem(image: image, selectedImage: selectedImage, controller: self.controller, subNode: self.subNode, longHoverHandler: self.longHoverHandler, customAction: self.customAction)
        item.accessibilityTitle = accessibilityTitle
        return item
    }
    
    open func makeView() -> NSView {
        return ImageView(frame: NSMakeRect(0, 0, image.backingSize.width, image.backingSize.height))
    }
    
    open func setSelected(_ selected: Bool, for view: NSView, animated: Bool) {
        (view as? ImageView)?.image = selected ? selectedImage : image

    }
}
