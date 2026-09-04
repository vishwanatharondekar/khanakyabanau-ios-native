import SwiftUI
import UIKit
import XCTest
@testable import KhanaKyaBanau

/// The meal-detail page widens iOS's left-edge-only pop gesture to the full
/// width. Two things have to hold: the widened gesture fires on a deliberate
/// rightward swipe and nothing else, and the native edge gesture — which is
/// interactive, and which this page has always had — survives being joined by it.
///
/// See `docs/superpowers/specs/2026-09-04-meal-detail-back-swipe-design.md`.
@MainActor
final class BackSwipeTests: XCTestCase {

    /// The worked examples from the spec. `DragGesture.Value` has no accessible
    /// initializer, which is why the decision takes the two sizes instead.
    func testOnlyADeliberateRightwardSwipePops() {
        let cases: [(dx: CGFloat, dy: CGFloat, predictedDx: CGFloat, pops: Bool, why: String)] = [
            (120, 10, 180, true, "deliberate horizontal swipe"),
            (40, 5, 200, true, "short fast flick"),
            (40, 5, 60, false, "small and slow — probably a stray touch"),
            (100, 80, 150, false, "diagonal; 100 < 80 × 1.6"),
            (100, -80, 150, false, "diagonal upward — the height sign must not matter"),
            (10, 300, 20, false, "a scroll"),
            (-120, 10, -180, false, "leftward; there is nothing forward to go to"),
        ]

        for testCase in cases {
            XCTAssertEqual(
                BackSwipe.shouldPop(
                    translation: CGSize(width: testCase.dx, height: testCase.dy),
                    predictedEnd: CGSize(width: testCase.predictedDx, height: testCase.dy)
                ),
                testCase.pops,
                "(\(testCase.dx), \(testCase.dy)) predicting \(testCase.predictedDx): \(testCase.why)"
            )
        }
    }

    /// A swipe has to travel before it counts, far enough that the scroll view's
    /// own pan slop is never in question.
    func testTheGestureIgnoresTravelShorterThanTheScrollViewsOwnSlop() {
        XCTAssertGreaterThanOrEqual(BackSwipe.minimumDistance, 20)
    }

    // MARK: - The native edge gesture

    /// `HomeView` hides the navigation bar for the whole stack and the detail page
    /// hides its back button; in UIKit either one disables
    /// `interactivePopGestureRecognizer`. SwiftUI keeps it, which is why this page
    /// has always had an interactive edge swipe — and why joining it with a
    /// `simultaneousGesture` rather than a `gesture` matters. This is the assertion
    /// that says a future modifier has not silently cost us the native swipe.
    func testTheNativeEdgeGestureSurvivesTheWidenedOne() {
        let host = UIHostingController(rootView: PushedDetailHarness())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        guard let nav = navigationController(in: host) else {
            return XCTFail("no UINavigationController backs the NavigationStack")
        }
        XCTAssertEqual(nav.viewControllers.count, 2, "the detail screen was not pushed")

        guard let edgePan = nav.interactivePopGestureRecognizer else {
            return XCTFail("the navigation controller has no interactive pop gesture")
        }
        XCTAssertTrue(edgePan.isEnabled, "the native edge-swipe recognizer is disabled")
        XCTAssertEqual(
            edgePan.delegate?.gestureRecognizerShouldBegin?(edgePan), true,
            "the native edge swipe would refuse to begin — something is blocking it"
        )
    }

    /// The detail page's container shape: a bar-less stack, a pushed screen with no
    /// back button, and the widened gesture over a vertical scroll view.
    private struct PushedDetailHarness: View {
        @State private var path = [1]

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    Text("today")
                        .navigationDestination(for: Int.self) { _ in
                            ScrollView {
                                VStack { Text("detail") }.frame(height: 1200)
                            }
                            .kkbBackSwipe {}
                            .navigationBarBackButtonHidden()
                        }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private func navigationController(in root: UIViewController) -> UINavigationController? {
        if let nav = root as? UINavigationController { return nav }
        for child in root.children {
            if let found = navigationController(in: child) { return found }
        }
        return nil
    }
}
