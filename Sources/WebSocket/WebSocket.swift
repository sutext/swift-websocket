//
//  WebSocket.swift
//
//
//  Created by supertext on 2023/3/22.
//

import Foundation
import Network

// MARK: - Protocol definitions
/// WebSocket callback delegate
public protocol WebSocketDelegate:AnyObject{
    /// Every status change callback
    func socket(_ socket:WebSocket, didUpdate  status:WebSocket.Status,old:WebSocket.Status)
    /// Every error callback.
    /// Most of the errors have already been handled. So you do not care this
    func socket(_ socket:WebSocket, didReceive error:Error)
    /// Any message callback
    func socket(_ socket:WebSocket, didReceive message:WebSocket.Message)
    /// Custom TLS handshake `@see URLSession URLAuthenticationChallenge API`
    func socket(_ socket:WebSocket, didReceive challenge:WebSocket.Challenge)->WSChallengeResult
}

/// Add default implementation of WebSocketDelegate
public extension WebSocketDelegate{
    func socket(_ socket:WebSocket, didUpdate status:WebSocket.Status) {}
    func socket(_ socket:WebSocket, didReceive error:Error){}
    func socket(_ socket:WebSocket, didReceive challenge:WebSocket.Challenge)->WSChallengeResult{
        .useDefault
    }
}

/// WebSocket ping pong protocol @see `WebSocket.Pinging` for implementation
///
///- Important All function will be call in `socket.queue`. It's best not to call directly
public protocol WebSocketPinging{
    init(_ socket:WebSocket)
    func onRecive(message:WebSocket.Message)
    func resume()
    func suspend()
}

// MARK: - Public definition
/// A WebSocket implementation on iOS13 base on URLSessionWebSocketTask
/// Add auto ping pong and retry implementation
public final class WebSocket{
    /// Internal runing  queue
    let rootQueue:DispatchQueue
    /// internal session implementation
    private let session:Session
    /// Internal monitor implementation
    private var monitor:Monitor?
    
    /// the delegate callback queue.
    public var queue:DispatchQueue = .main
    /// current websocket statuss
    public var status:Status { session.status }
    /// is connection available
    public var isConnected:Bool { status == .opened }
    /// current websocket request
    public var request:URLRequest { session.request }
    /// config the retry policy by default never retry
    public var retrier:Retrier? = nil
    /// ping pong mechanism protocol. You can use` WebSocket.Pinging` by default.
    public var pinging:WebSocketPinging? = nil
    /// websocket call back delegate
    /// - Important  All delegate method will callback in  delegate queue
    public weak var delegate:WebSocketDelegate?
    
    /// convenience init with string
    public convenience init(_ url:String,timeout:TimeInterval = 6){
        self.init(URLRequest(url: URL(string: url)!, timeoutInterval: timeout))
    }
    /// convenience init with url
    public convenience init(_ url:URL,timeout:TimeInterval = 6){
        self.init(URLRequest(url: url, timeoutInterval: timeout))
    }
    /// init with URLRequest
    public init(_ request:URLRequest){
        self.session = .init(request)
        self.rootQueue = .init(label: "swift.websocket.\(UUID().uuidString)",attributes: .concurrent)
        self.session.socket = self
    }
    /// update the internal session and configuration
    public func update(config:(URLSession)->Void){
        config(session.impl)
    }
    /// Open the websocket connecction
    public func open(){
        session.open()
    }
    /// start network mornitor or not
    /// - Parameters:
    ///    - monitor: use monitor or not. `false` by default
    public func using(monitor:Bool){
        if monitor{
            self.monitor = self.monitor ?? Monitor(self)
            self.monitor?.start()
        }else{
            self.monitor?.stop()
            self.monitor = nil
        }
    }
    /// Close the websocket
    ///
    /// - Parameters:
    ///    - reason: the close reason.
    public func close(_ reason:CloseReason? = nil){
        session.close(.normalClosure,reason: reason)
    }
    /// send string message
    public func send(message:String,finish:((Swift.Error?)->Void)? = nil){
        send(message: .string(message),finish: finish)
    }
    /// Send binary data
    public func send(data:Data,finish:((Swift.Error?)->Void)? = nil){
        send(message: .data(data),finish: finish)
    }
    /// Send message to the server
    public func send(message:Message,finish:((Swift.Error?)->Void)? = nil){
        guard case .opened = session.status else{
            finish?(Error.notOpened)
            return
        }
        session.task?.send(message, completionHandler: { err in
            finish?(err)
        })
    }
    /// Send ping frame to server
    /// - Parameters:
    ///    - onPong: callback when recived pong frame
    public func send(ping onPong:@escaping (Swift.Error?)->Void){
        guard case .opened = session.status else{
            onPong(Error.notOpened)
            return
        }
        session.task?.sendPing(pongReceiveHandler: onPong)
    }
    func notify(status:Status,old:Status){
        self.queue.async {
            self.delegate?.socket(self, didUpdate: status,old: old)
        }
    }
    func notify(message:Message){
        self.queue.async {
            self.delegate?.socket(self, didReceive: message)
        }
    }
    func notify(error:Swift.Error){
        self.queue.async {
            self.delegate?.socket(self, didReceive: error)
        }
    }
    func challenge(_ challenge:Challenge,completion:((WSChallengeResult)->Void)?){
        self.queue.async {
            if let result = self.delegate?.socket(self, didReceive: challenge){
                completion?(result)
            }
        }
    }
}
public enum WSChallengeResult{
    /* The entire request will be canceled */
    case cancel
    /* This challenge is rejected and the next authentication protection space should be tried */
    case reject
    /* Default handling for the challenge - as if this delegate were not implemented; */
    case useDefault
    /* Use the specified credential */
    case useCredential(URLCredential)
}

// MARK: - Type definitions
extension WebSocket{
    public typealias Message = URLSessionWebSocketTask.Message
    public typealias Challenge = URLAuthenticationChallenge
    public enum CloseCode:RawRepresentable,Codable,Equatable,Hashable{
        case invalid //0
        case normalClosure//1000
        case goingAway//1001
        case protocolError//1002
        case unsupportedData//1003
        case noStatusReceived//1005
        case abnormalClosure//1006
        case invalidFramePayloadData//1007
        case policyViolation//1008
        case messageTooBig//1009
        case mandatoryExtensionMissing//1010
        case internalServerError//1011
        case tlsHandshakeFailure//1015
        case custom(Int)//Follow ws protocol this custom code need greater than 4000
        public var rawValue: Int{
            switch self{
            case .invalid: return 0
            case .normalClosure: return 1000
            case .goingAway: return 1001
            case .protocolError: return 1002
            case .unsupportedData: return 1003
            case .noStatusReceived: return 1005
            case .abnormalClosure: return 1006
            case .invalidFramePayloadData: return 1007
            case .policyViolation: return 1008
            case .messageTooBig: return 1009
            case .mandatoryExtensionMissing: return 1010
            case .internalServerError: return 1011
            case .tlsHandshakeFailure: return 1015
            case .custom(let value): return value
            }
        }
        public init(rawValue: Int) {
            switch rawValue{
            case 0:
                self = .invalid
            case 1000:
                self = .normalClosure
            case 1001:
                self = .goingAway
            case 1002:
                self = .protocolError
            case 1003:
                self = .unsupportedData
            case 1005:
                self = .noStatusReceived
            case 1006:
                self = .abnormalClosure
            case 1007:
                self = .invalidFramePayloadData
            case 1008:
                self = .policyViolation
            case 1009:
                self = .messageTooBig
            case 1010:
                self = .mandatoryExtensionMissing
            case 1011:
                self = .internalServerError
            case 1015:
                self = .tlsHandshakeFailure
            default:
                self = .custom(rawValue)
            }
        }
        fileprivate var wscode:URLSessionWebSocketTask.CloseCode{
            .init(rawValue: rawValue) ?? .invalid
        }
    }
    public enum Error:Swift.Error{
        case notOpened
    }
    /// state machine
    public enum Status:Equatable,CustomStringConvertible{
        case opened
        case closed(CloseCode,CloseReason?)
        case opening
        public var description: String{
            switch self{
            case .opening: return "opening"
            case .opened: return "opened"
            case let .closed(code, reason):
                if let reason{
                    return "closed(\(code.rawValue),\(reason))"
                }
                return "closed(\(code.rawValue),nil)"
            }
        }
    }
    /// WehSocket close reason
    public enum CloseReason:Codable,Equatable,CustomStringConvertible{
        /// close when ping pong fail
        case pinging
        /// auto close by network monitor when network unsatisfied
        case monitor
        /// close when network layer error. `String is error message`
        case error(String)
        /// close when server reason `Data is server close reason data`
        case server(Data?)
        /// create from error
        public init(error:Swift.Error){
            let err  = error as NSError
            self = .error("\(err.domain)(\(err.code)")
        }
        /// create from sseion delegate reason data
        /// only internal available
        init(data:Data?){
            guard let data else{
                self = .server(nil)
                return
            }
            guard let reason = try? JSONDecoder().decode(CloseReason.self, from: data) else{
                self = .server(data)
                return
            }
            self = reason
        }
        /// to reason data
        /// only internal available
        var data:Data?{
            try? JSONEncoder().encode(self)
        }
        public var description: String{
            switch self{
            case .monitor: return "monitor"
            case .pinging: return "pinging"
            case .server(let data): return "server(\(data==nil ? "nil" : "\(data!.count)bytes"))"
            case .error(let str): return "error(\(str))"
            }
        }
    }
}

// MARK: - Core implementation
extension WebSocket{
    /// internal implementation
    class Session:NSObject{
        let request: URLRequest
        weak var socket: WebSocket!
        private let lock:NSLock = NSLock()
        private var retryTimes: UInt8 = 0
        private var retrying: Bool = false
        private(set) var task:URLSessionWebSocketTask?
        init(_ request:URLRequest) {
            self.request = request
        }
        private(set) var status:Status = .closed(.normalClosure,nil){
            didSet{
                if oldValue != status {
                    switch status{
                    case .opened:
                        self.receve()
                        self.retryTimes = 0
                        self.socket.pinging?.resume()
                    case .closed:
                        self.retryTimes = 0
                        self.task = nil
                        self.socket.pinging?.suspend()
                    case .opening:
                        self.socket.pinging?.suspend()
                        break
                    }
                    self.socket.notify(status: status, old: oldValue)
                }
            }
        }
        lazy var impl:URLSession = {
            let config = URLSessionConfiguration.default
            config.httpShouldUsePipelining = true
            let queue = OperationQueue()
            queue.underlyingQueue = socket.rootQueue
            queue.qualityOfService = .default
            queue.maxConcurrentOperationCount = 3
            return URLSession(configuration: config,delegate: self,delegateQueue: queue)
        }()
        func open(){
            self.lock.lock(); defer { self.lock.unlock() }
            guard case .closed = status else {
                return
            }
            status = .opening
            self.task = self.impl.webSocketTask(with:self.request)
            self.task?.resume()
        }
        func close(_ code:CloseCode,reason:CloseReason?){
            self.lock.lock(); defer { self.lock.unlock() }
            if case .closed = status{
                return
            }
            self.task?.cancel(with: code.wscode, reason: nil)
            self.socket.rootQueue.async {
                self.doRetry(code: code, reason: reason)
            }
        }
        /// Internal method run in delegate queue
        private func receve(){
            guard self.task?.state  == .running else{ return }
            self.task?.receive { [weak self] (result) in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.socket.pinging?.onRecive(message: message)
                    self.socket.notify(message: message)
                    self.receve()
                case .failure(let error):
                    self.socket.notify(error: error)
                    self.task?.cancel()
                }
            }
        }
        /// Internal method run in delegate queue
        private func doRetry(code:CloseCode,reason:CloseReason?){
            self.lock.lock(); defer { self.lock.unlock() }
            if self.retrying{
                return
            }
            // not retry when network unsatisfied
            if let monitor = socket.monitor, monitor.status == .unsatisfied{
                status = .closed(code,reason)
                return
            }
            // not retry when reason is nil(user close)
            guard let reason else{
                status = .closed(code, nil)
                return
            }
            // not retry when retrier is nil
            guard let retrier = socket.retrier else{
                status = .closed(code,reason)
                return
            }
            // not retry when limits
            self.retryTimes += 1
            guard let delay = retrier.retry(when: code, reason: reason, times: self.retryTimes) else{
                status = .closed(code,reason)
                return
            }
            self.retrying = true
            self.socket.rootQueue.asyncAfter(deadline: .now() + delay){
                self.status = .opening
                self.task = self.impl.webSocketTask(with:self.request)
                self.task?.resume()
                self.retrying = false
            }
        }
    }
}
extension WebSocket.Session:URLSessionWebSocketDelegate{
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask ==  self.task else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        self.status = .opened
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask ==  self.task else { return }
        doRetry(code: .init(rawValue: closeCode.rawValue),reason: .init(data: reason))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task ==  self.task,let error else { return }
        socket.rootQueue.async {
            self.doRetry(code: .invalid,reason: .init(error: error))
        }
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        socket.challenge(challenge) { result in
            switch result {
            case .useDefault:
                completionHandler(.performDefaultHandling,nil)
            case .reject:
                completionHandler(.rejectProtectionSpace,nil)
            case .cancel:
                completionHandler(.cancelAuthenticationChallenge,nil)
            case .useCredential(let credential):
                completionHandler(.useCredential,credential)
            }
        }
    }
}

// MARK: - Retry implementation
extension WebSocket{
    public struct Retrier{
        public typealias Filter = (CloseCode,CloseReason)->Bool
        /// retry delay policy
        public let policy:Policy
        /// retry limit times
        public let limits:UInt8
        /// fillter when check  retry
        ///
        /// - Important: return true means no retry
        ///
        private let filter:Filter?
        /// create a retrier
        ///
        /// - Parameters:
        ///    - policy:Retry policcy
        ///    - limits:max retry times
        ///    - filter:filter retry when some code and reasons
        ///
        public init(_ policy:Policy = .linear(scale: 0.6),limits:UInt8 = 10,filter:Filter? = nil){
            self.limits = limits
            self.policy = policy
            self.filter = filter
        }
        public enum Policy{
            /// The retry time grows linearly
            case linear(scale:Double)
            /// The retry time does not grow. Use equal time interval
            case equals(interval:TimeInterval)
            /// The retry time grows exponentially
            case exponential(base:Int,scale:Double)
        }
        /// get retry delay. nil means not retry
        func retry(when code:CloseCode,reason:CloseReason,times:UInt8) -> TimeInterval? {
            if self.filter?(code,reason) == true {
                return nil
            }
            if times > limits {
                return nil
            }
            switch self.policy {
            case .linear(let scale):
                return scale * Double(times)
            case .equals(let time):
                return time
            case .exponential(let base, let scale):
                return pow(Double(base),Double(times))*scale
            }
        }
    }
}

// MARK: - Standard ping pong implementation
extension WebSocket{
    /// A  standard  implementation of `WebSocketPinging` protocol
    public final class Pinging:NSObject,WebSocketPinging{
        private weak var socket:WebSocket!
        private var pongRecived:Bool = false
        private var suspended = false
        /// ping timeout in secends
        public var timeout:TimeInterval = 3
        /// ping interval after last ping
        public var interval:TimeInterval = 2
        required public init(_ socket: WebSocket) {
            super.init()
            self.socket = socket
        }
        public func resume(){
            self.suspended = false
            self.start()
        }
        public func suspend(){
            self.suspended = true
        }
        public func onRecive(message:Message){
            ///  Use this method when custom ping pong
        }
        private func start(){
            if self.suspended {
                return
            }
            self.pongRecived = false
            self.socket.send(ping: { err in
                if err == nil {
                    self.pongRecived = true
                }
            })
            self.socket.rootQueue.asyncAfter(deadline: .now() + self.timeout  ){
                if !self.pongRecived{
                    self.socket.close(.pinging)
                }
                self.socket.rootQueue.asyncAfter(deadline: .now() + self.interval){
                    self.start()
                }
            }
        }
    }
}

extension WebSocket{
    class Monitor{
        private weak var socket:WebSocket!
        private let m = NWPathMonitor()
        init(_ socket:WebSocket){
            self.socket = socket
            m.pathUpdateHandler  = {[weak self] path in
                self?.status = path.status
            }
        }
        var status:NWPath.Status = .unsatisfied{
            didSet{
                if status == oldValue{
                    return
                }
                switch status{
                case .satisfied:
                    if case let .closed(_, reason) = socket.status, reason != nil{
                        socket.open()
                    }
                case .unsatisfied:
                    socket.close(.monitor)
                default:
                    break
                }
            }
        }
        func start(){
            if m.queue == nil {
                m.start(queue: socket.rootQueue)
            }
        }
        func stop(){
            m.cancel()
        }
    }
}
