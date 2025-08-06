// WebSocketManager.swift

import Foundation
import Combine
import simd
import UIKit

protocol WebSocketManagerDelegate: AnyObject {
    /// Called when the connection status changes.
    func webSocketManager(_ manager: WebSocketManager, didConnect connected: Bool)
}

class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published state
    @Published var toggle: Bool = false
    @Published var button: Bool = false
    @Published var isConnected: Bool = false
    @Published var receivedImage: UIImage?

    var ipAddress: String?
    var port: String?

    weak var delegate: WebSocketManagerDelegate?

    // MARK: - Connection
    func connect(ip: String, port: String) {
        self.ipAddress = ip
        self.port = port
        guard let url = URL(string: "ws://\(ip):\(port)") else {
            print("WebSocketManager: invalid URL ws://\(ip):\(port)")
            return
        }
        print("WebSocketManager: connecting to \(url)")
        webSocketTask = URLSession(configuration: .default).webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        delegate?.webSocketManager(self, didConnect: true)
        listen()
    }

    func disconnect() {
        guard let ws = webSocketTask else {
            print("WebSocketManager: nothing to disconnect")
            return
        }
        let reason = "Client disconnect".data(using: .utf8)
        ws.cancel(with: .goingAway, reason: reason)
        isConnected = false
        delegate?.webSocketManager(self, didConnect: false)
        print("WebSocketManager: disconnected")
    }

    // MARK: - Sending
    func send(json: [String: Any]) {
        guard isConnected, let ws = webSocketTask else {
            print("WebSocketManager: send skipped, not connected")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            guard let text = String(data: data, encoding: .utf8) else { return }
            print("WebSocketManager: sending JSON: \(text)")
            let message = URLSessionWebSocketTask.Message.string(text)
            ws.send(message) { error in
                if let error = error {
                    print("WebSocketManager send error:", error)
                    DispatchQueue.main.async {
                        self.isConnected = false
                        self.delegate?.webSocketManager(self, didConnect: false)
                    }
                } else {
                    print("WebSocketManager: send succeeded")
                }
            }
        } catch {
            print("WebSocketManager serialization error:", error)
        }
    }

    // MARK: - Public API
    func sendPose(
        rotationMatrix: simd_float3x3,
        position: SIMD3<Float>,
        fingerAngles: [Float]? = nil,   // Made optional since we're focusing on landmarks
        landmarks: [[Float]]? = nil,
        worldLandmarksPositions: [[Float]]? = nil
    ) {
        let rotationArray = [
            [rotationMatrix.columns.0.x, rotationMatrix.columns.0.y, rotationMatrix.columns.0.z],
            [rotationMatrix.columns.1.x, rotationMatrix.columns.1.y, rotationMatrix.columns.1.z],
            [rotationMatrix.columns.2.x, rotationMatrix.columns.2.y, rotationMatrix.columns.2.z]
        ]
        let positionArray = [position.x, position.y, position.z]

        var payload: [String: Any] = [
            "rotation": rotationArray,
            "position": positionArray,
            "toggle": toggle,
            "button": button
        ]

        // Only include finger angles if provided
        if let angles = fingerAngles {
            payload["finger_angles"] = angles
        }

        // Include landmarks data (primary focus)
        if let lmArray = landmarks {
            payload["landmarks"] = lmArray
            print("WebSocketManager: sending \(lmArray.count) landmarks")
        } else {
            print("WebSocketManager: no landmarks provided")
        }
        
        if let wlmArray = worldLandmarksPositions {
            payload["world_landmarks"] = wlmArray
            print("WebSocketManager: sending \(wlmArray.count) world landmarks")
        }

        send(json: payload)
    }

    // MARK: - Receiving
    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("WebSocketManager received text:", text)
                case .data(let data):
                    print("WebSocketManager received data of length:", data.count)
                    if let img = UIImage(data: data) {
                        DispatchQueue.main.async { self.receivedImage = img }
                    }
                @unknown default:
                    print("WebSocketManager received unknown message")
                }
                self.listen()
            case .failure(let error):
                print("WebSocketManager receive error:", error)
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.delegate?.webSocketManager(self, didConnect: false)
                }
            }
        }
    }
}
