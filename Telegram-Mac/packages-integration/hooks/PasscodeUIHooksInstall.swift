import Cocoa
import SwiftSignalKit
import PasscodeUI
import PasscodeCore
import WalletContext
import BuildConfig
import ApiCredentials
import LocalAuthentication
import Darwin
import MachO

private var realSecItemAdd: (@convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus)?
private var realSecItemCopyMatching: (@convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus)?
private var realSecItemUpdate: (@convention(c) (CFDictionary, CFDictionary) -> OSStatus)?
private var realSecItemDelete: (@convention(c) (CFDictionary) -> OSStatus)?

private var symAdd: UnsafeMutableRawPointer?
private var repAdd: UnsafeMutableRawPointer?
private var symMatch: UnsafeMutableRawPointer?
private var repMatch: UnsafeMutableRawPointer?
private var symUpdate: UnsafeMutableRawPointer?
private var repUpdate: UnsafeMutableRawPointer?
private var symDelete: UnsafeMutableRawPointer?
private var repDelete: UnsafeMutableRawPointer?

private func hookedSecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let real = realSecItemAdd else { return errSecParam }
    let dict = attributes as NSDictionary
    if dict[kSecUseDataProtectionKeychain as String] == nil {
        let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, attributes)!
        CFDictionarySetValue(mutable, Unmanaged.passUnretained(kSecUseDataProtectionKeychain).toOpaque(), Unmanaged.passUnretained(kCFBooleanFalse).toOpaque())
        return real(mutable, result)
    }
    return real(attributes, result)
}

private func hookedSecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let real = realSecItemCopyMatching else { return errSecParam }
    let dict = query as NSDictionary
    if dict[kSecUseDataProtectionKeychain as String] == nil {
        let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query)!
        CFDictionarySetValue(mutable, Unmanaged.passUnretained(kSecUseDataProtectionKeychain).toOpaque(), Unmanaged.passUnretained(kCFBooleanFalse).toOpaque())
        return real(mutable, result)
    }
    return real(query, result)
}

private func hookedSecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
    guard let real = realSecItemUpdate else { return errSecParam }
    let dict = query as NSDictionary
    if dict[kSecUseDataProtectionKeychain as String] == nil {
        let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query)!
        CFDictionarySetValue(mutable, Unmanaged.passUnretained(kSecUseDataProtectionKeychain).toOpaque(), Unmanaged.passUnretained(kCFBooleanFalse).toOpaque())
        return real(mutable, attributesToUpdate)
    }
    return real(query, attributesToUpdate)
}

private func hookedSecItemDelete(_ query: CFDictionary) -> OSStatus {
    guard let real = realSecItemDelete else { return errSecParam }
    let dict = query as NSDictionary
    if dict[kSecUseDataProtectionKeychain as String] == nil {
        let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query)!
        CFDictionarySetValue(mutable, Unmanaged.passUnretained(kSecUseDataProtectionKeychain).toOpaque(), Unmanaged.passUnretained(kCFBooleanFalse).toOpaque())
        return real(mutable)
    }
    return real(query)
}

private func patchDyldImageHeader(header: UnsafePointer<mach_header>?, slide: Int) {
    guard let header = header else { return }
    let pageSize = sysconf(_SC_PAGESIZE)
    var cur = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
    for _ in 0 ..< header.pointee.ncmds {
        let lc = cur.assumingMemoryBound(to: load_command.self)
        if lc.pointee.cmd == LC_SEGMENT_64 {
            let seg = cur.assumingMemoryBound(to: segment_command_64.self)
            let segName = withUnsafePointer(to: seg.pointee.segname) {
                $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
            }
            if segName.hasPrefix("__DATA") {
                let sectPtr = cur.advanced(by: MemoryLayout<segment_command_64>.size).assumingMemoryBound(to: section_64.self)
                for k in 0 ..< Int(seg.pointee.nsects) {
                    let sect = sectPtr.advanced(by: k).pointee
                    let sectName = withUnsafePointer(to: sect.sectname) {
                        $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
                    }
                    if sectName == "__got" || sectName == "__la_symbol_ptr" || sectName == "__auth_got" {
                        guard let got = UnsafeMutablePointer<UnsafeMutableRawPointer?>.init(bitPattern: UInt(slide + Int(sect.addr))) else {
                            continue
                        }
                        let countPtrs = Int(sect.size) / MemoryLayout<UnsafeMutableRawPointer?>.size
                        for p in 0 ..< countPtrs {
                            let targetRep: UnsafeMutableRawPointer?
                            if got[p] == symAdd {
                                targetRep = repAdd
                            } else if got[p] == symMatch {
                                targetRep = repMatch
                            } else if got[p] == symUpdate {
                                targetRep = repUpdate
                            } else if got[p] == symDelete {
                                targetRep = repDelete
                            } else {
                                targetRep = nil
                            }
                            if let targetRep {
                                let ptrAddr = UInt(bitPattern: got.advanced(by: p))
                                let pageStart = ptrAddr & ~UInt(pageSize - 1)
                                mprotect(UnsafeMutableRawPointer(bitPattern: pageStart), pageSize, PROT_READ | PROT_WRITE)
                                got[p] = targetRep
                                mprotect(UnsafeMutableRawPointer(bitPattern: pageStart), pageSize, PROT_READ)
                            }
                        }
                    }
                }
            }
        }
        cur = cur.advanced(by: Int(lc.pointee.cmdsize))
    }
}

private var didInstallKeychainHook = false
private let keychainHookLock = NSLock()

private func installKeychainDataProtectionCompatHook() {
    keychainHookLock.lock()
    defer { keychainHookLock.unlock() }
    guard !didInstallKeychainHook else { return }
    didInstallKeychainHook = true

    let handle = dlopen(nil, RTLD_NOW)
    symAdd = dlsym(handle, "SecItemAdd")
    realSecItemAdd = unsafeBitCast(symAdd, to: (@convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus).self)
    repAdd = unsafeBitCast(hookedSecItemAdd as (@convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus), to: UnsafeMutableRawPointer.self)

    symMatch = dlsym(handle, "SecItemCopyMatching")
    realSecItemCopyMatching = unsafeBitCast(symMatch, to: (@convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus).self)
    repMatch = unsafeBitCast(hookedSecItemCopyMatching as (@convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus), to: UnsafeMutableRawPointer.self)

    symUpdate = dlsym(handle, "SecItemUpdate")
    realSecItemUpdate = unsafeBitCast(symUpdate, to: (@convention(c) (CFDictionary, CFDictionary) -> OSStatus).self)
    repUpdate = unsafeBitCast(hookedSecItemUpdate as (@convention(c) (CFDictionary, CFDictionary) -> OSStatus), to: UnsafeMutableRawPointer.self)

    symDelete = dlsym(handle, "SecItemDelete")
    realSecItemDelete = unsafeBitCast(symDelete, to: (@convention(c) (CFDictionary) -> OSStatus).self)
    repDelete = unsafeBitCast(hookedSecItemDelete as (@convention(c) (CFDictionary) -> OSStatus), to: UnsafeMutableRawPointer.self)

    _dyld_register_func_for_add_image(patchDyldImageHeader)
}

func passcodeCredentialKind(for code: String) -> PasscodeKind {
    let normalized = PasscodeKind.digits4.normalize(code)
    if normalized.allSatisfy({ $0.isASCII && $0.isNumber }) {
        if normalized.count == 4 {
            return .digits4
        }
        if normalized.count == 6 {
            return .digits6
        }
    }
    return .alphanumeric
}

private func passcodeRootPath() -> String? {
    return ApiEnvironment.containerURL?.path
}

@available(macOS 10.15, *)
func syncPasscodeCredential(code: String, rootPath: String) {
    let encryption = AppEncryptionParameters(path: rootPath)
    guard encryption.hasPasscode() else {
        return
    }
    encryption.applyPasscode(code)
    guard encryption.decrypt() != nil else {
        return
    }
    try? adoptPasscodeCredential(code: code)
}

@available(macOS 10.15, *)
func adoptPasscodeCredential(code: String, isNewPasscode: Bool = false) throws {
    let store = PasscodeCredentialStore.shared
    switch try store.managedReference() {
    case .none where !isNewPasscode:
        _ = try store.migrateLegacy(code: code, kind: passcodeCredentialKind(for: code))
    case .none, .some(.none):
        _ = try store.setPasscode(code, kind: passcodeCredentialKind(for: code), session: nil)
    case .some(.some):
        break
    }
    UserDefaults.standard.set(true, forKey: walletPasscodeCredentialManagedKey)
}

@available(macOS 10.15, *)
private func passcodeSettingsSession(code: String) throws -> PasscodeSession {
    if let rootPath = passcodeRootPath() {
        syncPasscodeCredential(code: code, rootPath: rootPath)
    }
    return try PasscodeCredentialStore.shared.verify(code, scope: .settings)
}

private func passcodeCredentialOperation(_ completion: @escaping PasscodeCredentialSyncCompletion, _ operation: @escaping () throws -> Void) {
    Queue.concurrentDefaultQueue().async {
        let result: Result<Void, PasscodeCredentialSyncError>
        do {
            try operation()
            result = .success(())
        } catch PasscodeError.invalidCode {
            result = .failure(.invalidCode)
        } catch let PasscodeError.cooldown(seconds) {
            result = .failure(.cooldown(seconds))
        } catch {
            result = .failure(.failed)
        }
        Queue.mainQueue().async {
            completion(result)
        }
    }
}

func installPasscodeUIHooks() {
    installKeychainDataProtectionCompatHook()
    var hooks = PasscodeCredentialHooks()
    hooks.passcodeInstalled = { code, completion in
        guard #available(macOS 10.15, *) else {
            completion(.success(()))
            return
        }
        passcodeCredentialOperation(completion) {
            try adoptPasscodeCredential(code: code, isNewPasscode: true)
        }
    }
    hooks.passcodeChanged = { current, code, completion in
        guard #available(macOS 10.15, *) else {
            completion(.success(()))
            return
        }
        passcodeCredentialOperation(completion) {
            let session = try passcodeSettingsSession(code: current)
            defer {
                session.invalidate()
            }
            _ = try PasscodeCredentialStore.shared.setPasscode(code, kind: passcodeCredentialKind(for: code), session: session)
        }
    }
    hooks.passcodeDisabled = { current, completion in
        guard #available(macOS 10.15, *) else {
            completion(.success(()))
            return
        }
        passcodeCredentialOperation(completion) {
            let session = try passcodeSettingsSession(code: current)
            try PasscodeCredentialStore.shared.disablePasscode(session: session)
        }
    }
    hooks.passcodeUnlocked = { code in
        guard #available(macOS 10.15, *), let rootPath = passcodeRootPath() else {
            return
        }
        Queue.concurrentDefaultQueue().async {
            syncPasscodeCredential(code: code, rootPath: rootPath)
        }
    }
    hooks.walletProtection = {
        guard #available(macOS 10.15, *) else {
            return .single(nil)
        }
        return (Signal<Void, NoError>.single(Void()) |> then(PasscodeCredentialStore.shared.changes)) |> mapToSignal { _ -> Signal<PasscodeWalletProtection?, NoError> in
            return Signal { subscriber in
                let settings = try? walletProtectionSettings()
                subscriber.putNext(settings.map { PasscodeWalletProtection(enabled: $0.enabled, biometricsEnabled: $0.biometricsEnabled) })
                subscriber.putCompletion()
                return EmptyDisposable
            } |> runOn(Queue.concurrentDefaultQueue())
        }
    }
    hooks.setWalletProtection = { enabled, code, completion in
        guard #available(macOS 10.15, *) else {
            completion(.failure(.failed))
            return
        }
        passcodeCredentialOperation(completion) {
            let session = try passcodeSettingsSession(code: code)
            defer {
                session.invalidate()
            }
            try setWalletProtectionEnabled(enabled, session: session)
        }
    }
    hooks.setWalletBiometrics = { enabled, code, completion in
        guard #available(macOS 10.15, *) else {
            completion(.failure(.failed))
            return
        }
        let laContext = LAContext()
        laContext.localizedReason = strings().walletBiometricsEnableReason
        laContext.localizedFallbackTitle = ""
        laContext.touchIDAuthenticationAllowableReuseDuration = 0
        let perform: () -> Void = {
            passcodeCredentialOperation(completion) {
                let session = try passcodeSettingsSession(code: code)
                defer {
                    laContext.invalidate()
                    session.invalidate()
                }
                try setWalletBiometricsEnabled(enabled, session: session, context: laContext)
            }
        }
        if enabled {
            laContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: strings().walletBiometricsEnableReason) { success, _ in
                if success {
                    perform()
                } else {
                    laContext.invalidate()
                    Queue.mainQueue().async {
                        completion(.failure(.failed))
                    }
                }
            }
        } else {
            perform()
        }
    }
    PasscodeCredentialHooks.install(hooks)
}
