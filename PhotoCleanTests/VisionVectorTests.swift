import XCTest
import UIKit
import Vision

final class VisionVectorTests: XCTestCase {
    private func observation(shift: CGFloat) throws -> VNFeaturePrintObservation {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIColor.black.setFill(); context.fill(CGRect(x: 12 + shift, y: 16, width: 42, height: 56))
        }
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage), options: [:]).perform([request])
        return try XCTUnwrap(request.results?.first)
    }
    private func vector(_ observation: VNFeaturePrintObservation) throws -> [Float] {
        let type: FeatureVector.Element
        switch observation.elementType {
        case .float: type = .float
        case .double: type = .double
        default: throw CocoaError(.fileReadCorruptFile)
        }
        return try XCTUnwrap(FeatureVector.read(observation.data, count: observation.elementCount, element: type))
    }
    func testRawEuclideanDistanceMatchesVisionRevisionTwo() throws {
        let a = try observation(shift: 0), b = try observation(shift: 9)
        var expected: Float = 0
        try a.computeDistance(&expected, to: b)
        let actual = try XCTUnwrap(FeatureVector.distance(vector(a), vector(b)))
        XCTAssertEqual(actual, expected, accuracy: 0.0001)
    }
}
