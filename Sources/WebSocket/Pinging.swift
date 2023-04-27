//
//  Pinging.swift
//
//
//  Created by supertext on 2023/3/22.
//

import Foundation


/// Pinging provider for custom pong mechanism
public protocol PingingProvider{
    /// create an ping message
    func buildPing()->WebSocket.Message
    /// Determine whether the message is a pong message
    func checkPong(_ msg:WebSocket.Message)->Bool
}

extension WebSocket{
    /// Implementation of ping pong mechanism
    final public class Pinging{
        public enum Policy{
            /// Use websocket protocol ping pong mechanism
            /// In this case all operations are fully automatic
            case standard
            /// Custom ping pong mechanism
            /// - Important  In this case you must provide a `PingingProvider`
            /// - Important  In this case you must call `resume()` and `suspend()` manually.
            case provider(PingingProvider)
        }
        /// current retry backoff policy
        public let policy:Policy
        /// current pinging timeout tolerance
        public let timeout:TimeInterval
        /// current pinging time interval
        public let interval:TimeInterval
        
        private let session:Session
        private var task:DelayTask? = nil
        private var pongRecived:Bool = false
        init(_ policy:Policy,session:Session,timeout:TimeInterval,interval:TimeInterval) {
            self.policy = policy
            self.session = session
            self.timeout = timeout
            self.interval = interval
        }
        /// resume the pinging task
        public func resume(){
            if self.task == nil{
                self.sendPing()
            }
        }
        /// suspend the pinging task
        public func suspend(){
            self.task = nil // cancel running task
        }
        func resumeIfStandard(){
            if case .standard = policy{
                self.resume()
            }
        }
        func suspendIfStandard(){
            if case .standard = policy{
                self.suspend()
            }
        }
        func onMessage(_ message:Message){
            if case .provider(let pro) = self.policy,pro.checkPong(message){
                self.pongRecived = true
            }
        }
        private func checkPong(){
            if !self.pongRecived{
                self.session.close(.invalid, reason: .pinging)
            }
        }
        private func sendPing(){
            self.pongRecived = false
            switch self.policy{
            case .standard:
                self.session.task?.sendPing { err in
                    if err == nil {
                        self.pongRecived = true
                    }
                }
            case .provider(let pro):
                self.session.task?.send(pro.buildPing()){_ in }
            }
            self.task = DelayTask(host: self)
        }
        private class DelayTask {
            private weak var host:Pinging? = nil
            private var item1:DispatchWorkItem? = nil
            private var item2:DispatchWorkItem? = nil
            deinit{
                self.item1?.cancel()
                self.item2?.cancel()
            }
            init(host:Pinging) {
                self.host = host
                let timeout = host.timeout
                let interval = host.interval
                self.item1 = after(timeout){[weak self] in
                    guard let self else { return }
                    self.host?.checkPong()
                    self.item2 = self.after(interval){[weak self] in
                        guard let self else { return }
                        self.host?.sendPing()
                    }
                }
            }
            private func after(_ time:TimeInterval,block:@escaping (()->Void))->DispatchWorkItem{
                let item = DispatchWorkItem(block: block)
                DispatchQueue.global().asyncAfter(deadline: .now() + time, execute: item)
                return item
            }
        }
    }
}
