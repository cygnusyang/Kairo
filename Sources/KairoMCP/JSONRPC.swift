import Foundation

/// JSON-RPC 2.0 请求。
struct JSONRPCRequest: Codable, Equatable {
    var jsonrpc: String
    var id: JSONValue?
    var method: String
    var params: JSONValue?

    /// 通知（无 id）时不产生响应。
    var isNotification: Bool { id == nil }

    init(jsonrpc: String = "2.0", id: JSONValue?, method: String, params: JSONValue? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 错误对象。
struct JSONRPCErrorObject: Codable, Equatable {
    var code: Int
    /// 细粒度稳定码（`KairoErrorCode.rawValue`）：`code` 是 JSON-RPC 的数值码，
    /// 不足以区分「解析失败 / 未知方法 / 缺 name / 未知工具」，故并列给出字符串码（F-0708）。
    var reason: String?
    var message: String
    var data: JSONValue?

    init(code: Int, reason: String? = nil, message: String, data: JSONValue? = nil) {
        self.code = code
        self.reason = reason
        self.message = message
        self.data = data
    }
}

/// JSON-RPC 2.0 响应（result 与 error 互斥）。
struct JSONRPCResponse: Codable, Equatable {
    var jsonrpc: String
    var id: JSONValue?
    var result: JSONValue?
    var error: JSONRPCErrorObject?

    static func ok(_ value: JSONValue, id: JSONValue?) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: value, error: nil)
    }

    static func failure(_ errorObject: JSONRPCErrorObject, id: JSONValue?) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: errorObject)
    }
}

/// 标准 JSON-RPC 错误码。
enum JSONRPCErrorCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}
