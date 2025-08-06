import MediaPipeTasksVision
import AVFoundation

class HandLandmarkerService: NSObject {
    var handLandmarker: HandLandmarker?
    var runningMode: RunningMode = .liveStream

    static func liveStreamHandLandmarkerService(modelPath: String?,
                                                numHands: Int,
                                                minHandDetectionConfidence: Float,
                                                minHandPresenceConfidence: Float,
                                                minTrackingConfidence: Float,
                                                liveStreamDelegate: HandLandmarkerServiceLiveStreamDelegate?,
                                                delegate: HandLandmarkerDelegate) -> HandLandmarkerService? {
        guard let modelPath = modelPath else { return nil }
        let service = HandLandmarkerService()

        let options = HandLandmarkerOptions()
        options.runningMode = .liveStream
        options.numHands = numHands
        options.minHandDetectionConfidence = minHandDetectionConfidence
        options.minHandPresenceConfidence = minHandPresenceConfidence
        options.minTrackingConfidence = minTrackingConfidence
        options.baseOptions.modelAssetPath = modelPath
        options.baseOptions.delegate = delegate.delegate
        options.handLandmarkerLiveStreamDelegate = service

        do {
            service.handLandmarker = try HandLandmarker(options: options)
        } catch {
            print("Failed to create handLandmarker: \(error)")
            return nil
        }
        return service
    }

    func detectAsync(sampleBuffer: CMSampleBuffer,
                     orientation: UIImage.Orientation,
                     timeStamps: Int) {
        guard let image = try? MPImage(sampleBuffer: sampleBuffer, orientation: orientation) else { return }
        try? handLandmarker?.detectAsync(image: image, timestampInMilliseconds: timeStamps)
    }
}

extension HandLandmarkerService: HandLandmarkerLiveStreamDelegate {
    func handLandmarker(_ handLandmarker: HandLandmarker,
                        didFinishDetection result: HandLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        let resultBundle = ResultBundle(inferenceTime: 0,
                                        handLandmarkerResults: [result])
        // Forward to your view controller via delegate
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .init("MediaPipeHandResult"),
                                            object: resultBundle)
        }
    }
}

struct ResultBundle {
    let inferenceTime: Double
    let handLandmarkerResults: [HandLandmarkerResult?]
}
