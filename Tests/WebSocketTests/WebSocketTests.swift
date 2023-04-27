import XCTest
@testable import WebSocket

class Client{
    static let shared = Client()
    let socket:WebSocket = .init("ws://127.0.0.1:8088")
    init(){
        self.socket.delegate = self
        self.socket.usingPinging(.provider(self),timeout: 2,interval: 1)
//        self.socket.usingPinging() // using standard ping pong
        self.socket.usingMonitor()// using network monitor
        self.socket.usingRetrier{code,reason in
            code.rawValue > 4000
        }
        self.socket.queue = DispatchQueue(label: "test")
    }
    func send(_ msg:String){
        self.socket.send(.string(msg))
    }
    func connect(){
        self.socket.open()
    }
}
extension Client:PingingProvider{
    func buildPing() -> WebSocket.Message {
        .string("ping")
    }
    func checkPong(_ msg: WebSocket.Message) -> Bool {
        if case .string(let str) = msg,str == "pong"{
            return true
        }
        return false
    }
}
extension Client:WebSocketDelegate{
    func echo(){
        DispatchQueue.global().asyncAfter(deadline: .now()+3){
            self.socket.send(.string("hello"))
            self.echo()
        }
    }
    func socket(_ socket: WebSocket, didUpdate status: WebSocket.Status,old:WebSocket.Status) {
        print("didUpdateStatus from:",old,"to:",status)
        switch status{
        case .opened:
            self.socket.pinging?.resume()
            self.echo()
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
final class WebSocketTests: XCTestCase {
    func testExample() throws {
        Client.shared.connect()
        sleep(1000)
    }
    func testCloseCode(){
        for i in 1000...1016{
            print(URLSessionWebSocketTask.CloseCode(rawValue: i)?.rawValue ?? -1)
        }
    }
}
