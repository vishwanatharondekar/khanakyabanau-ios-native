import KhanaKit
import UserNotifications
import XCTest
@testable import KhanaKyaBanau

/// Serves canned responses routed by method and path, and records every request
/// that reached the network.
///
/// The recording is the point: most of what `FirstWeekSeeder` promises is about
/// calls it must *not* make. A generation costs the user an AI credit and a PUT
/// can overwrite a week they already filled, so "no request was sent" is the
/// assertion, and only a recording stub can make it.
final class RecordingURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var body = Data()
    }

    /// Both dictionaries are keyed by `"<METHOD> /<path>"`.
    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var recorded: [String] = []
    nonisolated(unsafe) static var bodies: [String: Data] = [:]

    static func reset() {
        replies = [:]
        recorded = []
        bodies = [:]
    }

    static func key(method: String, path: String) -> String { "\(method) \(path)" }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = Self.key(
            method: request.httpMethod ?? "GET", path: request.url?.path ?? ""
        )
        Self.recorded.append(key)
        if let body = Self.body(of: request) { Self.bodies[key] = body }

        // An unstubbed path answers 404 rather than crashing: a test that reaches
        // one should fail on its own assertion, not on a fatal error somewhere in
        // URLSession's delegate queue.
        let reply = Self.replies[key]
            ?? Reply(status: 404, body: Data(#"{"error":"unstubbed \#(key)"}"#.utf8))

        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` moves an outgoing body onto `httpBodyStream` before a protocol
    /// ever sees the request, so `httpBody` is nil for the PUT we most want to
    /// inspect. Draining the stream is the only way to read it.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        let capacity = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: capacity)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

/// The post-onboarding first-week generation.
///
/// Android generates the week inside `OnboardingViewModel.complete()` and saves the
/// raw AI grid over whatever the week held. These tests pin the two guards this
/// port adds on top of that, both taken from the webapp
/// (`MealPlanner.tsx:246-280`, `:480`): a week that already has meals is left
/// alone, and a week that could not be read is never generated over.
@MainActor
final class FirstWeekSeederTests: XCTestCase {

    private let week = WeekDates.format(WeekDates.currentMonday())

    private var getWeek: String { "GET /api/meals/\(week)" }
    private var putWeek: String { "PUT /api/meals/\(week)" }
    private var postPrep: String { "POST /api/meals/\(week)/prep" }
    private let postGenerate = "POST /api/ai/generate"

    override func setUp() {
        super.setUp()
        RecordingURLProtocol.reset()
    }

    override func tearDown() {
        RecordingURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func emptyWeekJSON() -> Data {
        Data(#"{"weekStartDate":"\#(week)","meals":{}}"#.utf8)
    }

    private func weekWithRajmaJSON() -> Data {
        Data(#"{"weekStartDate":"\#(week)","meals":{"monday":{"lunch":"Rajma Chawal"}}}"#.utf8)
    }

    private func savedPlanJSON() -> Data {
        Data(#"{"id":"plan-1","userId":"user-1","weekStartDate":"\#(week)","meals":{}}"#.utf8)
    }

    /// What `POST /api/ai/generate` answers: a bare planner grid, no envelope.
    private func generatedWeekJSON() -> Data {
        Data(#"{"monday":{"breakfast":"Poha","lunch":"Chole","dinner":"Khichdi"}}"#.utf8)
    }

    private func stub(_ key: String, status: Int = 200, body: Data = Data()) {
        RecordingURLProtocol.replies[key] = .init(status: status, body: body)
    }

    private func makeSeeder(
        notificationStatus: UNAuthorizationStatus = .notDetermined
    ) -> FirstWeekSeeder {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let api = APIClient(
            session: URLSession(configuration: config),
            tokenProvider: { "stub-token" }
        )
        let meals = MealRepository(api: api)
        let center = FakeNotificationCenter()
        center.status = notificationStatus
        return FirstWeekSeeder(
            ai: AiRepository(api: api),
            meals: meals,
            prepReminders: PrepReminderScheduler(
                meals: meals, settings: SettingsRepository(api: api), center: center
            )
        )
    }

    // MARK: - Seeding

    func testSeedingAnEmptyWeekSavesTheGeneratedDishes() async {
        stub(getWeek, body: emptyWeekJSON())
        stub(postGenerate, body: generatedWeekJSON())
        stub(putWeek, body: savedPlanJSON())

        let seeded = await makeSeeder().seedCurrentWeek()

        XCTAssertEqual(
            seeded, week,
            "Seeding the current week has to report the week it wrote, so onboarding knows where to send the follow-up prep call."
        )
        let saved = try? XCTUnwrap(RecordingURLProtocol.bodies[putWeek])
        let savedText = String(decoding: saved ?? Data(), as: UTF8.self)
        XCTAssertTrue(
            savedText.contains("Poha"),
            "The generated dishes must reach the PUT — the server does not save what /api/ai/generate returns. Body was: \(savedText)"
        )
    }

    /// The web client is explicit about this: a week just imported from
    /// `/meal-plans` must not be generated over, nor cost a guest an AI credit.
    func testAWeekThatAlreadyHasMealsIsNeverGenerated() async {
        stub(getWeek, body: weekWithRajmaJSON())
        stub(postGenerate, body: generatedWeekJSON())
        stub(putWeek, body: savedPlanJSON())

        let seeded = await makeSeeder().seedCurrentWeek()

        XCTAssertNil(seeded, "Nothing was written, so there is no week to report.")
        XCTAssertFalse(
            RecordingURLProtocol.recorded.contains(postGenerate),
            "A week with meals in it must not spend an AI generation."
        )
        XCTAssertFalse(
            RecordingURLProtocol.recorded.contains(putWeek),
            "Saving here would overwrite meals the user already had."
        )
    }

    /// Android skips the read entirely and PUTs the AI grid, so a network blip
    /// during onboarding can clobber an existing week. This port reads first.
    func testAWeekThatCouldNotBeReadIsNeverGenerated() async {
        stub(getWeek, status: 500, body: Data(#"{"error":"upstream"}"#.utf8))
        stub(postGenerate, body: generatedWeekJSON())
        stub(putWeek, body: savedPlanJSON())

        let seeded = await makeSeeder().seedCurrentWeek()

        XCTAssertNil(seeded)
        XCTAssertFalse(
            RecordingURLProtocol.recorded.contains(postGenerate),
            "A week we could not read might be full. Generating against it risks overwriting it."
        )
        XCTAssertFalse(RecordingURLProtocol.recorded.contains(putWeek))
    }

    func testAFailedGenerationSavesNothing() async {
        stub(getWeek, body: emptyWeekJSON())
        stub(postGenerate, status: 503, body: Data(#"{"error":"AI provider down"}"#.utf8))
        stub(putWeek, body: savedPlanJSON())

        let seeded = await makeSeeder().seedCurrentWeek()

        XCTAssertNil(
            seeded,
            "Onboarding treats a nil as \"no week was built\" and completes silently."
        )
        XCTAssertFalse(
            RecordingURLProtocol.recorded.contains(putWeek),
            "There is nothing to save, and PUTting the empty grid would be a pointless write."
        )
    }

    /// A guest who has burned their three lifetime generations re-onboarding on the
    /// same device. It must not read as an error the user has to dismiss.
    func testAGuestLimitIsSwallowedLikeAnyOtherFailure() async {
        stub(getWeek, body: emptyWeekJSON())
        stub(
            postGenerate, status: 429,
            body: Data(#"{"error":"Guest users are limited to 3 AI generations."}"#.utf8)
        )

        let seeded = await makeSeeder().seedCurrentWeek()

        XCTAssertNil(seeded)
        XCTAssertFalse(RecordingURLProtocol.recorded.contains(putWeek))
    }

    // MARK: - Prep

    func testFillingPrepAsksForTheWholeWeekAtOnce() async {
        stub(postPrep, body: Data(#"{"updated":3,"dishes":["Poha","Chole","Khichdi"]}"#.utf8))
        stub(getWeek, body: emptyWeekJSON())

        await makeSeeder().fillPrep(weekStartDate: week)

        XCTAssertTrue(
            RecordingURLProtocol.recorded.contains(postPrep),
            "Prep for a freshly seeded week is one whole-week call, not one per slot."
        )
        let body = String(decoding: RecordingURLProtocol.bodies[postPrep] ?? Data(), as: UTF8.self)
        XCTAssertFalse(
            body.contains("mealType"),
            "Naming a day or mealType would scope the call to one slot. Body was: \(body)"
        )
    }

    /// Prep is a background nicety; onboarding has already completed by the time it
    /// runs, so there is nobody to show an error to.
    func testAFailedPrepCallIsSilent() async {
        stub(postPrep, status: 500, body: Data(#"{"error":"upstream"}"#.utf8))

        await makeSeeder().fillPrep(weekStartDate: week)

        XCTAssertTrue(RecordingURLProtocol.recorded.contains(postPrep))
    }
}
