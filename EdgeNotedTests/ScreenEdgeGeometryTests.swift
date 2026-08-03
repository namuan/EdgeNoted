import CoreGraphics
import Testing

@testable import EdgeNoted

@Suite("Screen edge geometry")
struct ScreenEdgeGeometryTests {
    // One screen, 1920x1080 at origin.
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("Detects the left edge")
    func leftEdge() {
        let point = CGPoint(x: 2, y: 540)
        #expect(ScreenEdgeGeometry.edge(containing: point, screens: [screen], threshold: 8) == .left)
    }

    @Test("Detects the right edge")
    func rightEdge() {
        let point = CGPoint(x: 1918, y: 540)
        #expect(ScreenEdgeGeometry.edge(containing: point, screens: [screen], threshold: 8) == .right)
    }

    @Test("Detects the bottom edge")
    func bottomEdge() {
        let point = CGPoint(x: 960, y: 3)
        #expect(ScreenEdgeGeometry.edge(containing: point, screens: [screen], threshold: 8) == .bottom)
    }

    @Test("Returns nil in the middle of the screen")
    func middle() {
        let point = CGPoint(x: 960, y: 540)
        #expect(ScreenEdgeGeometry.edge(containing: point, screens: [screen], threshold: 8) == nil)
    }

    @Test("Corners are excluded so two edges never trigger")
    func cornersExcluded() {
        let corner = CGPoint(x: 2, y: 2)
        #expect(ScreenEdgeGeometry.edge(containing: corner, screens: [screen], threshold: 8) == nil)
    }

    @Test("Multiple screens: picks the one containing the pointer")
    func secondaryDisplay() {
        let screens = [screen, CGRect(x: 1920, y: 0, width: 1440, height: 900)]
        let point = CGPoint(x: 1920 + 3, y: 450)
        #expect(ScreenEdgeGeometry.edge(containing: point, screens: screens, threshold: 8) == .left)
    }

    @Test("Visible panel frames span the usable screen height")
    func visibleFrames() {
        let size = CGSize(width: 460, height: 600)
        let usableScreen = CGRect(x: 0, y: 74, width: 1920, height: 982)

        let right = ScreenEdgeGeometry.visibleFrame(screen: usableScreen, edge: .right, panelSize: size, margin: 0)
        #expect(right.maxX == 1920)
        #expect(right.width == 460)
        #expect(right.minY == usableScreen.minY)
        #expect(right.height == usableScreen.height)

        let left = ScreenEdgeGeometry.visibleFrame(screen: usableScreen, edge: .left, panelSize: size, margin: 0)
        #expect(left.minX == 0)
        #expect(left.minY == usableScreen.minY)
        #expect(left.height == usableScreen.height)

        let bottom = ScreenEdgeGeometry.visibleFrame(screen: usableScreen, edge: .bottom, panelSize: size, margin: 0)
        #expect(bottom.minY == usableScreen.minY)
        #expect(bottom.height == usableScreen.height)
    }

    @Test("Hidden frames move off-screen in the slide direction")
    func hiddenFrames() {
        let size = CGSize(width: 460, height: 600)
        let frame = ScreenEdgeGeometry.visibleFrame(screen: screen, edge: .right, panelSize: size, margin: 0)
        let hidden = ScreenEdgeGeometry.hiddenFrame(visible: frame, edge: .right)
        #expect(hidden.minX > screen.maxX)
    }

    @Test("Open bar frame sits at the edge")
    func barFrame() {
        let bar = ScreenEdgeGeometry.barFrame(screen: screen, edge: .right, barSize: CGSize(width: 8, height: 110))
        #expect(bar.maxX == 1920)
        #expect(bar.width == 8)
    }
}
