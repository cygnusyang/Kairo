// OTANetworkLayer.swift —— OTA 网络层（应用层白名单落地）。
//
// 移植自 COFFER OTA（macos/Coffer/Updater/OTANetworkLayer.swift），通用化改造：
// 白名单策略经 init 注入；下载临时文件名前缀参数化。
//
// 协议抽象 = 注入点（测试用 stub 数据无真网测试）；生产实现 =
// OTANetworkSession（URLSession + 请求前 URL 校验 + challenge/重定向兜底，
// 全程只在白名单 host 上强制 HTTPS）。

import Foundation

// MARK: - 注入点协议

/// 清单拉取（协议，便于测试注入 stub）。
public protocol ManifestFetching {
    func fetchManifest(from url: URL) async throws -> Data
}

/// 产物下载（协议，便于测试注入 stub）。
public protocol DataDownloading {
    /// 下载到本地文件，`progress` 回调 0...1 进度（主队列调用）。
    func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL
}

// MARK: - 显式错误

/// HTTP 非 2xx 响应。
public struct OTAHTTPError: Error, UpdaterCodedError {
    public let statusCode: Int

    public var code: UpdaterErrorCode { .httpStatus }
    public var parameters: [String: String] { ["status": String(statusCode)] }

    public init(statusCode: Int) { self.statusCode = statusCode }
}

/// 下载产物落盘失败（临时文件移动失败）。
public struct OTADownloadMoveError: Error, UpdaterCodedError {
    public let detail: String

    public var code: UpdaterErrorCode { .downloadSaveFailed }
    public var parameters: [String: String] { ["detail": detail] }

    public init(detail: String) { self.detail = detail }
}

// MARK: - 生产网络层

/// URLSession 实现：请求前 `UpdateEndpointPolicy.validate`（https + host 白名单），
/// 每个操作独立 session（OTA 低频手动触发，隔离状态最简）。
///
/// 缓存纪律：OTA 内容（manifest + 产物）必须永远 fresh，绝不能接受缓存响应
/// （旧构建 manifest 会让 CDHash 误报不符）——配置上无条件禁用缓存
///（urlCache=nil + reloadIgnoringLocalCacheData），即使调用方显式传带缓存的
/// 配置也被强制覆盖。
public final class OTANetworkSession: ManifestFetching, DataDownloading {
    /// 建 session 用的配置，fetch（manifest）/download（产物）两路径共用。
    let configuration: URLSessionConfiguration
    private let policy: UpdateEndpointPolicy

    public init(policy: UpdateEndpointPolicy, configuration: URLSessionConfiguration = .default) {
        self.policy = policy
        if let config = configuration.copy() as? URLSessionConfiguration {
            config.timeoutIntervalForRequest = 30
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.configuration = config
        } else {
            self.configuration = configuration
        }
    }

    public func fetchManifest(from url: URL) async throws -> Data {
        try policy.validate(url)
        let delegate = ManifestFetchTaskDelegate(policy: policy)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        return try await withCheckedThrowingContinuation { continuation in
            delegate.start(task: task, continuation: continuation)
        }
    }

    public func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        try policy.validate(url)
        let delegate = DownloadTaskDelegate(policy: policy, progress: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: url)
        return try await withCheckedThrowingContinuation { continuation in
            delegate.start(task: task, continuation: continuation)
        }
    }
}

// MARK: - 白名单兜底（challenge + 重定向，URLSessionDelegate/TaskDelegate 共用）

/// 清单拉取的 session delegate：host 白名单 challenge 兜底 + 拒绝向非白名单
/// host 重定向 + 数据收集 + 一次性 continuation 恢复。
private final class ManifestFetchTaskDelegate: NSObject,
    URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate
{
    private let policy: UpdateEndpointPolicy
    private var continuation: CheckedContinuation<Data, Error>?
    private var collected = Data()

    init(policy: UpdateEndpointPolicy) {
        self.policy = policy
    }

    func start(task: URLSessionDataTask, continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
        task.resume()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard policy.isAllowedHost(challenge.protectionSpace.host) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let redirect = newRequest.url, policy.isAllowedURL(redirect) else {
            completionHandler(nil) // 拒绝向非白名单 host 重定向
            return
        }
        completionHandler(newRequest)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        collected.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil }
        if let error {
            continuation?.resume(throwing: error)
        } else if let response = task.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            continuation?.resume(throwing: OTAHTTPError(statusCode: response.statusCode))
        } else {
            continuation?.resume(returning: collected)
        }
    }
}

/// 产物下载的 session delegate：白名单兜底 + 进度 + 落盘 + 一次性 continuation 恢复。
private final class DownloadTaskDelegate: NSObject,
    URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate
{
    private let policy: UpdateEndpointPolicy
    private var continuation: CheckedContinuation<URL, Error>?
    private let progress: (Double) -> Void
    private var savedURL: URL?

    init(policy: UpdateEndpointPolicy, progress: @escaping (Double) -> Void) {
        self.policy = policy
        self.progress = progress
    }

    func start(task: URLSessionDownloadTask, continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
        task.resume()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard policy.isAllowedHost(challenge.protectionSpace.host) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let redirect = newRequest.url, policy.isAllowedURL(redirect) else {
            completionHandler(nil)
            return
        }
        completionHandler(newRequest)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        progress(p)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // 回调返回后 location 可能被系统删除 → 立即移到稳定临时位置。
        do {
            let fm = FileManager.default
            let dest = fm.temporaryDirectory
                .appendingPathComponent("kairo-ota-download-\(UUID().uuidString).zip")
            try fm.moveItem(at: location, to: dest)
            savedURL = dest
        } catch {
            savedURL = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil }
        if let error {
            continuation?.resume(throwing: error)
        } else if let url = savedURL {
            continuation?.resume(returning: url)
        } else {
            continuation?.resume(throwing: OTADownloadMoveError(detail: "临时文件移动失败"))
        }
    }
}
