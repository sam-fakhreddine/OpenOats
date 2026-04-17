import AppKit
import SwiftUI

struct IdleHomeDashboardView: View {
    @Bindable var settings: AppSettings
    @Environment(AppContainer.self) private var container

    @State private var events: [CalendarEvent] = []
    @State private var refreshTick = 0

    var body: some View {
        let accessState = currentAccessState

        VStack(alignment: .leading, spacing: 8) {
            Text("Coming up")
                .font(.system(size: 24, weight: .semibold))

            comingUpCard(accessState: accessState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .task(id: refreshTaskID(for: accessState)) {
            await refresh()
            try? await Task.sleep(for: refreshInterval(for: accessState))
            refreshTick &+= 1
        }
        .onChange(of: settings.calendarIntegrationEnabled) {
            refreshTick &+= 1
        }
    }

    @ViewBuilder
    private func comingUpCard(accessState: CalendarManager.AccessState) -> some View {
        Group {
            if !settings.calendarIntegrationEnabled {
                disabledCalendarCard
            } else {
                switch accessState {
                case .authorized:
                    if events.isEmpty {
                        emptyStateCard(
                            title: "No upcoming meetings",
                            description: "OpenOats will show your next calendar meetings here."
                        )
                    } else {
                        upcomingMeetingsCard
                    }
                case .denied:
                    deniedCalendarCard
                case .notDetermined:
                    emptyStateCard(
                        title: "Waiting for calendar access",
                        description: "OpenOats will show your upcoming meetings once Calendar access is granted."
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var disabledCalendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Calendar integration is off", systemImage: "calendar.badge.exclamationmark")
                .font(.system(size: 14, weight: .medium))
            Text("Enable Calendar integration to see the meetings OpenOats can prepare for.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var deniedCalendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Calendar access denied", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
            Text("Grant Calendar access in System Settings to see upcoming meetings here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                openCalendarPrivacySettings()
            } label: {
                Label("Open Privacy Settings", systemImage: "lock.shield")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var upcomingMeetingsCard: some View {
        let groups = UpcomingCalendarGrouping.groups(for: events)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                ComingUpDayGroupView(group: group)
                if index < groups.count - 1 {
                    Divider()
                        .padding(.top, 2)
                }
            }
        }
    }

    private func emptyStateCard(title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "calendar")
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @MainActor
    private func refresh() async {
        guard settings.calendarIntegrationEnabled, let manager = container.calendarManager else {
            events = []
            return
        }

        guard manager.accessState == .authorized else {
            events = []
            return
        }

        let now = Date()
        let currentEvent = manager.currentEvent(at: now)
        let upcomingEvents = manager.upcomingEvents(
            from: now,
            within: 7 * 24 * 60 * 60,
            limit: 6
        )

        var combined: [CalendarEvent] = []
        if let currentEvent {
            combined.append(currentEvent)
        }
        combined.append(contentsOf: upcomingEvents.filter { $0.id != currentEvent?.id })
        events = Array(combined.prefix(6))
    }

    private var currentAccessState: CalendarManager.AccessState {
        guard settings.calendarIntegrationEnabled else { return .notDetermined }
        return container.calendarManager?.accessState ?? .notDetermined
    }

    private func refreshTaskID(for accessState: CalendarManager.AccessState) -> String {
        "\(settings.calendarIntegrationEnabled)-\(accessStateTag(for: accessState))-\(refreshTick)"
    }

    private func accessStateTag(for accessState: CalendarManager.AccessState) -> String {
        switch accessState {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .notDetermined:
            return "not-determined"
        }
    }

    private func refreshInterval(for accessState: CalendarManager.AccessState) -> Duration {
        switch accessState {
        case .authorized:
            return .seconds(60)
        case .denied:
            return .seconds(300)
        case .notDetermined:
            return .seconds(1)
        }
    }

    private func openCalendarPrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}

private struct ComingUpDayGroupView: View {
    let group: UpcomingCalendarGrouping.DayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.sectionTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 34)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 15, weight: .medium))
                                .lineLimit(1)
                            Text(CalendarEventDisplay.timeRange(for: event))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

enum UpcomingCalendarGrouping {
    struct DayGroup: Identifiable, Equatable {
        let date: Date
        let events: [CalendarEvent]

        var id: Date { date }

        var dayNumber: String {
            Self.dayNumberFormatter.string(from: date)
        }

        var monthText: String {
            Self.monthFormatter.string(from: date)
        }

        var weekdayText: String {
            Self.weekdayFormatter.string(from: date)
        }

        var sectionTitle: String {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "Today"
            }
            if calendar.isDateInTomorrow(date) {
                return "Tomorrow"
            }
            return "\(weekdayText), \(dayNumber) \(monthText)"
        }

        private static let dayNumberFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "d"
            return formatter
        }()

        private static let monthFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter
        }()

        private static let weekdayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter
        }()
    }

    static func groups(
        for events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> [DayGroup] {
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }

        return grouped.keys.sorted().map { day in
            DayGroup(
                date: day,
                events: grouped[day, default: []]
                    .sorted { $0.startDate < $1.startDate }
            )
        }
    }
}
