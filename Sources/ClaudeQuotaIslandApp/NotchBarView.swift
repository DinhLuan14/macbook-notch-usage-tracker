import AppKit
import ClaudeQuotaIslandCore
import SwiftUI

struct NotchBarView: View {
    @ObservedObject var model: AppModel
    let metrics: NotchLayoutMetrics

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            NotchBarContent(
                preferences: model.displayPreferences,
                quotaSnapshot: model.quotaSnapshot,
                sessionSnapshot: model.selectedSnapshot,
                projects: model.recentProjects,
                selectedSessionID: model.selectedSessionID,
                selectedProjectID: model.selectedProjectID,
                remoteHost: model.remoteConfiguration.host,
                metrics: metrics,
                isExpanded: model.isIslandExpanded,
                now: context.date,
                isInteractive: true,
                onHoverChanged: model.handleIslandHover,
                onSelectSession: model.selectSession,
                onSelectProject: model.selectProject,
                onShowSettings: model.showSettings,
                onQuit: model.quit
            )
        }
        .contextMenu {
            Button("Settings…", action: model.showSettings)
            Divider()
            Button("Quit Claude Quota Island", action: model.quit)
        }
    }
}

struct NotchBarPreview: View {
    let preferences: DisplayPreferences
    @State private var isExpanded = false

    private static let quota = ClaudeSessionSnapshot(
        sessionID: "preview-quota",
        fiveHour: ClaudeQuotaWindow(usedPercentage: 31, resetsAt: .now.addingTimeInterval(4 * 3_600 + 34 * 60)),
        sevenDay: ClaudeQuotaWindow(usedPercentage: 34, resetsAt: .now.addingTimeInterval(40 * 3_600))
    )

    private static let session = ClaudeSessionSnapshot(
        sessionID: "preview-session",
        sessionName: "Personal project",
        modelDisplayName: "Opus 4.8",
        effort: "high",
        contextUsedPercentage: 63,
        contextWindowSize: 200_000,
        totalInputTokens: 126_000
    )

    var body: some View {
        GeometryReader { proxy in
            let metrics = NotchLayoutMetrics.preview(
                preferences: preferences,
                quotaSnapshot: Self.quota,
                sessionSnapshot: Self.session
            )
            let expandedWidth = metrics.visualMetrics(isExpanded: true).totalWidth
            let scale = min(0.78, max(0.55, (proxy.size.width - 8) / expandedWidth))

            ZStack(alignment: .top) {
                NotchBarContent(
                    preferences: preferences,
                    quotaSnapshot: Self.quota,
                    sessionSnapshot: Self.session,
                    projects: [],
                    selectedSessionID: nil,
                    selectedProjectID: nil,
                    remoteHost: "server",
                    metrics: metrics,
                    isExpanded: isExpanded,
                    now: .now,
                    isInteractive: false,
                    onHoverChanged: { isExpanded = $0 },
                    onSelectSession: { _ in },
                    onSelectProject: { _ in },
                    onShowSettings: {},
                    onQuit: {}
                )
                .frame(width: expandedWidth, height: metrics.expandedHeight)
                .scaleEffect(scale, anchor: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        .frame(height: 52)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isExpanded)
    }
}

private struct NotchBarContent: View {
    let preferences: DisplayPreferences
    let quotaSnapshot: ClaudeSessionSnapshot?
    let sessionSnapshot: ClaudeSessionSnapshot?
    let projects: [ClaudeRecentProject]
    let selectedSessionID: String?
    let selectedProjectID: String?
    let remoteHost: String
    let metrics: NotchLayoutMetrics
    let isExpanded: Bool
    let now: Date
    let isInteractive: Bool
    let onHoverChanged: (Bool) -> Void
    let onSelectSession: (String?) -> Void
    let onSelectProject: (String?) -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let visual = metrics.visualMetrics(isExpanded: isExpanded)

        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                quotaLane
                    .frame(width: visual.leftWidth, height: visual.height)

                Color.clear
                    .frame(width: visual.notchWidth, height: visual.height)

                sessionLane
                    .frame(width: visual.rightWidth, height: visual.height)
            }
            .frame(width: visual.totalWidth, height: visual.height)
            .background(
                QuotaIslandSurfaceShape(cornerRadius: isExpanded ? 18 : visual.height / 2)
                    .fill(Color(red: 0.035, green: 0.035, blue: 0.045))
            )
            .clipShape(QuotaIslandSurfaceShape(cornerRadius: isExpanded ? 18 : visual.height / 2))
            .contentShape(QuotaIslandSurfaceShape(cornerRadius: isExpanded ? 18 : visual.height / 2))
            .onHover(perform: onHoverChanged)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isExpanded)
    }

    private var quotaLane: some View {
        HStack(spacing: quotaSpacing) {
            quotaItem(
                label: "5h",
                symbol: "clock",
                window: quotaSnapshot?.fiveHour?.current(at: now)
            )
            laneDivider
            quotaItem(
                label: "7d",
                symbol: "calendar",
                window: quotaSnapshot?.sevenDay?.current(at: now)
            )
        }
        .padding(.horizontal, isExpanded ? 11 : 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(quotaAccessibilityLabel)
    }

    private var quotaSpacing: CGFloat {
        isExpanded ? (preferences.style == .minimal ? 6 : 8) : 5
    }

    @ViewBuilder
    private func quotaItem(
        label: String,
        symbol: String,
        window: ClaudeQuotaWindow?
    ) -> some View {
        let percentage = QuotaFormatter.percentage(window?.usedPercentage, metric: preferences.quotaMetric)
        let percentageText = percentage.map { "\($0)%" } ?? "…"
        let reset = QuotaFormatter.resetDuration(
            until: window?.resetsAt,
            now: now,
            compact: true
        )
        let tint = statusColor(for: window?.usedPercentage)

        if !isExpanded {
            HStack(spacing: 3) {
                if preferences.style == .iconCompact || preferences.style == .progressRings {
                    Image(systemName: symbol)
                        .foregroundStyle(.white.opacity(0.58))
                } else {
                    Text(label)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(percentageText)
                    .foregroundStyle(tint)
                    .fontWeight(.semibold)
                if label == "5h", preferences.showsResetTime, let reset {
                    Text(reset)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(compactStatusFont)
            .fixedSize()
        } else {
            switch preferences.style {
            case .full:
                HStack(spacing: 5) {
                    Text(label).foregroundStyle(.white.opacity(0.55))
                    Text(percentageText).foregroundStyle(tint).fontWeight(.semibold)
                    if preferences.showsResetTime, let reset {
                        Text(reset).foregroundStyle(.white.opacity(0.62))
                    }
                }
                .font(statusFont)
                .fixedSize()

            case .iconCompact:
                HStack(spacing: 5) {
                    Image(systemName: symbol).foregroundStyle(.white.opacity(0.64))
                    Text(percentageText).foregroundStyle(tint).fontWeight(.semibold)
                    if preferences.showsResetTime, let reset {
                        Text(reset).foregroundStyle(.white.opacity(0.62))
                    }
                }
                .font(statusFont)
                .fixedSize()

            case .progressRings:
                HStack(spacing: 5) {
                    ProgressRing(symbol: symbol, usedPercentage: window?.usedPercentage, tint: tint)
                    Text(percentageText).foregroundStyle(tint).fontWeight(.semibold)
                    if preferences.showsResetTime, let reset {
                        Text(reset).foregroundStyle(.white.opacity(0.62))
                    }
                }
                .font(statusFont)
                .fixedSize()

            case .minimal:
                HStack(spacing: 4) {
                    Image(systemName: symbol).foregroundStyle(.white.opacity(0.64))
                    Text(percentageText).foregroundStyle(tint).fontWeight(.semibold)
                }
                .font(statusFont)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var sessionLane: some View {
        HStack(spacing: 0) {
            rightSideContent

            if isInteractive && isExpanded {
                sessionPickerMenu
                    .frame(width: 26, height: 26)
                    .padding(.trailing, 8)
            }
        }
        .opacity(
            preferences.rightSideMode == .claudeOnly
                ? 1
                : (sessionSnapshot?.isFresh(at: now) == false ? 0.62 : 1)
        )
        .accessibilityLabel(sessionAccessibilityLabel)
    }

    private var sessionPickerMenu: some View {
        Menu {
            if preferences.rightSideMode == .modelAndContext {
                Button {
                    onSelectProject(nil)
                    onSelectSession(nil)
                } label: {
                    if selectedProjectID == nil, selectedSessionID == nil {
                        Image(systemName: "checkmark")
                    }
                    Text("Automatic · monitored folders")
                }

                if !projects.isEmpty { Divider() }
                ForEach(Array(projects.prefix(10))) { project in
                    Menu {
                        Button {
                            onSelectProject(project.id)
                        } label: {
                            if selectedProjectID == project.id, selectedSessionID == nil {
                                Image(systemName: "checkmark")
                            }
                            Text("Most recent conversation")
                        }

                        if !project.sessions.isEmpty { Divider() }
                        ForEach(Array(project.sessions.prefix(8))) { session in
                            Button {
                                onSelectSession(session.id)
                            } label: {
                                if selectedSessionID == session.id { Image(systemName: "checkmark") }
                                Text(sessionMenuTitle(session))
                            }
                        }
                        if project.sessions.count > 8 {
                            Divider()
                            Button("\(project.sessions.count - 8) more…", action: onShowSettings)
                        }
                    } label: {
                        Text(projectMenuTitle(project))
                    }
                }
                if projects.count > 10 {
                    Button("\(projects.count - 10) more projects…", action: onShowSettings)
                }

                Divider()
            }

            Button("Settings…", action: onShowSettings)
            Button("Quit", action: onQuit)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.06), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(
            preferences.rightSideMode == .claudeOnly
                ? "Claude Quota Island menu"
                : "Choose Claude session"
        )
    }

    @ViewBuilder
    private var rightSideContent: some View {
        if preferences.rightSideMode == .claudeOnly {
            Text("Claude")
                .font(isExpanded ? statusFont : compactStatusFont)
                .fontWeight(.semibold)
                .foregroundStyle(.cyan)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            sessionContent
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        HStack(spacing: 6) {
            if sessionSnapshot?.resolvedSource.isRemote == true {
                Image(systemName: "globe")
                    .frame(width: 13, alignment: .center)
                    .fixedSize()
                    .foregroundStyle(.white.opacity(0.58))
            }

            ModelMarqueeText(
                model: modelDisplayName,
                effort: marqueeEffort,
                fontSize: isExpanded ? 11.5 : 10.5,
                contentWidth: modelMarqueeContentWidth,
                resetKey: modelMarqueeKey
            )
            .frame(width: modelMarqueeSlotWidth, height: 18)

            laneDivider
                .fixedSize()

            HStack(spacing: 5) {
                if isExpanded {
                    if preferences.style == .full {
                        Text("ctx").foregroundStyle(.white.opacity(0.55))
                    } else {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Text(contextPercentageText)
                    .foregroundStyle(statusColor(for: sessionSnapshot?.contextUsedPercentage))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if isExpanded,
                   preferences.showsTokenCount,
                   preferences.style != .minimal,
                   sessionSnapshot?.contextUsedPercentage != nil,
                   let tokens = QuotaFormatter.tokenCount(sessionSnapshot?.totalInputTokens) {
                    Text(tokens).foregroundStyle(.white.opacity(0.62))
                }
            }
            .fixedSize()
        }
        .font(isExpanded ? statusFont : compactStatusFont)
        .padding(.leading, isExpanded ? 12 : 8)
        .padding(.trailing, isExpanded ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var laneDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.24))
            .frame(width: 1, height: 15)
    }

    private var statusFont: Font {
        .system(size: 11.5, weight: .medium, design: .monospaced)
    }

    private var compactStatusFont: Font {
        .system(size: 10.5, weight: .medium, design: .monospaced)
    }

    private var contextPercentageText: String {
        if let percentage = sessionSnapshot?.contextUsedPercentage {
            return "\(Int(min(max(percentage, 0), 100).rounded()))%"
        }
        return QuotaFormatter.tokenCount(sessionSnapshot?.totalInputTokens) ?? "…"
    }

    private var modelDisplayName: String {
        sessionSnapshot?.modelDisplayName ?? "Claude"
    }

    private var modelMarqueeKey: String {
        "\(modelDisplayName)|\(marqueeEffort ?? "")|\(isExpanded)"
    }

    private var marqueeEffort: String? {
        guard isExpanded,
              preferences.showsEffort,
              preferences.style != .minimal,
              let effort = sessionSnapshot?.effort,
              !effort.isEmpty else {
            return nil
        }
        return effort
    }

    private var modelMarqueeContentWidth: CGFloat {
        let size: CGFloat = isExpanded ? 11.5 : 10.5
        let modelFont = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        var width = (modelDisplayName as NSString).size(
            withAttributes: [.font: modelFont]
        ).width
        if let effort = marqueeEffort {
            let effortFont = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
            width += 5 + (effort as NSString).size(
                withAttributes: [.font: effortFont]
            ).width
        }
        return ceil(width)
    }

    private var modelMarqueeSlotWidth: CGFloat {
        let rightWidth = metrics.visualMetrics(isExpanded: isExpanded).rightWidth
        let pickerWidth: CGFloat = isInteractive && isExpanded ? 34 : 0
        let paddingWidth: CGFloat = isExpanded ? 20 : 18
        let sourceWidth: CGFloat = sessionSnapshot?.resolvedSource.isRemote == true ? 19 : 0
        let dividerAndSpacing: CGFloat = 13
        return max(
            rightWidth
                - pickerWidth
                - paddingWidth
                - sourceWidth
                - dividerAndSpacing
                - contextContentWidth,
            42
        )
    }

    private var contextContentWidth: CGFloat {
        let size: CGFloat = isExpanded ? 11.5 : 10.5
        let medium = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        let semibold = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        var width = measuredWidth(contextPercentageText, font: semibold)
        guard isExpanded else { return width }

        width += 5
        width += preferences.style == .full
            ? measuredWidth("ctx", font: medium)
            : 13
        if preferences.showsTokenCount,
           preferences.style != .minimal,
           sessionSnapshot?.contextUsedPercentage != nil,
           let tokens = QuotaFormatter.tokenCount(sessionSnapshot?.totalInputTokens) {
            width += 5 + measuredWidth(tokens, font: medium)
        }
        return ceil(width)
    }

    private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func statusColor(for usedPercentage: Double?) -> Color {
        guard let usedPercentage else { return .white.opacity(0.45) }
        if usedPercentage >= 80 { return .red }
        if usedPercentage >= 50 { return .orange }
        return .mint
    }

    private func sessionMenuTitle(_ session: ClaudeSessionSnapshot) -> String {
        let context = session.contextUsedPercentage.map { " · \(Int($0.rounded()))%" } ?? ""
        return "\(session.sessionID.prefix(8)) · \(session.modelDisplayName ?? "Claude")\(context)"
    }

    private func projectMenuTitle(_ project: ClaudeRecentProject) -> String {
        let source = project.source.isRemote ? "SSH: \(remoteHost)" : "Local"
        let selected = selectedProjectID == project.id ? "✓ " : ""
        return "\(selected)\(project.name) [\(source)]"
    }

    private var quotaAccessibilityLabel: String {
        let five = QuotaFormatter.percentage(
            quotaSnapshot?.fiveHour?.current(at: now)?.usedPercentage,
            metric: preferences.quotaMetric
        )
            .map(String.init) ?? "unavailable"
        let seven = QuotaFormatter.percentage(
            quotaSnapshot?.sevenDay?.current(at: now)?.usedPercentage,
            metric: preferences.quotaMetric
        )
            .map(String.init) ?? "unavailable"
        return "Five hour quota \(five) percent. Seven day quota \(seven) percent."
    }

    private var sessionAccessibilityLabel: String {
        if preferences.rightSideMode == .claudeOnly {
            return "Claude quota tracker"
        }
        return "\(sessionSnapshot?.modelDisplayName ?? "Claude"), context \(contextPercentageText), session \(sessionSnapshot?.title ?? "unavailable")"
    }
}

private struct ModelMarqueeText: View {
    let model: String
    let effort: String?
    let fontSize: CGFloat
    let contentWidth: CGFloat
    let resetKey: String

    @State private var animationStartedAt: Date?
    @State private var animationToken = UUID()

    var body: some View {
        GeometryReader { proxy in
            let overflow = max(contentWidth - proxy.size.width, 0)

            TimelineView(
                .animation(
                    minimumInterval: 1 / 30,
                    paused: animationStartedAt == nil || overflow < 1
                )
            ) { timeline in
                Canvas { context, size in
                    let text = context.resolve(marqueeText)
                    context.draw(
                        text,
                        at: CGPoint(
                            x: -travelOffset(
                                at: timeline.date,
                                overflow: overflow
                            ),
                            y: size.height / 2
                        ),
                        anchor: .leading
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .onAppear {
                restart(overflow: overflow)
            }
            .onChange(of: overflow) { _, value in
                restart(overflow: value)
            }
            .onChange(of: resetKey) {
                restart(overflow: overflow)
            }
            .onDisappear {
                animationToken = UUID()
                animationStartedAt = nil
            }
        }
        .clipped()
    }

    private var marqueeText: Text {
        let modelText = Text(model)
            .foregroundColor(.cyan)
            .fontWeight(.semibold)
        let combined: Text
        if let effort {
            combined = modelText
                + Text(" \(effort)")
                    .foregroundColor(.purple.opacity(0.9))
                    .fontWeight(.medium)
        } else {
            combined = modelText
        }
        return combined.font(.system(size: fontSize, weight: .medium, design: .monospaced))
    }

    private func restart(overflow: CGFloat) {
        let token = UUID()
        animationToken = token
        animationStartedAt = nil
        guard overflow >= 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            guard animationToken == token else { return }
            animationStartedAt = .now
        }
    }

    private func travelOffset(at date: Date, overflow: CGFloat) -> CGFloat {
        guard let animationStartedAt, overflow >= 1 else { return 0 }
        let travel = max(TimeInterval(overflow / 22), 0.8)
        let pause: TimeInterval = 1.25
        let cycle = travel + pause + travel + pause
        let elapsed = max(date.timeIntervalSince(animationStartedAt), 0)
            .truncatingRemainder(dividingBy: cycle)

        if elapsed < travel {
            return overflow * easedProgress(elapsed / travel)
        }
        if elapsed < travel + pause {
            return overflow
        }
        if elapsed < travel + pause + travel {
            return overflow * (1 - easedProgress((elapsed - travel - pause) / travel))
        }
        return 0
    }

    private func easedProgress(_ value: TimeInterval) -> CGFloat {
        let bounded = min(max(value, 0), 1)
        return CGFloat(bounded * bounded * (3 - 2 * bounded))
    }
}

private struct ProgressRing: View {
    let symbol: String
    let usedPercentage: Double?
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max((usedPercentage ?? 0) / 100, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(width: 22, height: 22)
    }
}

/// Flat top plus rounded lower corners, matching the physical MacBook notch.
/// The panel itself remains transparent and fixed at the expanded size.
private struct QuotaIslandSurfaceShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
