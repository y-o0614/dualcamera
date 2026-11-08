import AVFoundation
import CoreImage
import CoreMedia
import Foundation

private struct CaptureProblem: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class DualCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private struct Frame {
        let sampleBuffer: CMSampleBuffer
        let time: Double
    }

    private struct Shot {
        let id = UUID()
        var front: [Frame] = []
        var rear: [Frame] = []
        var closestSkewMs: Double?
    }

    let frontPreview: AVCaptureVideoPreviewLayer
    let rearPreview: AVCaptureVideoPreviewLayer
    var onStatus: ((String, Bool) -> Void)?

    private let session: AVCaptureMultiCamSession
    private let frontOutput = AVCaptureVideoDataOutput()
    private let rearOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "dual-camera.capture", qos: .userInitiated)
    private let imageContext = CIContext()
    private let rgb = CGColorSpaceCreateDeviceRGB()
    private let maximumSkewMs = 50.0
    private var isConfigured = false
    private var requestedRunning = false
    private var startupCheck: UUID?
    private var receivedFront = false
    private var receivedRear = false
    private var pendingShot: Shot?

    override init() {
        let session = AVCaptureMultiCamSession()
        self.session = session
        frontPreview = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        rearPreview = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        super.init()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interrupted(_:)),
                           name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(interruptionEnded(_:)),
                           name: AVCaptureSession.interruptionEndedNotification, object: session)
        center.addObserver(self, selector: #selector(runtimeError(_:)),
                           name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setRunning(_ running: Bool) {
        queue.async {
            self.requestedRunning = running
            if running {
                self.startIfNeeded()
            } else {
                self.resetFrameState()
                if self.session.isRunning { self.session.stopRunning() }
            }
        }
    }

    func takePair() {
        queue.async {
            guard self.canCapture, self.pendingShot == nil else { return }
            let shot = Shot()
            self.pendingShot = shot
            let shotID = shot.id
            self.onStatus?("時刻が近い前後のフレームを取得しています…", false)

            self.queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let timedOut = self.pendingShot, timedOut.id == shotID else { return }
                self.pendingShot = nil
                if let skew = timedOut.closestSkewMs {
                    let difference = String(format: "%.2f", skew)
                    self.onStatus?("時刻差50 ms以内のペアを取得できませんでした。今回の最小差は \(difference) ms です。", self.canCapture)
                } else {
                    self.onStatus?(self.missingFramesMessage(front: !timedOut.front.isEmpty,
                                                             rear: !timedOut.rear.isEmpty), self.canCapture)
                }
            }
        }
    }

    private func startIfNeeded() {
        guard requestedRunning, !session.isRunning, !session.isInterrupted else { return }
        onStatus?("前後カメラを起動しています…", false)
        do {
            if !isConfigured { try configureSession() }
            session.startRunning()
            if session.isRunning {
                checkFirstFrames()
            } else {
                onStatus?("カメラを開始できませんでした。アプリを開き直してください。", false)
            }
        } catch {
            onStatus?(error.localizedDescription, false)
        }
    }

    private var canCapture: Bool {
        requestedRunning && session.isRunning && !session.isInterrupted && receivedFront && receivedRear
    }

    private func resetFrameState() {
        startupCheck = nil
        receivedFront = false
        receivedRear = false
        pendingShot = nil
    }

    private func checkFirstFrames() {
        resetFrameState()
        let check = UUID()
        startupCheck = check
        onStatus?("前後カメラの最初のフレームを待っています…", false)
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.startupCheck == check else { return }
            self.onStatus?(self.missingFramesMessage(front: self.receivedFront, rear: self.receivedRear), false)
        }
    }

    private func missingFramesMessage(front: Bool, rear: Bool) -> String {
        if !front && !rear { return "内・外カメラのフレームが届いていません。" }
        return front ? "外カメラのフレームが届いていません。" : "内カメラのフレームが届いていません。"
    }

    private func configureSession() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw CaptureProblem(message: "この端末は前後カメラの同時撮影に対応していません。対応するiPhone実機で開いてください。")
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video, position: .unspecified
        )
        guard let rear = discovery.devices.first(where: { $0.position == .back }),
              let front = discovery.devices.first(where: { device in
                  device.position == .front && discovery.supportedMultiCamDeviceSets.contains {
                      $0.contains(device) && $0.contains(rear)
                  }
              }) else {
            throw CaptureProblem(message: "同時に使用できる前後カメラの組み合わせが見つかりません。")
        }

        session.beginConfiguration()
        do {
            try connect(front, to: frontOutput, preview: frontPreview)
            try connect(rear, to: rearOutput, preview: rearPreview)
        } catch {
            removeConnections()
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()
        guard session.hardwareCost <= 1.0 else {
            session.beginConfiguration()
            removeConnections()
            session.commitConfiguration()
            throw CaptureProblem(message: "このカメラ構成は端末の同時撮影上限を超えています。")
        }

        frontOutput.setSampleBufferDelegate(self, queue: queue)
        rearOutput.setSampleBufferDelegate(self, queue: queue)
        isConfigured = true
    }

    private func removeConnections() {
        for connection in session.connections { session.removeConnection(connection) }
        for output in session.outputs { session.removeOutput(output) }
        for input in session.inputs { session.removeInput(input) }
    }

    private func connect(_ device: AVCaptureDevice, to output: AVCaptureVideoDataOutput,
                         preview: AVCaptureVideoPreviewLayer) throws {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input),
              let port = input.ports.first(where: { $0.mediaType == .video }) else {
            throw CaptureProblem(message: "カメラ入力を構成できません。")
        }
        session.addInputWithNoConnections(input)
        try configureFormat(device)

        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else {
            throw CaptureProblem(message: "カメラのフレーム出力を追加できません。")
        }
        session.addOutputWithNoConnections(output)

        let frames = AVCaptureConnection(inputPorts: [port], output: output)
        let display = AVCaptureConnection(inputPort: port, videoPreviewLayer: preview)
        for connection in [frames, display] {
            guard session.canAddConnection(connection) else {
                throw CaptureProblem(message: "カメラの出力を接続できません。")
            }
            session.addConnection(connection)
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    private func configureFormat(_ device: AVCaptureDevice) throws {
        let targetFPS = 30.0
        let candidates = device.formats.filter { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return format.isMultiCamSupported && max(size.width, size.height) <= 1280 &&
                format.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= targetFPS && $0.maxFrameRate >= targetFPS
                }
        }
        guard let format = candidates.min(by: { resolutionDistance($0) < resolutionDistance($1) }) else {
            throw CaptureProblem(message: "試作の撮影条件（1280 px以下・30 fps）に対応する形式が見つかりません。")
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        let interval = CMTime(value: 1, timescale: 30)
        device.activeVideoMinFrameDuration = interval
        device.activeVideoMaxFrameDuration = interval
    }

    private func resolutionDistance(_ format: AVCaptureDevice.Format) -> Int32 {
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return abs(max(size.width, size.height) - 640) + abs(min(size.width, size.height) - 480)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard startupCheck != nil || pendingShot != nil,
              requestedRunning, session.isRunning, !session.isInterrupted,
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        let isFront = output === frontOutput
        guard isFront || output === rearOutput else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time.isFinite else { return }

        if startupCheck != nil {
            if isFront { receivedFront = true } else { receivedRear = true }
            if receivedFront && receivedRear {
                startupCheck = nil
                onStatus?("撮影できます。画像は「ファイル」の「このiPhone内」に保存されます。", true)
            }
        }
        guard var shot = pendingShot else { return }
        let frame = Frame(sampleBuffer: sampleBuffer, time: time)
        let otherFrames = isFront ? shot.rear : shot.front
        if let other = otherFrames.min(by: { abs($0.time - time) < abs($1.time - time) }) {
            let skewMs = abs(time - other.time) * 1_000
            if skewMs <= maximumSkewMs {
                pendingShot = nil
                saveShot(front: isFront ? frame : other, rear: isFront ? other : frame, skewMs: skewMs)
                return
            }
            shot.closestSkewMs = min(shot.closestSkewMs ?? skewMs, skewMs)
        }

        // Keep only two recent buffers per camera, and only while a shot is pending.
        if isFront {
            if shot.front.count == 2 { shot.front.removeFirst() }
            shot.front.append(frame)
        } else {
            if shot.rear.count == 2 { shot.rear.removeFirst() }
            shot.rear.append(frame)
        }
        pendingShot = shot
    }

    private func saveShot(front: Frame, rear: Frame, skewMs: Double) {
        do {
            try savePair(front: front.sampleBuffer, rear: rear.sampleBuffer,
                         frontTime: front.time, rearTime: rear.time, skewMs: skewMs)
            let skew = String(format: "%.2f", skewMs)
            onStatus?("画像2枚を保存しました。前後のフレーム時刻差は \(skew) ms です。", canCapture)
        } catch {
            onStatus?("保存できませんでした。\(error.localizedDescription)", canCapture)
        }
    }

    private func savePair(front: CMSampleBuffer, rear: CMSampleBuffer,
                          frontTime: Double, rearTime: Double, skewMs: Double) throws {
        guard let frontBuffer = CMSampleBufferGetImageBuffer(front),
              let rearBuffer = CMSampleBufferGetImageBuffer(rear),
              let frontJPEG = imageContext.jpegRepresentation(of: CIImage(cvPixelBuffer: frontBuffer),
                                                              colorSpace: rgb, options: [:]),
              let rearJPEG = imageContext.jpegRepresentation(of: CIImage(cvPixelBuffer: rearBuffer),
                                                             colorSpace: rgb, options: [:]) else {
            throw CaptureProblem(message: "フレームをJPEGに変換できませんでした。")
        }

        let files = FileManager.default
        let documents = try files.url(for: .documentDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
        let captures = documents.appendingPathComponent("Captures", isDirectory: true)
        try files.createDirectory(at: captures, withIntermediateDirectories: true)

        let now = Date()
        let id = UUID().uuidString
        let staging = files.temporaryDirectory.appendingPathComponent(id, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }

        try frontJPEG.write(to: staging.appendingPathComponent("front.jpg"), options: .atomic)
        try rearJPEG.write(to: staging.appendingPathComponent("rear.jpg"), options: .atomic)
        let metadata: [String: Any] = [
            "savedAtUTC": ISO8601DateFormatter().string(from: now),
            "frontPresentationTimeSeconds": frontTime,
            "rearPresentationTimeSeconds": rearTime,
            "absolutePresentationTimeDifferenceMs": skewMs
        ]
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: staging.appendingPathComponent("capture.json"), options: .atomic)

        let epochMs = Int64(now.timeIntervalSince1970 * 1_000)
        let destination = captures.appendingPathComponent("\(epochMs)-\(id.prefix(8))", isDirectory: true)
        try files.moveItem(at: staging, to: destination)
    }

    @objc private func interrupted(_ notification: Notification) {
        queue.async {
            self.resetFrameState()
            if self.requestedRunning { self.onStatus?("カメラの利用が中断されました。", false) }
        }
    }

    @objc private func interruptionEnded(_ notification: Notification) {
        queue.async {
            guard self.requestedRunning else { return }
            if self.session.isRunning {
                self.checkFirstFrames()
            } else {
                self.startIfNeeded()
            }
        }
    }

    @objc private func runtimeError(_ notification: Notification) {
        let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
        queue.async {
            self.resetFrameState()
            guard self.requestedRunning else { return }
            self.onStatus?(message ?? "カメラでエラーが発生しました。", false)
        }
    }
}
