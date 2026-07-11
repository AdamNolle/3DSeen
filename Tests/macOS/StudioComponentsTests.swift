import XCTest
import SwiftUI
import AppKit
@testable import ThreeDSeenMac

final class StudioComponentsTests: XCTestCase {

    @MainActor
    func testMacPanesRenderAtMinimumWindowSize() throws {
        let size = NSSize(width: 1120, height: 720)
        for section in MacSection.allCases {
            let nav = MacNav()
            nav.section = section
            let host = NSHostingView(
                rootView: ContentView(nav: nav)
                    .environmentObject(ProcessingStateMachine())
                    .frame(width: size.width, height: size.height)
            )
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: host.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))

            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: size)
            image.addRepresentation(bitmap)
            XCTAssertEqual(image.size.width, 1120, accuracy: 1)
            XCTAssertEqual(image.size.height, 720, accuracy: 1)
            var sampledColors = Set<String>()
            for y in stride(from: 20, to: Int(size.height), by: 40) {
                for x in stride(from: 20, to: Int(size.width), by: 40) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    sampledColors.insert(
                        "\(Int(color.redComponent * 255))-\(Int(color.greenComponent * 255))-" +
                        "\(Int(color.blueComponent * 255))-\(Int(color.alphaComponent * 255))"
                    )
                }
            }
            XCTAssertGreaterThan(sampledColors.count, 3, "\(section.rawValue) rendered as a blank or flat image")

            let attachment = XCTAttachment(image: image)
            attachment.name = "Mac \(section.rawValue.capitalized) - 1120x720"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.orderOut(nil)
        }
    }

    func testSplitPaneLeftWidthHonorsRatioAndGap() {
        // (1000 - 20) * 0.58 = 568.4
        XCTAssertEqual(StSplitPane<EmptyView, EmptyView>.leftWidth(total: 1000, gap: 20, ratio: 0.58),
                       568.4, accuracy: 0.001)
        // ratio clamps to 0…1 and never goes negative.
        XCTAssertEqual(StSplitPane<EmptyView, EmptyView>.leftWidth(total: 500, gap: 20, ratio: 2),
                       480, accuracy: 0.001)
        XCTAssertEqual(StSplitPane<EmptyView, EmptyView>.leftWidth(total: 500, gap: 20, ratio: -1),
                       0, accuracy: 0.001)
    }

    func testFidelityChartYPositionMonotonicAndBounded() {
        let h: CGFloat = 170
        let low = StFidelityChart.yPosition(psnr: 22, height: h)
        let high = StFidelityChart.yPosition(psnr: 44, height: h)
        // Higher PSNR sits higher on screen (smaller y).
        XCTAssertLessThan(high, low)
        // Both stay inside the plot area (above the baseline at h-28).
        XCTAssertLessThan(low, h - 28 + 1)
        XCTAssertGreaterThan(high, 0)
    }

    func testFidelityChartDefaultTiers() {
        XCTAssertEqual(StFidelityChart.defaultTiers.map(\.name),
                       ["Preview", "Reduced", "Medium", "Full", "Raw"])
        XCTAssertEqual(StFidelityChart.defaultTiers.map(\.psnr), [22, 28, 33, 38, 44])
    }
}
