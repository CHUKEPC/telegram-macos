# Avatar menu binding

Run `python3 -I tools/tests/avatar-menu-binding/run.py` on macOS.

The harness compiles the production `MenuContext` equality and `updateContextMenu` method with the repository's `ChatAvatarMenuBindingTests`. AppKit `NSMenu`/`NSMenuItem` are real; peer models, the avatar view and TGUIKit's closure-carrying item wrapper are adapters. The two model factory helpers are replaced for this harness. It does not compile the full ChatUI module or exercise live row layout.

Coverage includes same-context refresh, all five primary actions and nested actions, author/row/message/account/interaction/rights/mode/thread/story-context changes, live permission revalidation, latest-row liveness checks and removal. Source checks cover `setPeer` wiring and ensure message versions are not used as binding identity.

`--negative-control` restores unconditional UUID rotation in the extracted method; the same-context and latest-row-refresh cases must fail. Full module tests remain in `packages/ChatUI/Tests/ChatUITests/ChatAvatarMenuBindingTests.swift`.
