import AVFoundation
import UIKit

final class DualCameraView: UIView {
    private let capture = DualCapture()
    private let frontPanel = UIView()
    private let rearPanel = UIView()
    private let statusLabel = UILabel()
    private let shutter = UIButton(type: .system)
    private var requestingPermission = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        buildInterface()
        capture.onStatus = { [weak self] message, canShoot in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.statusLabel.text = message
                self.shutter.isEnabled = canShoot && UIApplication.shared.applicationState == .active
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationBecameActive(_:)),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationWillResignActive(_:)),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        capture.setRunning(false)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshCamera()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capture.frontPreview.frame = frontPanel.bounds
        capture.rearPreview.frame = rearPanel.bounds
        CATransaction.commit()
    }

    @objc private func applicationBecameActive(_ notification: Notification) {
        refreshCamera()
    }

    @objc private func applicationWillResignActive(_ notification: Notification) {
        pauseCamera()
    }

    private func refreshCamera() {
        guard window != nil, UIApplication.shared.applicationState == .active else {
            pauseCamera()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            capture.setRunning(true)
        case .notDetermined:
            guard !requestingPermission else { return }
            requestingPermission = true
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
        configurePanel(frontPanel, preview: capture.frontPreview, title: "内カメラ · FRONT")
        configurePanel(rearPanel, preview: capture.rearPreview, title: "外カメラ · REAR")

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

    private func configurePanel(_ panel: UIView, preview: AVCaptureVideoPreviewLayer, title: String) {
        panel.backgroundColor = .black
        panel.layer.cornerRadius = 12
        panel.clipsToBounds = true
        preview.videoGravity = .resizeAspect
        panel.layer.addSublayer(preview)

        let label = UILabel()
        label.text = "  \(title)  "
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.layer.cornerRadius = 5
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 6),
            label.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6)
        ])
    }
}
