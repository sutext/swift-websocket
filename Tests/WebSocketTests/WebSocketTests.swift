import XCTest
@testable import WebSocket
class Client{
    static let shared = Client()
    let socket:WebSocket = .init("ws://127.0.0.1:8088")
    init(){
        self.socket.delegate = self
        self.socket.retrier = WebSocket.Retrier{code,reason in
            code.rawValue > 4000
        }//usubg default retrier
        self.socket.pinging = WebSocket.Pinging(socket) // using default ping pong
//        self.socket.pinging = CustomPinging(socket) // using your custom pinging
        self.socket.using(monitor: true)// using network monitor
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
        case .opening:
            self.socket.pinging?.suspend()
        case .closed:
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
        sleep(2)
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        // XCTAssertEqual(swift_websocket().text, "Hello, World!")
    }
}
