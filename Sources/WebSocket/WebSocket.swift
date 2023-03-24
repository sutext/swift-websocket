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
    func socket(_ socket:WebSocket, didUpdate  status:WebSocket.Status)
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
    private let session:Session
    /// Internal monitor implementation
    private var monitor:Monitor?
    /// Internal delegate queue
    public let queue:DispatchQueue
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
    /// - Important  All delegate method will callback in private delegate queue
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
        self.queue = .init(label: "com.airmey.websocket.\(UUID().uuidString)",attributes: .concurrent)
        self.session.socket = self
    }
    /// update the internal session configuration
    public func update(config:(URLSessionConfiguration)->Void){
        config(session.impl.configuration)
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
    public func close(_ reason:CloseReason = .manual){
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
    public typealias CloseCode = URLSessionWebSocketTask.CloseCode
    public typealias Challenge = URLAuthenticationChallenge
    
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
        /// close manual by user
        case manual
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
            case .manual: return "manual"
            case .monitor: return "monitor"
            case .pinging: return "pinging"
            case .server: return "server"
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
        private var retryTimes: UInt8 = 0
        private var retrying: Bool = false
        private(set) var task:URLSessionWebSocketTask?
        @Atomic
        private(set) var status:Status = .closed(.normalClosure,nil){
            didSet{
                if oldValue !=  status {
                    switch self.status{
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
                    socket.delegate?.socket(socket, didUpdate: status)
                }
            }
        }
        init(_ request:URLRequest) {
            self.request = request
        }
        lazy var impl:URLSession = {
            let config = URLSessionConfiguration.default
            config.httpShouldUsePipelining = true
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 3
            queue.underlyingQueue = socket.queue
            queue.qualityOfService = .default
            return URLSession(configuration: config,delegate: self,delegateQueue: queue)
        }()
        func open(){
            guard case .closed = status else {
                return
            }
            self.status = .opening
            self.task = self.impl.webSocketTask(with:self.request)
            self.task?.resume()
        }
        func close(_ code:CloseCode,reason:CloseReason){
            if case .closed = status{
                return
            }
            self.task?.cancel(with: code, reason: nil)
            socket.queue.async {
                self.doRetry(code: code, reason: reason)
            }
        }
        /// Internal method run in delegate queue
        private func receve(){
            task?.receive { [weak self] (result) in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.socket.pinging?.onRecive(message: message)
                    self.socket.delegate?.socket(self.socket, didReceive: message)
                    self.receve()
                case .failure(let error):
                    self.socket.delegate?.socket(self.socket, didReceive: error)
                    self.doRetry(code:.abnormalClosure, reason: .init(error: error))
                }
            }
        }
        /// Internal method run in delegate queue
        private func doRetry(code:CloseCode,reason:CloseReason){
            // reject retry concurrency
            if self.retrying{
                return
            }
            // not retry when network unsatisfied
            if let monitor = socket.monitor,
               monitor.status == .unsatisfied{
                self.status = .closed(code,reason)
                return
            }
            // not retry when user close
            if case .manual = reason{
                self.status = .closed(code,reason)
                return
            }
            // not retry when retrier is nil
            guard let retrier = socket.retrier else{
                self.status = .closed(code,reason)
                return
            }
            // not retry when limits
            self.retryTimes += 1
            guard let delay = retrier.delay(at: self.retryTimes) else{
                self.status = .closed(code,reason)
                return
            }
            self.retrying = true
            self.socket.queue.asyncAfter(deadline: .now() + delay){
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
        self.status = .opened
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask ==  self.task else { return }
        self.doRetry(code: closeCode,reason: .init(data: reason))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task ==  self.task,let error else { return }
        self.socket.delegate?.socket(self.socket, didReceive: error)
        self.doRetry(code: .abnormalClosure,reason: .init(error: error))
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard
            let result = socket.delegate?.socket(socket, didReceive: challenge) else {
            completionHandler(.performDefaultHandling,nil)
            return
        }
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

// MARK: - Retry implementation
extension WebSocket{
    public struct Retrier{
        /// retry delay policy
        public let policy:Policy
        /// retry limit times
        public let limits:UInt8
        public init(_ policy:Policy = .linear(scale: 0.6),limits:UInt8 = 10){
            self.limits = limits
            self.policy = policy
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
        func delay(at times:UInt8) -> TimeInterval? {
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
        @Atomic private var pongRecived:Bool = false
        @Atomic private var suspended = false
        /// ping timeout in secends
        @Atomic public var timeout:TimeInterval = 3
        /// ping interval after last ping
        @Atomic public var interval:TimeInterval = 2
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
            self.socket.queue.asyncAfter(deadline: .now() + self.timeout  ){
                if !self.pongRecived{
                    self.socket.close(.pinging)
                }
                self.socket.queue.asyncAfter(deadline: .now() + self.interval){
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
            self.status = m.currentPath.status
            m.pathUpdateHandler  = {path in
                self.status = path.status
            }
            self.socket = socket
        }
        var status:NWPath.Status{
            didSet{
                if status == oldValue{
                    return
                }
                switch status{
                case .satisfied:
                    if case let .closed(_, reason) = socket.status,
                       reason != .manual{
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
                m.start(queue: socket.queue)
            }
        }
        func stop(){
            m.cancel()
        }
    }
}
extension WebSocket{
    /// A thread-safe wrapper around a value.
    @propertyWrapper public final class Atomic<T> {
        private let lock: os_unfair_lock_t
        private var value: T
        deinit {
            lock.deinitialize(count: 1)
            lock.deallocate()
        }
        public init(wrappedValue: T) {
            self.value = wrappedValue
            lock = .allocate(capacity: 1)
            lock.initialize(to: os_unfair_lock())
        }
        public var wrappedValue: T {
            get { around { value } }
            set { around { value = newValue } }
        }
        private func around<T>(_ closure: () -> T) -> T {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return closure()
        }
    }
}
