//
//  Prefs.swift
//  统一的偏好存储
//
//  注意：CLI 通过 build/vela 符号链接调用时，Bundle.main 解析不到 Info.plist，
//  bundleIdentifier 为 nil，UserDefaults.standard 会落到另一个域。
//  所以这里固定用 suite 名，GUI 和 CLI 读写同一份设置。
//

import Foundation

enum Prefs {
    static let suiteName = "dev.vela.mac.prefs"
    /// 更名前（AsusControl / ROG X 时期）的设置域，首次启动时整体搬过来，
    /// 免得改名把主题、采样间隔、菜单栏勾选项、上次背光档位全清空。
    private static let legacySuiteName = "dev.asuscontrol.mac.prefs"

    static let store: UserDefaults = {
        let current = UserDefaults(suiteName: suiteName) ?? .standard
        let isEmpty = current.persistentDomain(forName: suiteName)?.isEmpty ?? true
        if isEmpty,
           let legacy = UserDefaults(suiteName: legacySuiteName),
           let dict = legacy.persistentDomain(forName: legacySuiteName), !dict.isEmpty {
            for (key, value) in dict { current.set(value, forKey: key) }
        }
        return current
    }()

    static func string(_ key: String) -> String? {
        store.string(forKey: key)
    }

    static func set(_ value: String?, for key: String) {
        if let value, !value.isEmpty {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    static func int(_ key: String, default def: Int = 0) -> Int {
        store.object(forKey: key) as? Int ?? def
    }

    static func set(_ value: Int, for key: String) {
        store.set(value, forKey: key)
    }

    static func bool(_ key: String) -> Bool {
        store.bool(forKey: key)
    }

    static func set(_ value: Bool, for key: String) {
        store.set(value, forKey: key)
    }
}
