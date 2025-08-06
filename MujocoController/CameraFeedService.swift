import UIKit
import AVFoundation

protocol CameraFeedServiceDelegate: AnyObject {
    func didOutput(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation)
    func didEncounterSessionRuntimeError()
    func sessionWasInterrupted(canResumeManually: Bool)
    func sessionInterruptionEnded()
}

class CameraFeedService: NSObject {
    
    enum CameraConfigurationStatus {
        case success, failed, permissionDenied
    }
    
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraFeedService.sessionQueue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var isSessionRunning = false
    private var imageBufferSize: CGSize?
    
    weak var delegate: CameraFeedServiceDelegate?
    
    init(previewView: UIView) {
        super.init()
        
        session.sessionPreset = .high
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = previewView.bounds
        previewView.layer.addSublayer(previewLayer)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func updateVideoPreviewLayer(toFrame frame: CGRect) {
        previewLayer.frame = frame
    }

    func startLiveCameraSession(completion: @escaping (CameraConfigurationStatus) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
            sessionQueue.async {
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                completion(.success)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configureSession()
                        self.sessionQueue.async {
                            self.addObservers()
                            self.session.startRunning()
                            self.isSessionRunning = self.session.isRunning
                            completion(.success)
                        }
                    } else {
                        completion(.permissionDenied)
                    }
                }
            }
        case .denied:
            completion(.permissionDenied)
        default:
            completion(.failed)
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                self.isSessionRunning = false
            }
            self.removeObservers()
        }
    }

    func resumeInterruptedSession(completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            DispatchQueue.main.async {
                completion(self.isSessionRunning)
            }
        }
    }

    // MARK: - Session Configuration

    private func configureSession() {
        session.beginConfiguration()
        
        // Use ultra-wide back camera (0.5x)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        )

        guard let camera = discovery.devices.first else {
            print("❌ No ultra-wide back camera available.")
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                print("❌ Could not add camera input.")
                session.commitConfiguration()
                return
            }
        } catch {
            print("❌ Failed to create AVCaptureDeviceInput:", error)
            session.commitConfiguration()
            return
        }

        let bufferQueue = DispatchQueue(label: "camera.buffer.queue")
        videoOutput.setSampleBufferDelegate(self, queue: bufferQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.connection(with: .video)?.videoOrientation = .portrait
        } else {
            print("❌ Could not add video output.")
        }

        session.commitConfiguration()
    }

    // MARK: - Orientation

    @objc private func deviceOrientationChanged() {
        let orientation = UIDevice.current.orientation
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            switch orientation {
            case .portrait:
                connection.videoOrientation = .portrait
            case .landscapeLeft:
                connection.videoOrientation = .landscapeRight
            case .landscapeRight:
                connection.videoOrientation = .landscapeLeft
            default:
                break
            }
        }
    }

    // MARK: - Observers

    private func addObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func sessionRuntimeError(notification: Notification) {
        delegate?.didEncounterSessionRuntimeError()
    }

    @objc private func sessionWasInterrupted(notification: Notification) {
        delegate?.sessionWasInterrupted(canResumeManually: true)
    }

    @objc private func sessionInterruptionEnded(notification: Notification) {
        delegate?.sessionInterruptionEnded()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraFeedService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let orientation = UIImage.Orientation.up
        delegate?.didOutput(sampleBuffer: sampleBuffer, orientation: orientation)
    }
}
