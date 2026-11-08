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
    func makeUIView(context: Context) -> DualCameraView {
        DualCameraView(frame: .zero)
    }

    func updateUIView(_ uiView: DualCameraView, context: Context) {}
}
