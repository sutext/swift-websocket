import XCTest
@testable import WebSocket

final class CustomPinging:NSObject,WebSocketPinging{
    private weak var socket:WebSocket!
    public var timeout:TimeInterval = 5
    public var interval:TimeInterval = 8
    @WebSocket.Atomic
    private var pongRecived:Bool = false
    @WebSocket.Atomic
    private var suspended = false;
    required public init(_ socket: WebSocket) {
        super.init()
        self.socket = socket
    }
    func resume(){
        self.suspended = false
        self.start()
    }
    func suspend(){
        self.suspended = true
    }
    func onRecive(message:WebSocket.Message){
        if case .string(let str) = message{
            if str == "pong"{
                self.pongRecived = true
            }
        }
    }
    private func start(){
        if self.suspended {
            return
        }
        self.pongRecived = false
        self.socket.send(message: "ping")
        self.socket.queue.asyncAfter(deadline: .now()+self.timeout){
            if !self.pongRecived{
                self.socket.close(.pinging)
            }
            self.start()
        }
    }
}
class Client{
    let socket:WebSocket = .init(URL(string: "wss://web.example.com")!)
    init(){
        self.socket.delegate = self
        self.socket.retrier = WebSocket.Retrier(.linear(scale: 0.5),limits: 10)//usubg default retrier
        self.socket.pinging = WebSocket.Pinging(socket) // using default ping pong
        self.socket.pinging = CustomPinging(socket) // using your custom pinging
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
    func socket(_ socket: WebSocket, didUpdate status: WebSocket.Status) {
        print("didUpdateStatus:",status)
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
        let client = Client()
        client.send("hello")
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        // XCTAssertEqual(swift_websocket().text, "Hello, World!")
    }
}
