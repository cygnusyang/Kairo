// UpdateChecksum.swift —— 更新产物 SHA256 完整性校验。
//
// 移植自 COFFER OTA（macos/Coffer/Updater/UpdateChecksum.swift），原样通用。
//
// 在 UpdaterManager.download() 的下载落盘之后、ditto 解压之前调用：对 zip 文件
// 字节流式算 SHA256（CryptoKit，分块读取，不整包载入内存），与清单声明的
// sha256 比对——不匹配即拒装（fail-closed）。

import Foundation
import CryptoKit

/// 下载包 SHA256 校验的显式错误（用户可见文案 fail-closed）。
public enum UpdateChecksumError: Error, UpdaterCodedError {
    /// 计算失败（下载文件不可读 / 读取中断）。
    case readFailed(String)
    /// 与清单声明不一致（fail-closed 拒装）。
    case mismatch

    public var code: UpdaterErrorCode {
        switch self {
        case .readFailed: return .checksumReadFailed
        case .mismatch: return .checksumMismatch
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .readFailed(let detail): return ["detail": detail]
        case .mismatch: return [:]
        }
    }
}

/// 更新产物 SHA256 工具。
public enum UpdateChecksum {
    /// 流式计算文件 SHA256 hex（64KB 块读取，内存占用恒定）。
    public static func sha256Hex(of url: URL) throws -> String {
        var hasher = SHA256()
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw UpdateChecksumError.readFailed("\(error)")
        }
        defer { try? handle.close() }
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 64 * 1024)
            } catch {
                throw UpdateChecksumError.readFailed("\(error)")
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
