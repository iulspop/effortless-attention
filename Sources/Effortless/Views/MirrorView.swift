import SwiftUI

// MARK: - Layout Model

/// A node placed on a specific rail at a specific row in the timeline.
struct TimelineNode: Identifiable {
    let id: UUID
    let event: TransitionEvent
    let rail: Int          // which vertical rail this node sits on
    let row: Int           // vertical position (0 = first event)
    var completedByNext: Bool = false  // the next transition was a completion
    var distractions: [String] = []    // distraction texts logged during this intention
}

/// A connector between two nodes — vertical (same rail) or horizontal (cross-rail).
struct TimelineConnector: Identifiable {
    let id = UUID()
    let fromRail: Int
    let fromRow: Int
    let toRail: Int
    let toRow: Int
    let type: TransitionEvent.TransitionType
    let duration: TimeInterval  // seconds between from and to events
    let timeboxMinutes: Int?    // intended timebox of the from node's todo
    let fromTimestamp: Date     // when the from-node's intention started
}

/// Pre-processed layout derived from raw events.
struct TimelineLayout {
    let nodes: [TimelineNode]
    let connectors: [TimelineConnector]
    let railLabels: [String]   // label for each rail column
    let railCount: Int

    /// Build layout from a list of transition events.
    static func build(from events: [TransitionEvent]) -> TimelineLayout {
        guard !events.isEmpty else {
            return TimelineLayout(nodes: [], connectors: [], railLabels: [], railCount: 0)
        }

        // Assign each context to a rail. Interruptions get ephemeral rails to the right.
        var contextToRail: [UUID: Int] = [:]
        var railLabels: [String] = []
        var nextRail = 0

        func railFor(_ contextId: UUID, label: String) -> Int {
            if let r = contextToRail[contextId] { return r }
            let r = nextRail
            contextToRail[contextId] = r
            railLabels.append(label)
            nextRail += 1
            return r
        }

        var nodes: [TimelineNode] = []
        var connectors: [TimelineConnector] = []

        // Separate distractions from transition events
        let transitionEvents = events.filter { $0.type != .distraction }
        let distractionEvents = events.filter { $0.type == .distraction }

        for (row, event) in transitionEvents.enumerated() {
            let rail = railFor(event.to.contextId, label: event.to.contextLabel)
            nodes.append(TimelineNode(id: event.id, event: event, rail: rail, row: row))

            // Connect from previous node
            if row > 0 {
                let prevNode = nodes[row - 1]
                let elapsed = event.timestamp.timeIntervalSince(prevNode.event.timestamp)
                connectors.append(TimelineConnector(
                    fromRail: prevNode.rail,
                    fromRow: prevNode.row,
                    toRail: rail,
                    toRow: row,
                    type: event.type,
                    duration: elapsed,
                    timeboxMinutes: prevNode.event.to.timeboxMinutes,
                    fromTimestamp: prevNode.event.timestamp
                ))
                // Mark the from-node as completed if this transition is a completion
                if event.type == .completion {
                    nodes[row - 1].completedByNext = true
                }
            }
        }

        // Attach distractions to their parent node (the active intention at the time)
        for d in distractionEvents {
            guard let text = d.distractionText else { continue }
            // Find the last node whose event happened before or at this distraction
            if let nodeIndex = nodes.lastIndex(where: { $0.event.timestamp <= d.timestamp }) {
                nodes[nodeIndex].distractions.append(text)
            }
        }

        return TimelineLayout(
            nodes: nodes,
            connectors: connectors,
            railLabels: railLabels,
            railCount: nextRail
        )
    }
}

// MARK: - View

struct MirrorView: View {
    let transitionLogger: TransitionLogger
    var onDismiss: () -> Void = {}

    @State private var currentTime = Date()
    @State private var keyMonitor: Any?
    @State private var magnifyMonitor: Any?
    @State private var zoomLevel: CGFloat = 1.0
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var availableDays: [Date] = []
    @State private var events: [TransitionEvent] = []
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let minZoom: CGFloat = 0.3
    private let maxZoom: CGFloat = 3.0
    private let zoomStep: CGFloat = 0.2

    private var layout: TimelineLayout {
        TimelineLayout.build(from: events)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDay)
    }

    // Base layout constants (scaled by zoomLevel)
    private var railSpacing: CGFloat { 140 * zoomLevel }
    private var rowHeight: CGFloat { 80 * zoomLevel }
    private var nodeRadius: CGFloat { 5 * zoomLevel }
    private let timeColumnWidth: CGFloat = 50

    var body: some View {
        ZStack {
            Color(nsColor: NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                Text("Mirror")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundColor(.secondary)
                    .padding(.top, 40)

                // Day pills
                dayPills
                    .padding(.top, 12)

                if events.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    graphView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(timer) { currentTime = $0 }
        .onAppear { loadData(); installKeyMonitor(); installMagnificationMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: selectedDay) { _, _ in loadDayEvents() }
    }

    // MARK: - Key Monitor

    private func zoomIn() {
        withAnimation(.easeOut(duration: 0.15)) {
            zoomLevel = min(zoomLevel + zoomStep, maxZoom)
        }
    }

    private func zoomOut() {
        withAnimation(.easeOut(duration: 0.15)) {
            zoomLevel = max(zoomLevel - zoomStep, minZoom)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                onDismiss()
                return nil
            }
            // + or = key (zoom in)
            if event.keyCode == 24 {
                zoomIn()
                return nil
            }
            // - key (zoom out)
            if event.keyCode == 27 {
                zoomOut()
                return nil
            }
            // 0 key (reset zoom)
            if event.keyCode == 29 {
                withAnimation(.easeOut(duration: 0.15)) {
                    zoomLevel = 1.0
                }
                return nil
            }
            return event
        }
    }

    private func installMagnificationMonitor() {
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            let newZoom = zoomLevel + event.magnification
            withAnimation(.easeOut(duration: 0.05)) {
                zoomLevel = min(max(newZoom, minZoom), maxZoom)
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = magnifyMonitor {
            NSEvent.removeMonitor(monitor)
            magnifyMonitor = nil
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        availableDays = transitionLogger.availableDays()
        // Ensure today is always in the list
        let today = Calendar.current.startOfDay(for: Date())
        if !availableDays.contains(today) {
            availableDays.insert(today, at: 0)
        }
        loadDayEvents()
    }

    private func loadDayEvents() {
        events = transitionLogger.loadDay(for: selectedDay)
    }

    // MARK: - Day Pills

    private static let pillDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private var dayPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableDays, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    let label = Calendar.current.isDateInToday(day) ? "Today" : Self.pillDateFormatter.string(from: day)

                    Button(action: { selectedDay = day }) {
                        Text(label)
                            .font(.system(size: 12, weight: isSelected ? .medium : .regular, design: .monospaced))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isSelected ? Color.primary.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(isToday ? "No transitions yet today." : "No transitions on this day.")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundColor(.primary.opacity(0.6))
            Text(isToday ? "Declare an intention to begin." : "")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Graph

    private var graphView: some View {
        let lay = layout
        let gw = graphWidth(lay)
        let gh = graphHeight(lay)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Time scale pinned to left edge (doesn't scroll horizontally)
                    timeScale(lay)
                        .frame(width: 70, height: gh + 80)

                    // Graph scrolls horizontally
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            // Rail labels at top
                            railHeaders(lay)

                            // Connectors (draw behind nodes)
                            ForEach(lay.connectors) { conn in
                                connectorPath(conn, layout: lay)
                            }

                            // Now marker (today only)
                            if isToday {
                                nowMarker(layout: lay)
                                    .id("now")
                            }
                        }
                        .frame(width: gw, height: gh)
                        // Nodes as individual overlays
                        .overlay {
                            ForEach(lay.nodes) { node in
                                NodeCardView(
                                    node: node,
                                    zoomLevel: zoomLevel,
                                    nodeRadius: nodeRadius,
                                    railSpacing: railSpacing
                                )
                                .fixedSize()
                                .position(
                                    x: railX(node.rail, layout: lay),
                                    y: nodeY(node.row, totalRows: lay.nodes.count)
                                )
                            }
                            .frame(width: gw, height: gh)
                        }
                    }
                }
                .padding(.vertical, 40)
            }
            .onAppear {
                proxy.scrollTo("now", anchor: .top)
            }
        }
    }

    // MARK: - Time Scale

    private func timeScale(_ lay: TimelineLayout) -> some View {
        let nodes = lay.nodes
        guard let first = nodes.first, let last = nodes.last else {
            return AnyView(EmptyView())
        }

        let firstTime = first.event.timestamp
        let now = Date()
        let totalRows = nodes.count
        let showingToday = isToday

        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"

        struct TimeMark: Identifiable {
            let id = UUID()
            let label: String
            let y: CGFloat
            let isHour: Bool
        }

        var marks: [TimeMark] = []

        // Always show first node time
        marks.append(TimeMark(
            label: fmt.string(from: firstTime),
            y: nodeY(first.row, totalRows: totalRows),
            isHour: false
        ))

        // For past days, stop at the last event; for today, extend to now
        let endTime = showingToday ? now : last.event.timestamp

        // Add 30-min interval marks between first event and end time
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: firstTime)
        let minute = comps.minute ?? 0
        let nextHalf = minute < 30 ? 30 : 60
        var markDate = cal.date(bySettingHour: comps.hour! + (nextHalf == 60 ? 1 : 0),
                                 minute: nextHalf == 60 ? 0 : 30,
                                 second: 0, of: firstTime)!

        while markDate < endTime {
            let y = interpolatedY(for: markDate, nodes: nodes, now: now)
            let isHour = cal.component(.minute, from: markDate) == 0
            marks.append(TimeMark(label: fmt.string(from: markDate), y: y, isHour: isHour))
            markDate = cal.date(byAdding: .minute, value: 30, to: markDate)!
        }

        if showingToday {
            // Show "now" time at the bottom
            let nowY = nodeY(totalRows, totalRows: totalRows)
            marks.append(TimeMark(
                label: fmt.string(from: now),
                y: nowY,
                isHour: false
            ))
        } else {
            // Show last event time
            marks.append(TimeMark(
                label: fmt.string(from: last.event.timestamp),
                y: nodeY(last.row, totalRows: totalRows),
                isHour: false
            ))
        }

        return AnyView(
            ZStack {
                ForEach(marks) { mark in
                    Text(mark.label)
                        .font(.system(size: (mark.isHour ? 20 : 16) * zoomLevel, weight: mark.isHour ? .light : .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(mark.isHour ? 0.4 : 0.35))
                        .position(x: 35, y: mark.y)
                }
            }
        )
    }

    /// Interpolate a Y position for a given date, extending past the last node toward "now".
    private func interpolatedY(for date: Date, nodes: [TimelineNode], now: Date) -> CGFloat {
        let total = nodes.count
        // Before first node
        if date <= nodes.first!.event.timestamp {
            return nodeY(nodes.first!.row, totalRows: total)
        }
        // After last node — interpolate between last node and "now" marker
        if date >= nodes.last!.event.timestamp {
            let lastY = nodeY(nodes.last!.row, totalRows: total)
            let nowY = nodeY(total, totalRows: total)
            let span = now.timeIntervalSince(nodes.last!.event.timestamp)
            guard span > 0 else { return lastY }
            let frac = date.timeIntervalSince(nodes.last!.event.timestamp) / span
            return lastY + CGFloat(frac) * (nowY - lastY)
        }
        // Between two nodes
        for i in 0..<(nodes.count - 1) {
            let a = nodes[i]
            let b = nodes[i + 1]
            if date >= a.event.timestamp && date <= b.event.timestamp {
                let span = b.event.timestamp.timeIntervalSince(a.event.timestamp)
                guard span > 0 else { return nodeY(a.row, totalRows: total) }
                let frac = date.timeIntervalSince(a.event.timestamp) / span
                let yA = nodeY(a.row, totalRows: total)
                let yB = nodeY(b.row, totalRows: total)
                return yA + CGFloat(frac) * (yB - yA)
            }
        }
        return nodeY(nodes.last!.row, totalRows: total)
    }



    // MARK: - Rail Headers

    private func railHeaders(_ lay: TimelineLayout) -> some View {
        ForEach(0..<lay.railCount, id: \.self) { rail in
            let label = lay.railLabels[rail]
            let isInterruption = label == "⚡ Interruption"

            Text(isInterruption ? "⚡" : label)
                .font(.system(size: 11 * zoomLevel, weight: .regular, design: .serif))
                .foregroundColor(isInterruption ? .orange.opacity(0.6) : .secondary.opacity(0.4))
                .position(x: railX(rail, layout: lay), y: 16 * zoomLevel)
        }
    }

    // MARK: - Connectors

    private func connectorPath(_ conn: TimelineConnector, layout lay: TimelineLayout) -> some View {
        let fromX = railX(conn.fromRail, layout: lay)
        let fromY = nodeY(conn.fromRow, totalRows: lay.nodes.count) - nodeRadius
        let toX = railX(conn.toRail, layout: lay)
        let toY = nodeY(conn.toRow, totalRows: lay.nodes.count) + nodeRadius

        let isInterruption = conn.type == .interruption
        let isCompletion = conn.type == .completion
        let color: Color = isCompletion ? .green.opacity(0.3) :
                           isInterruption ? .orange.opacity(0.4) :
                           .primary.opacity(0.1)

        let midY = (fromY + toY) / 2

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: fromX, y: fromY))
                if conn.fromRail == conn.toRail {
                    path.addLine(to: CGPoint(x: toX, y: toY))
                } else {
                    path.addCurve(
                        to: CGPoint(x: toX, y: toY),
                        control1: CGPoint(x: fromX, y: midY),
                        control2: CGPoint(x: toX, y: midY)
                    )
                }
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: (isInterruption ? 1.5 : 1) * zoomLevel,
                dash: conn.type == .contextSwitch ? [4 * zoomLevel, 4 * zoomLevel] : []
            ))

            // Start time on left of line
            Text(timeLabel(conn.fromTimestamp))
                .font(.system(size: 9 * zoomLevel, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .position(x: min(fromX, toX) - 36 * zoomLevel, y: midY)

            // Elapsed duration on right of line
            Text(durationLabel(conn.duration))
                .font(.system(size: 9 * zoomLevel, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .position(x: max(fromX, toX) + 36 * zoomLevel, y: midY)
        }
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        let m = total / 60
        let s = total % 60
        if m < 60 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        let h = m / 60
        let rm = m % 60
        return rm > 0 ? "\(h)h \(rm)m" : "\(h)h"
    }

    // MARK: - Now Marker

    private func nowMarker(layout lay: TimelineLayout) -> some View {
        let y = nodeY(lay.nodes.count, totalRows: lay.nodes.count)
        let lastRail = lay.nodes.last?.rail ?? 0
        let x = railX(lastRail, layout: lay)

        return VStack(spacing: 2 * zoomLevel) {
            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 1.5 * zoomLevel)
                .frame(width: nodeRadius * 2, height: nodeRadius * 2)
            Text("now")
                .font(.system(size: 10 * zoomLevel, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .position(x: x, y: y)
    }

    // MARK: - Geometry Helpers

    private func railX(_ rail: Int, layout lay: TimelineLayout) -> CGFloat {
        let totalWidth = CGFloat(max(lay.railCount - 1, 0)) * railSpacing
        let startX = -totalWidth / 2
        return graphWidth(lay) / 2 + startX + CGFloat(rail) * railSpacing
    }

    private func nodeY(_ row: Int, totalRows: Int) -> CGFloat {
        let invertedRow = totalRows - row
        return CGFloat(invertedRow) * rowHeight + 48 * zoomLevel
    }

    private func graphWidth(_ lay: TimelineLayout) -> CGFloat {
        max(CGFloat(lay.railCount) * railSpacing + 80 * zoomLevel, 400)
    }

    private func graphHeight(_ lay: TimelineLayout) -> CGFloat {
        CGFloat(lay.nodes.count + 1) * rowHeight + 96 * zoomLevel
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Node Card

private struct NodeCardView: View {
    let node: TimelineNode
    let zoomLevel: CGFloat
    let nodeRadius: CGFloat
    let railSpacing: CGFloat
    @State private var isHovering = false

    private var isInterruption: Bool {
        node.event.type == .interruption || node.event.to.contextLabel == "⚡ Interruption"
    }
    private var isCompleted: Bool { node.completedByNext }

    private var accentColor: Color {
        isCompleted ? .green : isInterruption ? .orange : .primary
    }

    var body: some View {
        VStack(spacing: 0) {
            // Distraction tick marks above the dot
            if !node.distractions.isEmpty {
                HStack(spacing: 2 * zoomLevel) {
                    ForEach(Array(node.distractions.enumerated()), id: \.offset) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.red.opacity(0.5))
                            .frame(width: 2 * zoomLevel, height: 6 * zoomLevel)
                    }
                }
                .padding(.bottom, 2 * zoomLevel)
            }

            Circle()
                .fill(accentColor.opacity(0.7))
                .frame(width: nodeRadius * 2, height: nodeRadius * 2)

            Text(node.event.to.todoText)
                .font(.system(size: 12 * zoomLevel, weight: .regular, design: .serif))
                .foregroundColor(accentColor.opacity(0.8))
                .lineLimit(4)
                .multilineTextAlignment(.center)
                .frame(width: railSpacing - 16)
                .padding(.top, 4 * zoomLevel)

            if let tb = node.event.to.timeboxMinutes {
                HStack {
                    Spacer()
                    Text("\(tb)m")
                        .font(.system(size: 9 * zoomLevel, weight: .light, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .frame(width: railSpacing - 16)
            }
        }
        .padding(.horizontal, 6 * zoomLevel)
        .padding(.vertical, 4 * zoomLevel)
        .background(
            RoundedRectangle(cornerRadius: 6 * zoomLevel)
                .stroke(isHovering ? accentColor.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(alignment: .trailing) {
            if isHovering && !node.distractions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(node.distractions.enumerated()), id: \.offset) { _, text in
                        Text("• \(text)")
                            .font(.system(size: 11 * zoomLevel, weight: .regular, design: .serif))
                            .foregroundColor(.primary.opacity(0.8))
                    }
                }
                .padding(8 * zoomLevel)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                )
                .offset(x: railSpacing * 0.6)
                .allowsHitTesting(false)
            }
        }
    }
}
