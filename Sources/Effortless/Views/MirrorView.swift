import SwiftUI

// MARK: - Layout Model

/// A node placed on a specific rail at a specific row in the timeline.
struct TimelineNode: Identifiable {
    let id: UUID
    let event: TransitionEvent
    let rail: Int          // which vertical rail this node sits on
    let row: Int           // vertical position (0 = first event)
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

        for (row, event) in events.enumerated() {
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
                    duration: elapsed
                ))
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
    let events: [TransitionEvent]
    var onDismiss: () -> Void = {}

    @State private var currentTime = Date()
    @State private var keyMonitor: Any?
    @State private var magnifyMonitor: Any?
    @State private var zoomLevel: CGFloat = 1.0
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let minZoom: CGFloat = 0.3
    private let maxZoom: CGFloat = 3.0
    private let zoomStep: CGFloat = 0.2

    private var layout: TimelineLayout {
        TimelineLayout.build(from: events)
    }

    // Base layout constants (scaled by zoomLevel)
    private var railSpacing: CGFloat { 120 * zoomLevel }
    private var rowHeight: CGFloat { 64 * zoomLevel }
    private var nodeRadius: CGFloat { 5 * zoomLevel }
    private let timeColumnWidth: CGFloat = 50

    var body: some View {
        ZStack {
            Color(nsColor: NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                Text(currentTime, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .light, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 80)

                Text("Mirror")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

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
        .onAppear { installKeyMonitor(); installMagnificationMonitor() }
        .onDisappear { removeKeyMonitor() }
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No transitions yet today.")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundColor(.primary.opacity(0.6))
            Text("Declare an intention to begin.")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Graph

    private var graphView: some View {
        let lay = layout

        return ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Rail labels at top
                    railHeaders(lay)

                    // Connectors (draw behind nodes)
                    ForEach(lay.connectors) { conn in
                        connectorPath(conn, layout: lay)
                    }

                    // Nodes
                    ForEach(lay.nodes) { node in
                        nodeView(node, layout: lay)
                    }

                    // Now marker
                    nowMarker(layout: lay)
                        .id("now")
                }
                .frame(
                    width: graphWidth(lay),
                    height: graphHeight(lay)
                )
                .padding(.vertical, 40)
            }
            .onAppear {
                proxy.scrollTo("now", anchor: .top)
            }
        }
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

    // MARK: - Node

    private func nodeView(_ node: TimelineNode, layout lay: TimelineLayout) -> some View {
        let x = railX(node.rail, layout: lay)
        let y = nodeY(node.row, totalRows: lay.nodes.count)
        let isInterruption = node.event.type == .interruption ||
                             node.event.to.contextLabel == "⚡ Interruption"

        return VStack(spacing: 0) {
            // The node dot
            Circle()
                .fill(isInterruption ? Color.orange.opacity(0.7) : Color.primary.opacity(0.35))
                .frame(width: nodeRadius * 2, height: nodeRadius * 2)

            // Label below node
            VStack(spacing: 1) {
                Text(node.event.to.todoText)
                    .font(.system(size: 12 * zoomLevel, weight: .regular, design: .serif))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(timeLabel(node.event.timestamp))
                    .font(.system(size: 10 * zoomLevel, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .frame(width: railSpacing - 16)
            .padding(.top, 4 * zoomLevel)
        }
        .position(x: x, y: y)
    }

    // MARK: - Connectors

    private func connectorPath(_ conn: TimelineConnector, layout lay: TimelineLayout) -> some View {
        let fromX = railX(conn.fromRail, layout: lay)
        let fromY = nodeY(conn.fromRow, totalRows: lay.nodes.count) - nodeRadius
        let toX = railX(conn.toRail, layout: lay)
        let toY = nodeY(conn.toRow, totalRows: lay.nodes.count) + nodeRadius

        let isInterruption = conn.type == .interruption
        let color = isInterruption ? Color.orange.opacity(0.4) : Color.primary.opacity(0.1)

        let midX = (fromX + toX) / 2
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

            // Duration label at midpoint of connector
            Text(durationLabel(conn.duration))
                .font(.system(size: 9 * zoomLevel, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .position(x: conn.fromRail == conn.toRail ? midX + 24 * zoomLevel : midX, y: midY)
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
        // Inverted: row 0 (earliest) at bottom, last row (now) at top.
        // "now" marker uses row = totalRows (one past last node).
        let invertedRow = totalRows - row
        return CGFloat(invertedRow) * rowHeight + 48 * zoomLevel // offset for rail headers
    }

    private func graphWidth(_ lay: TimelineLayout) -> CGFloat {
        max(CGFloat(lay.railCount) * railSpacing + 80 * zoomLevel, 400)
    }

    private func graphHeight(_ lay: TimelineLayout) -> CGFloat {
        CGFloat(lay.nodes.count + 1) * rowHeight + 96 * zoomLevel
    }

    // MARK: - Helpers

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
