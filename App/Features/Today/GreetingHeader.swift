import KhanaKit
import SwiftUI

/// The greeting at the top of Today.
///
/// Replaces the gradient bar reading "On today's card", which spent a full
/// display-size line and a divider saying nothing the screen did not already
/// say. This is content rather than chrome, so it can sit where a header used
/// to without costing the same vertical space.
struct GreetingHeader: View {
    var name: String?
    /// Injectable so the copy can be checked without freezing the clock.
    var now: Date = Date()

    private var today: PlanDate { PlanDate.today() }

    private var hour: Int {
        Calendar.current.component(.hour, from: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(firstName(name).map { "\(greeting(forHour: hour)), \($0)" }
                 ?? greeting(forHour: hour))
                .kkbFont(.displayMedium)
                .foregroundStyle(Kkb.textPrimary)
            Text("\(today.dayOfWeek.displayName), \(today.day) \(today.fullMonthName)")
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
