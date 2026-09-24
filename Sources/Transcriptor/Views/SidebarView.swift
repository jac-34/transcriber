import SwiftUI
import TranscriptorCore

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Binding var selection: SidebarItem?

    /// Jobs worth showing: anything unfinished, plus failures the user has not cleared.
    private var activeJobs: [Job] {
        state.queue.jobs.filter { job in
            if case .done = job.state { return false }
            return true
        }
    }

    var body: some View {
        List(selection: $selection) {
            if !activeJobs.isEmpty {
                Section("En proceso") {
                    ForEach(activeJobs) { job in
                        JobRowView(job: job).tag(SidebarItem.job(job.id))
                    }
                }
            }
            Section("Transcripciones") {
                if state.transcripts.isEmpty {
                    Text("Todavía no hay transcripciones.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(state.transcripts) { transcript in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transcript.title).lineLimit(1)
                        Text("\(transcript.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(Timestamp.duration(transcript.audioDuration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarItem.transcript(transcript.id))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
