import SwiftUI
import TranscriptorCore

/// Shows a queued or running job's filename and progress, or its error message if it failed.
struct JobRowView: View {
    /// Holds the job to display.
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.fileURL.lastPathComponent).lineLimit(1)
            switch job.state {
            case .loadingModel(let p), .transcribing(let p):
                ProgressView(value: p).controlSize(.small)
                Text(job.stateText).font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(3)
            default:
                Text(job.stateText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
