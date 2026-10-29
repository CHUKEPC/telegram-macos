# Contacts-only tab visibility

```sh
python3 -I tools/tests/contacts-tab/run.py
```

This local revision retains only the Contacts visibility preference from the closed combined Contacts/Wallet proposal. It is based on current upstream, not the old combined branch. Contacts remains visible by default and when decoding settings without the new key. Old experimental Wallet keys are ignored and are not written back.

The harness compiles the real settings model/Codable implementation and extracted tab-update methods with a minimal tab-controller adapter. It checks 449 assertions over 64 visibility/selection transitions, persistence, preservation of the preference through other settings mutations, and repeated updates. Source checks cover the settings action/order, Calls shortcut and theme indexing, absence of Wallet/action-tab infrastructure, and unchanged TGUIKit/localization files.

This is not a full application build or an AppKit event test.
