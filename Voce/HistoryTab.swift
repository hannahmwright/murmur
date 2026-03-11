import SwiftUI
import VoceKit

struct HistoryTab: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchQuery: String = ""
    @State private var expandedIDs: Set<UUID> = []
    @State private var hoveredID: UUID?
    @State private var currentTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: VoceDesign.md) {
            // Header bar
            HStack {
                Text("History")
                    .font(VoceDesign.heading2())
                    .foregroundStyle(VoceDesign.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: VoceDesign.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(VoceDesign.textSecondary)
                        .font(VoceDesign.caption())
                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(VoceDesign.callout())
                        .accessibilityLabel("Search transcripts")
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(VoceDesign.caption())
                                .foregroundStyle(VoceDesign.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, VoceDesign.sm)
                .padding(.vertical, VoceDesign.xs + VoceDesign.xxs)
                .glassBackground(cornerRadius: VoceDesign.radiusSmall)
                .overlay(
                    RoundedRectangle(cornerRadius: VoceDesign.radiusSmall)
                        .stroke(VoceDesign.border, lineWidth: VoceDesign.borderThin)
                )
                .frame(maxWidth: VoceDesign.searchBarMaxWidth)
            }

            // Content
            if filteredEntries.isEmpty {
                Spacer()
                VStack(spacing: VoceDesign.sm) {
                    Image(systemName: searchQuery.isEmpty ? "text.bubble" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(VoceDesign.textSecondary.opacity(0.5))
                    Text(searchQuery.isEmpty ? "No transcripts yet" : "No matches")
                        .font(VoceDesign.body())
                        .foregroundStyle(VoceDesign.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VoceDesign.sm) {
                        ForEach(groupedEntries, id: \.label) { group in
                            // Day header
                            Text(group.label)
                                .font(VoceDesign.captionEmphasis())
                                .foregroundStyle(VoceDesign.textSecondary)
                                .padding(.top, VoceDesign.sm)
                                .padding(.leading, VoceDesign.xs)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(group.entries) { entry in
                                entryRow(entry)
                            }
                        }
                    }
                    .padding(.bottom, VoceDesign.lg)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: VoceDesign.animationNormal),
                        value: filteredEntries.count
                    )
                }
            }
        }
        .padding(.vertical, VoceDesign.lg)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            currentTime = now
        }
    }

    private var filteredEntries: [TranscriptEntry] {
        if searchQuery.isEmpty {
            return controller.recentEntries
        }
        return controller.recentEntries.filter {
            $0.cleanText.localizedCaseInsensitiveContains(searchQuery)
            || $0.rawText.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var groupedEntries: [DayGroup] {
        let calendar = Calendar.current
        var groups: [String: [TranscriptEntry]] = [:]
        var order: [String] = []

        for entry in filteredEntries {
            let label = dayLabel(for: entry.createdAt, calendar: calendar)
            if groups[label] == nil {
                order.append(label)
                groups[label] = []
            }
            groups[label]?.append(entry)
        }

        return order.map { DayGroup(label: $0, entries: groups[$0] ?? []) }
    }

    private func dayLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        _ = currentTime
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: TranscriptEntry) -> some View {
        let isExpanded = expandedIDs.contains(entry.id)
        let isHovered = hoveredID == entry.id

        return VStack(alignment: .leading, spacing: VoceDesign.sm) {
            // Text + metadata on one line
            HStack(alignment: .top, spacing: VoceDesign.sm) {
                // Transcript text
                Text(entry.cleanText.isEmpty ? entry.rawText : entry.cleanText)
                    .font(VoceDesign.callout())
                    .foregroundStyle(VoceDesign.textPrimary)
                    .lineLimit(isExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: VoceDesign.animationFast)) {
                            if isExpanded {
                                expandedIDs.remove(entry.id)
                            } else {
                                expandedIDs.insert(entry.id)
                            }
                        }
                    }

                // Chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(VoceDesign.textSecondary.opacity(0.5))
                    .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            }

            // Bottom row: metadata left, actions right (actions on hover)
            HStack(spacing: VoceDesign.sm) {
                Text(appName(for: entry.appBundleID))
                    .font(VoceDesign.label())
                    .foregroundStyle(VoceDesign.textSecondary)

                Text("\u{00B7}")
                    .foregroundStyle(VoceDesign.textSecondary.opacity(0.4))

                Text(relativeTimestamp(for: entry.createdAt))
                    .font(VoceDesign.label())
                    .foregroundStyle(VoceDesign.textSecondary)

                statusDot(entry.insertionStatus)

                Spacer()

                // Actions — visible on hover or always on expanded
                if isHovered || isExpanded {
                    HStack(spacing: VoceDesign.md) {
                        Button {
                            controller.copyEntry(entry)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(VoceDesign.label())
                                .foregroundStyle(VoceDesign.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            controller.pasteEntry(entry)
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .font(VoceDesign.label())
                                .foregroundStyle(VoceDesign.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: VoceDesign.animationFast), value: isHovered)
        }
        .accessibilityElement(children: .contain)
        .cardStyle(elevation: .sm)
        .onHover { hovering in
            hoveredID = hovering ? entry.id : nil
        }
        .contextMenu {
            Button {
                controller.copyEntry(entry)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                controller.pasteEntry(entry)
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Divider()
            Button(role: .destructive) {
                controller.deleteEntry(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Status Dot (replaces verbose pill)

    private func statusDot(_ status: InsertionStatus) -> some View {
        let color: Color = {
            switch status {
            case .inserted: return VoceDesign.success
            case .copiedOnly: return VoceDesign.warning
            case .failed: return VoceDesign.error
            }
        }()

        let label: String = {
            switch status {
            case .inserted: return "Inserted"
            case .copiedOnly: return "Copied"
            case .failed: return "Failed"
            }
        }()

        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .accessibilityLabel("Status: \(label)")
            .help(label)
    }

    private func appName(for bundleID: String) -> String {
        guard !bundleID.isEmpty else { return "Unknown" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }
}

private struct DayGroup {
    let label: String
    let entries: [TranscriptEntry]
}
