import SwiftUI
import UIKit

@main
struct DualCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                CameraScreen()
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct CameraScreen: UIViewRepresentable {
    @Environment(\.scenePhase) private var scenePhase

    func makeUIView(context: Context) -> DualCameraView {
        DualCameraView(frame: .zero)
    }

    func updateUIView(_ uiView: DualCameraView, context: Context) {
        uiView.setSceneActive(scenePhase == .active)
    }
}
