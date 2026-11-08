import AVFoundation
import UIKit

final class DualCameraView: UIView {
    private let capture = DualCapture()
    private let statusLabel = UILabel()
    private let shutter = UIButton(type: .system)
    private var sceneIsActive = false
    private var requestingPermission = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        buildInterface()
        capture.onStatus = { [weak self] message, canShoot in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.statusLabel.text = message
                self.shutter.isEnabled = canShoot && self.sceneIsActive
            }
        }
    }

    deinit {
        capture.setRunning(false)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshCamera()
    }

    func setSceneActive(_ active: Bool) {
        guard sceneIsActive != active else { return }
        sceneIsActive = active
        refreshCamera()
    }

    private func refreshCamera() {
        guard window != nil, sceneIsActive else {
            pauseCamera()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            capture.setRunning(true)
        case .notDetermined:
            guard !requestingPermission else { return }
            requestingPermission = true
            statusLabel.text = "カメラへのアクセスを許可してください。"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.requestingPermission = false
                    self?.refreshCamera()
                }
            }
        default:
            statusLabel.text = "設定アプリでこのアプリのカメラアクセスを許可してください。"
            pauseCamera()
        }
    }

    private func pauseCamera() {
        shutter.isEnabled = false
        capture.setRunning(false)
    }

    @objc private func takePair() {
        capture.takePair()
    }

    private func buildInterface() {
        let frontPanel = CameraPreviewPanel(preview: capture.frontPreview, title: "内カメラ · FRONT")
        let rearPanel = CameraPreviewPanel(preview: capture.rearPreview, title: "外カメラ · REAR")

        let previews = UIStackView(arrangedSubviews: [frontPanel, rearPanel])
        previews.axis = .horizontal
        previews.distribution = .fillEqually
        previews.spacing = 8

        let title = UILabel()
        title.text = "前後カメラ同時撮影"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .white
        title.accessibilityTraits = .header

        statusLabel.text = "カメラを準備しています…"
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .lightGray
        statusLabel.numberOfLines = 0

        var configuration = UIButton.Configuration.filled()
        configuration.title = "前後の画像を保存"
        configuration.baseBackgroundColor = .systemBlue
        shutter.configuration = configuration
        shutter.isEnabled = false
        shutter.addTarget(self, action: #selector(takePair), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, previews, shutter, statusLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            shutter.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            previews.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }
}

private final class CameraPreviewPanel: UIView {
    private let preview: AVCaptureVideoPreviewLayer

    init(preview: AVCaptureVideoPreviewLayer, title: String) {
        self.preview = preview
        super.init(frame: .zero)
        backgroundColor = .black
        layer.cornerRadius = 12
        clipsToBounds = true
        preview.videoGravity = .resizeAspect
        layer.addSublayer(preview)

        let label = UILabel()
        label.text = "  \(title)  "
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.layer.cornerRadius = 5
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
}
