import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let value: String
    var size: CGFloat = 200
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let img = generateQRCode(from: value) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .accessibilityLabel("QR code for session link")
            } else {
                Color.secondary.opacity(0.2)
                    .overlay(Image(systemName: "xmark.octagon").foregroundColor(.secondary))
                    .frame(width: size, height: size)
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        // Optional error correction level (L, M, Q, H). Higher = denser code.
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scale = size / outputImage.extent.size.width
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

#Preview {
    QRCodeView(value: "inviso://join/123456")
}
