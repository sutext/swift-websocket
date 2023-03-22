# swift-websocket

![Platform](https://img.shields.io/badge/platforms-iOS%2013.0%20%7C%20macOS%2010.15%20%7C%20tvOS%2013.0%20%7C%20watchOS%206.0-F28D00.svg)

swift-websocket A WebSocket Client in swift. Add auto ping pong and keep alive implementation

## Requirements

- iOS 13.0+ | macOS 10.15+ | tvOS 13.0+ | watchOS 6.0+
- Xcode 14

## Integration

#### Swift Package Manager

You can use [The Swift Package Manager](https://swift.org/package-manager) to install `swift-websocket` by adding the proper description to your `Package.swift` file:

```swift
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "YOUR_PROJECT_NAME",
    dependencies: [
        .package(url: "https://github.com/sutext/swift-websocket.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "YOUR_TARGET_NAME",
            dependencies: [
                .product(name: "WebSocket", package: "swift-websocket")
            ],
        ),
    ]
)
```
Then run `swift build` whenever you get prepared.

## Usage
```swift
import WebSocket

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
```