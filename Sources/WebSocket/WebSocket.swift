//
//  WebSocket.swift
//
//
//  Created by supertext on 2023/3/22.
//

import Foundation
import Network

/// WebSocket event delegate
public protocol WebSocketDelegate:AnyObject{
    /// websocket did recevied error.
    /// Most of the time you don't have to care about this, because it's already taken care of internally
    func socket(_ socket:WebSocket, didReceive error:Error)
    /// websocket did recevied message
    func socket(_ socket:WebSocket, didReceive message:WebSocket.Message)
    /// websocket status did update
    func socket(_ socket:WebSocket, didUpdate  status:WebSocket.Status,old:WebSocket.Status)
    /// Custom TLS handshake `@see URLSession URLAuthenticationChallenge API`
    /// - Important: This method will becall in `innerQueue`
    func socket(_ socket:WebSocket, didReceive challenge:WebSocket.Challenge)->WebSocket.ChallengeResult
}
/// Add empty implementation of WebSocketDelegate
public extension WebSocketDelegate{
    func socket(_ socket:WebSocket, didReceive error:Error){}
    func socket(_ socket:WebSocket, didReceive challenge:WebSocket.Challenge)->WebSocket.ChallengeResult{
        .useDefault
    }
}

/// A WebSocket implementation on iOS13 base on URLSessionWebSocketTask
/// Add ping pong , retry and network monitor  implementation
public final class WebSocket{
    let params:Params
    let session:Session
    var monitor:Monitor?
    let innerQueue:DispatchQueue
    /// create by `usingRetrier()`
    public private(set) var retrier:Retrier?
    /// create by `usingPinging()`
    public private(set) var pinging:Pinging?
    /// current websocket url when init with url
    public var url:URL? { params.url }
    /// the delegate callback queue.
    public var queue:DispatchQueue = .main
    /// current websocket statuss
    public var status:Status { session.status }
    /// current websocket request when init with request
    public var request:URLRequest? { params.req }
    /// sub protocols witch will be add to `Sec-WebSocket-Protocol`.
    /// - Important  Take effec onlyt when init with url
    /// - Important  set sub protocol values before `open`
    public var protocols:[SecProtocol] = []
    /// websocket call back delegate queue
    /// - Important  All delegate method will callback in  delegate queue
    public weak var delegate:WebSocketDelegate?
    /// is connection available
    public var isConnected:Bool {
        if case .opened = session.status{
            return true
        }
        return false
    }
    /// convenience init with string url
    public convenience init(_ url:String){
        self.init(URL(string: url)!)
    }
    /// init with URL
    /// This is the recommended initializer. You should use this initializer in most cases
    public init(_ url:URL){
        self.session = Session()
        self.params = .url(url)
        self.innerQueue = DispatchQueue(label: "swift.websocket.\(UInt.random(in: 100000...999999))",attributes: .concurrent)
        self.session.socket = self
    }
    /// init with URLRequest
    /// Consider this  initializer  for highly customizable situations
    public init(_ request:URLRequest){
        self.session = Session()
        self.params = .req(request)
        self.innerQueue = DispatchQueue(label: "swift.websocket.\(UInt.random(in: 100000...999999))",attributes: .concurrent)
        self.session.socket = self
    }
    /// Update the internal session and session configuration
    /// This method and config block is called synchronously
    ///
    ///     self.socket.update { session in
    ///         session.configuration.httpShouldUsePipelining = true
    ///         session.delegateQueue.maxConcurrentOperationCount = 5
    ///     }
    ///
    public func update(config:(URLSession)->Void){
        config(session.impl)
    }
    /// Open the websocket connecction
    public func open(){
        session.open()
    }
    /// Close the websocket
    /// Here we discard the close reason data because it is rarely used and we almost never passes data in the close frame
    ///
    /// - Parameters:
    ///    - code: The close code that will be send to server.
    ///
    public func close(_ code:CloseCode = .normalClosure){
        session.close(code,reason: nil)
    }
    /// Send message to the server
    /// You no longer need to consider the connection status before sending
    public func send(_ message:Message,finish:((Error?)->Void)? = nil){
        guard case .opened = session.status else{
            finish?(NSError(domain:"swift.webwcoket.notopened" , code: -1))
            return
        }
        session.task?.send(message, completionHandler: { err in
            finish?(err)
        })
    }
    /// Send ping frame to server
    /// You no longer need to consider the connection status before sending
    ///
    /// - Parameters:
    ///    - onPong: callback when recived pong frame
    ///
    public func sendPing(_ onPong:@escaping (Error?)->Void){
        guard case .opened = session.status else{
            onPong(NSError(domain:"swift.webwcoket.notopened" , code: -1))
            return
        }
        session.task?.sendPing(pongReceiveHandler: onPong)
    }
    /// Enabling the  ping pong heartbeat mechanism
    ///
    /// - Parameters:
    ///    - policy: `Pinging.Policy` by default use `.standard`
    ///    - timeout: Ping pong timeout tolerance.
    ///    - interval: Ping pong time  interval.
    ///
    public func usingPinging(
        _ policy:Pinging.Policy  = .standard,
        timeout:TimeInterval = 5,
        interval:TimeInterval = 3)
    {
        self.pinging = Pinging(policy,session: session, timeout: timeout, interval: interval)
    }
    /// Enabling the retry mechanism
    ///
    /// - Parameters:
    ///    - policy: Retry policcy
    ///    - limits: max retry times
    ///    - filter: filter retry when some code and reason
    ///
    public func usingRetrier(
        _ policy:Retrier.Policy = .random(),
        limits:UInt = 20,
        filter:Retrier.Filter? = nil)
    {
        self.retrier = Retrier(policy, limits: limits, filter: filter)
    }
    /// Enabling the network mornitor mechanism
    ///
    /// - Parameters:
    ///    - enable: use monitor or not.
    ///
    public func usingMonitor(_ enable:Bool = true){
        guard enable else{
            monitor?.stop()
            monitor = nil
            return
        }
        let monitor = monitor ?? newMonitor()
        monitor.start(queue: innerQueue)
    }
    func newMonitor()->Monitor{
        let m = Monitor{[weak self] new in
            guard let self else { return }
            switch new{
            case .satisfied:
                if case let .closed(_, reason) = self.status, reason != nil{
                    self.session.open()
                }
            case .unsatisfied:
                self.session.close(.invalid,reason: .monitor)
            default:
                break
            }
        }
        self.monitor = m
        return m
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
    func challenge(_ challenge:Challenge,completion:((ChallengeResult)->Void)?){
        if let result = self.delegate?.socket(self, didReceive: challenge){
            completion?(result)
        }
    }
}
extension WebSocket{
    public typealias SecProtocol = String // Sec-WebScocket-Protocol
    public typealias Message = URLSessionWebSocketTask.Message
    public typealias Challenge = URLAuthenticationChallenge
    public enum ChallengeResult{
        /* The entire request will be canceled */
        case cancel
        /* This challenge is rejected and the next authentication protection space should be tried */
        case reject
        /* Default handling for the challenge - as if this delegate were not implemented; */
        case useDefault
        /* Use the specified credential */
        case useCredential(URLCredential)
    }
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
    final class Monitor{
        private let impl:NWPathMonitor
        private var onChange:((NWPath.Status)->Void)?
        init(_ onChange:((NWPath.Status)->Void)?){
            self.impl = NWPathMonitor()
            self.onChange = onChange
            self.impl.pathUpdateHandler = {[weak self] newPath in
                guard let self else { return }
                self.status = newPath.status
            }
        }
        var status:NWPath.Status = .unsatisfied{
            didSet{
                if status == oldValue{ return }
                self.onChange?(status)
            }
        }
        func start(queue:DispatchQueue){
            if impl.queue == nil{
                impl.start(queue: queue)
            }
        }
        func stop(){
            impl.cancel()
        }
    }
}
