import SwiftUI
import TranscriptorCore

struct JobRowView: View {
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
