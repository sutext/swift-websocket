//
//  Session.swift
//
//
//  Created by supertext on 2023/3/22.
//

import Foundation

extension WebSocket{
    /// Internal core implementation
    final class Session:NSObject{
        weak var socket: WebSocket!
        private let lock:NSLock = NSLock()
        private var retryTimes: UInt = 0
        private var retrying: Bool = false
        private(set) var task:URLSessionWebSocketTask?
        private(set) var status:Status = .closed(.normalClosure){
            didSet{
                if oldValue != status {
                    switch status{
                    case .opened:
                        self.recive()
                        self.retryTimes = 0
                        socket.pinging?.resumeIfStandard()
                    case .closed:
                        socket.pinging?.suspendIfStandard()
                        self.retryTimes = 0
                        self.task = nil
                    case .opening:
                        socket.pinging?.suspendIfStandard()
                        self.task = nil
                    case .closing:
                        socket.pinging?.suspendIfStandard()
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
            queue.maxConcurrentOperationCount = 5
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
            switch self.task?.state{
            case .completed,.canceling:
                self.tryClose(code: code, reason: reason)
            default:
                if let scode = code.server{
                    self.status = .closing
                    self.task?.cancel(with: scode, reason: nil)
                }else{
                    self.tryClose(code: code, reason: reason)
                }
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
                    self.socket.pinging?.onMessage(message)
                    self.socket.notify(message: message)
                    self.recive()
                case .failure(let error):
                    self.socket.notify(error: error)
                }
            }
        }
        /// Internal method run in delegate queue
        /// try close when no need retry
        private func tryClose(code:CloseCode,reason:CloseReason?){
            if self.retrying{
                return
            }
            // not retry when network unsatisfied
            if let monitor = socket.monitor, monitor.status == .unsatisfied{
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
        self.status = .opened
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask ==  self.task else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        tryClose(code: .init(rawValue: closeCode.rawValue),reason: .init(server: reason))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task ==  self.task,let error else { return }
        socket.innerQueue.async {
            self.lock.lock(); defer { self.lock.unlock() }
            self.tryClose(code: .invalid,reason: .init(error: error))
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
