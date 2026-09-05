import Foundation
import Vision

guard CommandLine.arguments.count == 2 else { exit(64) }
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1])).perform([request])
for observation in request.results ?? [] {
    if let text = observation.topCandidates(1).first?.string { print(text) }
}
