//
//  Keychain.swift
//  EmbyDanmaku
//
//  访问令牌等敏感信息存入 Keychain（kSecClassGenericPassword）。
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpected(OSStatus)
    case notFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpected(let s): return "Keychain 错误：\(s)"
        case .notFound: return "Keychain 中未找到对应记录"
        case .invalidData: return "Keychain 数据格式异常"
        }
    }
}

struct Keychain {

    static let service = "cn.emby.danmaku"

    static func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        // 先删除旧值，避免 errSecDuplicateItem
        _ = try? delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
    }

    static func read(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
        guard let data = result as? Data, let str = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return str
    }

    @discardableResult
    static func delete(account: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
        return true
    }

    // MARK: - 便捷封装

    static func tokenKey(serverURL: String, userId: String) -> String {
        "token|\(serverURL.lowercased())|\(userId)"
    }

    static func passwordKey(serverURL: String, username: String) -> String {
        "password|\(serverURL.lowercased())|\(username)"
    }
}
