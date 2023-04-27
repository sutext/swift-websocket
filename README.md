# swift-websocket

![Platform](https://img.shields.io/badge/platforms-iOS%2013.0%20%7C%20macOS%2010.15%20%7C%20tvOS%2013.0%20%7C%20watchOS%206.0-F28D00.svg)

swift-websocket A WebSocket Client in swift. Add ping pong, retry and network monitor implementation

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
        .package(url: "https://github.com/sutext/swift-websocket.git", from: "2.0.0"),
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
```
