import Foundation
import ImageIO
import Vision

guard (2...3).contains(CommandLine.arguments.count) else { exit(64) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { exit(65) }
var images = [original]
if CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--character-list" {
    // Recognize the account count and selected name at their native pixel size.
    // Whole-window OCR downsamples these small labels at larger game resolutions.
    if let right = original.cropping(to: CGRect(x: Double(original.width) * 0.75, y: 0,
                                               width: Double(original.width) * 0.25,
                                               height: Double(original.height))) {
        images.append(right)
    }
}
for image in images {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])
    for observation in request.results ?? [] {
        if let text = observation.topCandidates(1).first?.string { print(text) }
    }
}
