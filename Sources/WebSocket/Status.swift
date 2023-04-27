//
//  Status.swift
//  
//
//  Created by supertext on 2023/3/22.
//

import Foundation

extension WebSocket{
    /// state machine
    public enum Status:Equatable,CustomStringConvertible{
        case opened
        case opening
        case closing
        case closed(CloseCode,CloseReason? = nil)
        public var description: String{
            switch self{
            case .opening: return "opening"
            case .closing: return "closing"
            case .opened:  return "opened"
            case let .closed(code, reason):
                if let reason{
                    return "closed(\(code.rawValue),\(reason))"
                }
                return "closed(\(code.rawValue),nil)"
            }
        }
    }
    public enum CloseCode:RawRepresentable,Codable,Equatable,Hashable{
        /// 0  This code will never been send to server.
        /// Use for custom `reason` such as `pinging` `monitor`  `error(code,domain)`
        case invalid
        ///1000
        case normalClosure
        ///1001
        case goingAway
        ///1002
        case protocolError
        ///1003
        case unsupportedData
        ///1005
        case noStatusReceived
        ///1006
        case abnormalClosure
        ///1007
        case invalidFramePayloadData
        ///1008
        case policyViolation
        ///1009
        case messageTooBig
        ///1010
        case mandatoryExtensionMissing
        ///1011
        case internalServerError
        ///1015
        case tlsHandshakeFailure
        ///1016...1999 Reserved by websocket
        case reserved(Int)
        ///2000...2999 Reserved by websocket extension
        case extensionReserved(Int)
        ///3000...3999 Defined by a library or framework.
        ///Registration is available at IANA on a first-come, first-served basis
        case thirdFramework(Int)
        ///4000...4999 Defined by application
        case application(Int)
        ///1004 Reserved by websocket.  It's undefined and meaningless
        ///...999  5000... Any other code is  undefined.
        case undefined(Int)
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
            case .reserved(let value): return value
            case .extensionReserved(let value): return value
            case .thirdFramework(let value): return value
            case .application(let value): return value
            case .undefined(let value): return value
            }
        }
        public init(rawValue: Int) {
            switch rawValue{
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
            case 1016...1999: // Reserved by websocket protocol
                self = .reserved(rawValue)
            case 2000...2999: // Reserved by websocket extension protocol
                self = .extensionReserved(rawValue)
            case 3000...3999: // Defined by a library or framework
                self = .thirdFramework(rawValue)
            case 4000...4999: // Defined by application
                self = .application(rawValue)
            default:
                self = .invalid
            }
        }
        /// Only some verified code can be send to the server
        public var server:URLSessionWebSocketTask.CloseCode?{
            switch self.rawValue{
            case 1000...1003, 1007...1011, 3000...4999:
                return .init(rawValue: rawValue)
            default:
                return nil
            }
        }
    }
    /// WehSocket close reason
    public enum CloseReason:Equatable,CustomStringConvertible{
        /// close when ping pong fail
        case pinging
        /// auto close by network monitor when network unsatisfied
        case monitor
        /// close when network error.
        case error(code:Int,domain:String)
        /// server reason data
        case server(Data)
        /// create with optional server data
        public init?(server data:Data?){
            guard let data else{
                return nil
            }
            self = .server(data)
        }
        /// create from error
        public init(error:Error){
            let err  = error as NSError
            self = .error(code: err.code,domain: err.domain)
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
