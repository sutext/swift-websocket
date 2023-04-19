import XCTest
@testable import WebSocket
class Client{
    static let shared = Client()
    let socket:WebSocket = .init("ws://127.0.0.1:8088")
    init(){
        self.socket.delegate = self
        self.socket.retrier = WebSocket.Retrier{code,reason in //define retrier
            code.rawValue > 4000
        }
        self.socket.pinging = WebSocket.Pinging(socket) // using default ping pong
//        self.socket.pinging = CustomPinging(socket) // using your custom pinging
        self.socket.using(monitor: true)// using network monitor
        self.socket.queue = DispatchQueue(label: "test")
    }
    func send(_ msg:String){
        self.socket.send(message: msg)
    }
    func connect(){
        self.socket.open()
    }
}
extension Client:WebSocketDelegate{
    func socket(_ socket: WebSocket, didUpdate status: WebSocket.Status,old:WebSocket.Status) {
        print("didUpdateStatus from:",old,"to:",status)
        switch status{
        case .opened:
            self.socket.pinging?.resume()
            socket.send(message: "hello")
        case .opening,.closing,.closed:
            self.socket.pinging?.suspend()
        }
    }
    func socket(_ socket: WebSocket, didReceive message: WebSocket.Message) {
        switch message{
        case .string(let str):
            print("didReceiveMessage:",str)
        case .data(let data):
            print("didReceiveMessage:",String(data: data, encoding: .utf8) ?? "")
        default:
            break
        }
    }
}
extension URLSessionWebSocketTask.CloseCode{
    var isInvalid:Bool{
        if case .invalid = self{
            return true
        }
        return false
    }
}
final class WebSocketTests: XCTestCase {
    func testExample() throws {
        Client.shared.connect()
        sleep(1000)
    }
    func testCloseCode(){
        let code = WebSocket.CloseCode.init(rawValue: 1007)
        print(code.toServer as Any)
        for i in 1000...1099{
            print(URLSessionWebSocketTask.CloseCode(rawValue: i)?.rawValue ?? -1)
        }
    }
}
