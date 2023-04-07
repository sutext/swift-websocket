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
    /// - Important: This method will becall in `innerQueue`
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
public protocol WebSocketPinging{
    func resume()
    func suspend()
    func onRecive(message:WebSocket.Message)
}

// MARK: - Public definition
/// A WebSocket implementation on iOS13 base on URLSessionWebSocketTask
/// Add auto ping pong and retry implementation
public final class WebSocket{
    /// Internal process  queue
    let innerQueue:DispatchQueue
    private let params:Params
    /// internal session implementation
    private let session:Session
    /// Internal monitor implementation
    private var monitor:Monitor?
    /// current websocket url when init with url
    public var url:URL? { params.url }
    /// the delegate callback queue.
    public var queue:DispatchQueue = .main
    /// current websocket statuss
    public var status:Status { session.status }
    /// current websocket request when init with request
    public var request:URLRequest? { params.req }
    /// config the retry policy by default never retry
    public var retrier:Retrier? = nil
    /// ping pong mechanism protocol. You can use` WebSocket.Pinging` by default.
    public var pinging:WebSocketPinging? = nil
    /// sub protocols witch will be add to `Sec-WebSocket-Protocol`, ` take effect when init with url`
    public var protocols:[SecProtocol] = []
    /// websocket call back delegate
    /// - Important  All delegate method will callback in  delegate queue
    public weak var delegate:WebSocketDelegate?
    /// is connection available
    public var isConnected:Bool {
        if case .opened = session.status{
            return true
        }
        return false
    }
    /// convenience init with string
    public convenience init(_ url:String){
        self.init(URL(string: url)!)
    }
    /// init with URL
    public init(_ url:URL){
        self.session = Session()
        self.params = .url(url)
        self.innerQueue = .init(label: "swift.websocket.\(UUID().uuidString)",attributes: .concurrent)
        self.session.socket = self
    }
    /// init with URLRequest
    public init(_ request:URLRequest){
        self.session = Session()
        self.params = .req(request)
        self.innerQueue = .init(label: "swift.websocket.\(UUID().uuidString)",attributes: .concurrent)
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
            if self.monitor == nil{
                self.monitor = Monitor(self)
            }
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
    public func close(_ code:CloseCode = .normalClosure,reason:CloseReason? = nil){
        session.close(code,reason: reason)
    }
    /// send string message
    public func send(message:String,finish:((Error?)->Void)? = nil){
        send(message: .string(message),finish: finish)
    }
    /// Send binary data
    public func send(data:Data,finish:((Error?)->Void)? = nil){
        send(message: .data(data),finish: finish)
    }
    /// Send message to the server
    public func send(message:Message,finish:((Error?)->Void)? = nil){
        guard case .opened = session.status else{
            finish?(NSError.WebScoketNotOpened)
            return
        }
        session.task?.send(message, completionHandler: { err in
            finish?(err)
        })
    }
    /// Send ping frame to server
    /// - Parameters:
    ///    - onPong: callback when recived pong frame
    public func send(ping onPong:@escaping (Error?)->Void){
        guard case .opened = session.status else{
            onPong(NSError.WebScoketNotOpened)
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
    func notify(error:Error){
        self.queue.async {
            self.delegate?.socket(self, didReceive: error)
        }
    }
    func challenge(_ challenge:Challenge,completion:((WSChallengeResult)->Void)?){
        if let result = self.delegate?.socket(self, didReceive: challenge){
            completion?(result)
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
public extension NSError{
    static let WebScoketNotOpened:NSError = .init(domain:"WebScoketNotOpened" , code: 0)
}
// MARK: - Type definitions
extension WebSocket{
    public typealias Message = URLSessionWebSocketTask.Message
    public typealias Challenge = URLAuthenticationChallenge
    public typealias SecProtocol = String // Sec-WebScocket-Protocol
    public enum CloseCode:RawRepresentable,Codable,Equatable,Hashable{
        /// this code will never been send to server. Use for custom `reason` logic like `pinging` `monitor`  `error(code,domain)`
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
    /// state machine
    public enum Status:Equatable,CustomStringConvertible{
        case opened(SecProtocol?)
        case opening
        case closed(CloseCode,CloseReason?)
        case closing
        public var description: String{
            switch self{
            case .opening: return "opening"
            case .closing: return "closing"
            case .opened(let proto):
                if let proto{
                    return "opened(\(proto))"
                }
                return "opened"
            case let .closed(code, reason):
                if let reason{
                    return "closed(\(code.rawValue),\(reason))"
                }
                return "closed(\(code.rawValue),nil)"
            }
        }
    }
    /// WehSocket close reason
    public enum CloseReason:Equatable,CustomStringConvertible{
        /// close when ping pong fail
        case pinging
        /// auto close by network monitor when network unsatisfied
        case monitor
        /// close when network layer error.
        case error(code:Int,domain:String)
        /// reason data` from server` or send `to server`
        case server(Data)
        /// create with optional server data
        public init?(server data:Data?){
            if let data{
                self = .server(data)
            }
            return nil
        }
        /// create from error
        public init(error:Error){
            let err  = error as NSError
            self = .error(code: err.code,domain: err.domain)
        }
        /// to reason data
        /// only internal available
        public var data:Data?{
            if case .server(let data) = self {
                return data
            }
            return nil
        }
        public var description: String{
            switch self{
            case .monitor: return "monitor"
            case .pinging: return "pinging"
            case .error(let code,let domain): return "error(code:\(code),domain:\(domain))"
            case .server(let data): return "server(\(data.count)bytes)"
            }
        }
    }
}

// MARK: - Core implementation
extension WebSocket{
    /// internal implementation
    class Session:NSObject{
        weak var socket: WebSocket!
        private let lock:NSLock = NSLock()
        private var retryTimes: UInt8 = 0
        private var retrying: Bool = false
        private(set) var task:URLSessionWebSocketTask?
        private(set) var status:Status = .closed(.normalClosure,nil){
            didSet{
                if oldValue != status {
                    switch status{
                    case .opened:
                        self.recive()
                        self.retryTimes = 0
                    case .closed:
                        self.retryTimes = 0
                        self.task = nil
                    case .opening:
                        self.task = nil
                    case .closing:
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
            queue.underlyingQueue = socket.innerQueue
            queue.qualityOfService = .default
            queue.maxConcurrentOperationCount = 3
            return URLSession(configuration: config,delegate: self,delegateQueue: queue)
        }()
        func open(){
            self.lock.lock(); defer { self.lock.unlock() }
            switch self.status{
            case .opening,.opened:
                return
            default:
                break
            }
            self.status = .opening
            self.resumeTask()
        }
        func close(_ code:CloseCode,reason:CloseReason?){
            self.lock.lock(); defer { self.lock.unlock() }
            switch self.status{
            case .closing,.closed:
                return
            default:
                break
            }
            if case .invalid = code{
                self.doRetry(code: code, reason: reason)
                return
            }
            switch self.task?.state{
            case .completed,.canceling:
                self.doRetry(code: code, reason: reason)
            default:
                self.status = .closing
                self.task?.cancel(with: code.wscode, reason: reason?.data)
            }
        }
        private func resumeTask(){
            switch socket.params{
            case .url(let u):
                if socket.protocols.count>0{
                    self.task = self.impl.webSocketTask(with:u,protocols: socket.protocols)
                }else{
                    self.task = self.impl.webSocketTask(with:u)
                }
            case .req(let r):
                self.task = self.impl.webSocketTask(with: r)
            }
            self.task?.resume()
        }
        /// Internal method run in delegate queue
        private func recive(){
            guard let task = self.task,task.state  == .running else { return }
            task.receive { [weak self,weak task] (result) in
                guard let self,let task,self.task === task else { return } //invalid last task recive
                switch result {
                case .success(let message):
                    self.socket.pinging?.onRecive(message: message)
                    self.socket.notify(message: message)
                    self.recive()
                case .failure(let error):
                    self.socket.notify(error: error)
                }
            }
        }
        /// Internal method run in delegate queue
        private func doRetry(code:CloseCode,reason:CloseReason?){
            if self.retrying{
                return
            }
            // not retry when network unsatisfied
            if let monitor = socket.monitor, monitor.status == .unsatisfied{
                status = .closed(code,reason)
                return
            }
            // not retry when close normaly
            if case .normalClosure = code{
                status = .closed(code,reason)
                return
            }
            // not retry when reason is nil(close no reason)
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
            guard let delay = retrier.retry(when: reason, code: code, times: self.retryTimes) else{
                status = .closed(code,reason)
                return
            }
            self.retrying = true
            self.status = .opening
            self.socket.innerQueue.asyncAfter(deadline: .now() + delay){
                self.resumeTask()
                self.retrying = false
            }
        }
    }
}
extension WebSocket.Session:URLSessionWebSocketDelegate{
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask ==  self.task else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        self.status = .opened(`protocol`)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask ==  self.task else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        doRetry(code: .init(rawValue: closeCode.rawValue),reason: .init(server: reason))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task ==  self.task,let error else { return }
        socket.innerQueue.async {
            self.lock.lock(); defer { self.lock.unlock() }
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
        func retry(when reason:CloseReason,code:CloseCode,times:UInt8) -> TimeInterval? {
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
    public final class Pinging:WebSocketPinging{
        private var delay:Delay? = nil
        private weak var socket:WebSocket!
        private var pongRecived:Bool = false
        /// ping timeout in secends
        public var timeout:TimeInterval = 3
        /// ping interval after last ping
        public var interval:TimeInterval = 3
        public init(_ socket: WebSocket) {
            self.socket = socket
        }
        public func resume(){
            if self.delay == nil{
                self.sendPing()
            }
        }
        public func suspend(){
            self.delay = nil // cancel running delay tasks
        }
        public func onRecive(message:Message){
            ///  Use this method when custom ping pong
        }
        private func checkPong(){
            if !self.pongRecived{
                self.socket.close(.invalid,reason: .pinging)
            }
        }
        private func sendPing(){
            self.pongRecived = false
            self.socket.send(ping: { err in
                if err == nil {
                    self.pongRecived = true
                }
            })
            self.delay = Delay(t1: timeout, t2: interval, step1: checkPong, step2: sendPing)
        }
        private class Delay {
            private var step1:(()->Void)?
            private var step2:(()->Void)?
            init(t1:TimeInterval,t2:TimeInterval,step1:(()->Void)?,step2:(()->Void)?) {
                self.step1 = step1
                self.step2 = step2
                DispatchQueue.global().asyncAfter(deadline: .now() + t1){[weak self] in
                    guard let self else { return }
                    self.step1?()
                    DispatchQueue.global().asyncAfter(deadline: .now() + t2){[weak self] in
                        guard let self else { return }
                        self.step2?()
                    }
                }
            }
        }
    }
}

extension WebSocket{
    enum Params{
        case url(URL)
        case req(URLRequest)
        var url:URL?{
            if case .url(let u) = self {
                return u
            }
            return nil
        }
        var req:URLRequest?{
            if case .req(let r) = self {
                return r
            }
            return nil
        }
    }
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
                    socket.close(.invalid,reason: .monitor)
                default:
                    break
                }
            }
        }
        func start(){
            if m.queue == nil {
                m.start(queue: socket.innerQueue)
            }
        }
        func stop(){
            m.cancel()
        }
    }
}
