import ActivityKit
import SwiftUI
import WidgetKit

/// The only face of a dictation on the iPhone. No stop button: a button here would run the
/// intent outside the shortcut, and the text it returns would go nowhere. The trigger that
/// started the dictation is the one that stops it.
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseLabel(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Elapsed(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.detail.isEmpty {
                        Text(context.state.detail)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            } compactLeading: {
                PhaseSymbol(state: context.state)
            } compactTrailing: {
                Elapsed(state: context.state)
            } minimal: {
                PhaseSymbol(state: context.state)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PhaseLabel(state: state)
                Spacer()
                Elapsed(state: state)
            }
            if !state.detail.isEmpty {
                Text(state.detail)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}

private struct PhaseLabel: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        Label(state.phase.label, systemImage: state.phase.symbol)
            .lineLimit(1)
            .foregroundStyle(state.phase == .recording ? .red : .primary)
    }
}

private struct PhaseSymbol: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        Image(systemName: state.phase.symbol)
            .foregroundStyle(state.phase == .recording ? .red : .primary)
    }
}

private struct Elapsed: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        if state.phase == .recording {
            // A past date with the timer style counts up on its own: nothing has to update
            // the activity while it records.
            Text(state.startedAt, style: .timer)
                .monospacedDigit()
                .frame(maxWidth: 52)
        } else {
            Text(state.phase.label)
                .lineLimit(1)
        }
    }
}
