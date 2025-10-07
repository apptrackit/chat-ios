import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct QRCodeView: View {
    let value: String
    var size: CGFloat = 200
    var dotRadius: CGFloat = 0.35 // Roundness factor (0.5 = circles, 0 = squares)
    var showLogo: Bool = true // Whether to show app icon in center
    var foregroundColor: UIColor = .black
    var backgroundColor: UIColor = .white
    
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let img = generateStylizedQRCode(from: value) {
                Image(uiImage: img)
                    .interpolation(.high)
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

    private func generateStylizedQRCode(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        // Use high error correction (H) so we can overlay a logo without breaking the QR code
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        
        // Get the base QR code
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        
        // Create version with rounded corners on the shapes
        let roundedQR = createRoundedShapesQRCode(from: cgImage, targetSize: size)
        
        // Add app icon in the center if enabled
        if showLogo {
            return addLogoToCenter(of: roundedQR)
        }
        
        return roundedQR
    }
    
    private func createRoundedShapesQRCode(from cgImage: CGImage, targetSize: CGFloat) -> UIImage {
        let qrWidth = cgImage.width
        let qrHeight = cgImage.height
        
        // Minimal padding for cleaner look
        let padding: CGFloat = 8
        let contentSize = targetSize - (padding * 2)
        let pixelSize = contentSize / CGFloat(qrWidth)
        let outputSize = CGSize(width: targetSize, height: targetSize)
        
        UIGraphicsBeginImageContextWithOptions(outputSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return UIImage() }
        
        // Background
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: outputSize))
        
        // Access pixel data
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let data = CFDataGetBytePtr(pixelData) else { return UIImage() }
        
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        
        // First pass: identify all black pixels and create a map
        var blackPixels = Set<String>()
        for y in 0..<qrHeight {
            for x in 0..<qrWidth {
                let pixelIndex = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = data[pixelIndex]
                if r < 128 {
                    blackPixels.insert("\(x),\(y)")
                }
            }
        }
        
        // Helper function to check if a pixel is black
        func isBlack(_ x: Int, _ y: Int) -> Bool {
            return blackPixels.contains("\(x),\(y)")
        }
        
        // Second pass: draw connected shapes with smart corner rounding
        context.setFillColor(foregroundColor.cgColor)
        
        let cornerRadius = pixelSize * 0.35 // Roundness on corners only
        
        for y in 0..<qrHeight {
            for x in 0..<qrWidth {
                if !isBlack(x, y) { continue }
                
                let rect = CGRect(
                    x: padding + (CGFloat(x) * pixelSize),
                    y: padding + (CGFloat(y) * pixelSize),
                    width: pixelSize,
                    height: pixelSize
                )
                
                // Check neighbors
                let hasTop = y > 0 && isBlack(x, y - 1)
                let hasBottom = y < qrHeight - 1 && isBlack(x, y + 1)
                let hasLeft = x > 0 && isBlack(x - 1, y)
                let hasRight = x < qrWidth - 1 && isBlack(x + 1, y)
                
                // Determine which corners should be rounded
                var corners: UIRectCorner = []
                
                // Top-left corner: round if no top AND no left neighbors
                if !hasTop && !hasLeft {
                    corners.insert(.topLeft)
                }
                // Top-right corner: round if no top AND no right neighbors
                if !hasTop && !hasRight {
                    corners.insert(.topRight)
                }
                // Bottom-left corner: round if no bottom AND no left neighbors
                if !hasBottom && !hasLeft {
                    corners.insert(.bottomLeft)
                }
                // Bottom-right corner: round if no bottom AND no right neighbors
                if !hasBottom && !hasRight {
                    corners.insert(.bottomRight)
                }
                
                // If all corners should be rounded (isolated pixel), use standard rounded rect
                if corners == [.topLeft, .topRight, .bottomLeft, .bottomRight] {
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
                    path.fill()
                } else if corners.isEmpty {
                    // No rounded corners, just fill rectangle
                    context.fill(rect)
                } else {
                    // Custom corners
                    let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: cornerRadius, height: cornerRadius))
                    path.fill()
                }
            }
        }
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    private func addLogoToCenter(of qrImage: UIImage) -> UIImage {
        let imageSize = qrImage.size
        let logoSize = imageSize.width * 0.18 // Logo takes up 18% of QR code
        let logoRect = CGRect(
            x: (imageSize.width - logoSize) / 2,
            y: (imageSize.height - logoSize) / 2,
            width: logoSize,
            height: logoSize
        )
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, qrImage.scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return qrImage }
        
        // Draw the QR code
        qrImage.draw(at: .zero)
        
        // Draw white background with subtle shadow for logo
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.15).cgColor)
        
        let backgroundRect = logoRect.insetBy(dx: -6, dy: -6)
        let backgroundPath = UIBezierPath(roundedRect: backgroundRect, cornerRadius: backgroundRect.width * 0.23)
        backgroundColor.setFill()
        backgroundPath.fill()
        context.restoreGState()
        
        // Add subtle border around logo background
        let borderPath = UIBezierPath(roundedRect: backgroundRect, cornerRadius: backgroundRect.width * 0.23)
        UIColor.black.withAlphaComponent(0.08).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
        
        // Draw app icon with rounded corners
        if let appIcon = getAppIcon() {
            context.saveGState()
            let iconPath = UIBezierPath(roundedRect: logoRect, cornerRadius: logoSize * 0.20)
            iconPath.addClip()
            appIcon.draw(in: logoRect)
            context.restoreGState()
        }
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? qrImage
    }
    
    private func getAppIcon() -> UIImage? {
        // Try to get the app icon from the bundle
        if let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        
        // Fallback: try common icon names
        let iconNames = ["AppIcon", "Icon-60@2x", "Icon-60@3x", "Icon-App-60x60"]
        for name in iconNames {
            if let icon = UIImage(named: name) {
                return icon
            }
        }
        
        // Last resort: create a simple branded icon
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        return UIImage(systemName: "lock.shield.fill", withConfiguration: config)?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Text("Default Style")
                    .font(.headline)
                QRCodeView(value: "inviso://join/123456", size: 240)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(24)
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
            }
            
            VStack(spacing: 10) {
                Text("Without Logo")
                    .font(.headline)
                QRCodeView(value: "inviso://join/123456", size: 240, showLogo: false)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(24)
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
            }
        }
        .padding()
    }
}
