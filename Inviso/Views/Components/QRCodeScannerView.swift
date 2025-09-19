import SwiftUI
import AVFoundation

struct QRCodeScannerView: UIViewControllerRepresentable {
    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRCodeScannerView
        var didReturn = false
        init(parent: QRCodeScannerView) { self.parent = parent }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didReturn else { return }
            if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let value = obj.stringValue,
               value.lowercased().hasPrefix("inviso://join/") {
                didReturn = true
                DispatchQueue.main.async { self.parent.onCode(value) }
            }
        }
    }

    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = { code in context.coordinator.didReturn = true; onCode(code) }
        vc.delegateBridge = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController {
        let session = AVCaptureSession()
        var preview: AVCaptureVideoPreviewLayer?
        var onCode: ((String) -> Void)?
        fileprivate var delegateBridge: AVCaptureMetadataOutputObjectsDelegate?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            setup()
        }

        private func setup() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) { session.addOutput(output) }
            output.setMetadataObjectsDelegate(delegateBridge, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            self.preview = preview
            session.startRunning()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        deinit { session.stopRunning() }
    }
}

struct QRCodeScannerContainer: View {
    @Environment(\.dismiss) private var dismiss
    var onScanned: (String) -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            QRCodeScannerView { code in
                onScanned(code)
                dismiss()
            }
            .ignoresSafeArea()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                    .padding()
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    QRCodeScannerContainer { _ in }
}
