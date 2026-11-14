import FlickCore
import SwiftUI

struct SetupView: View {
    let library: RecordingLibrary
    let motion: MotionRecorder

    @Environment(\.scenePhase) private var scenePhase
    @State private var participant = 1
    @State private var activity = Activity.swings(.forehand, .medium)
    @State private var liveRecording: LiveRecording?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Participant") {
                    Picker("Participant", selection: $participant) {
                        ForEach(Recording.participants, id: \.self) { Text("P\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Activity", selection: $activity) {
                        Section("Swings") { options(Activity.all.filter(\.isSwings)) }
                        Section("Not swings") { options(Activity.all.filter { !$0.isSwings && $0 != .still }) }
                        Text(Activity.still.title).tag(Activity.still)
                    }
                    Button(isSaving ? "Saving…" : "Start recording", action: start)
                        .disabled(!motion.isAvailable || isSaving)
                } footer: {
                    Text(motion.isAvailable ? activity.instructions : "Motion sensors aren't available here. Run the recorder on an iPhone.")
                }
                Section("Recordings") {
                    if library.files.isEmpty {
                        Text("No recordings yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.files, id: \.self) { file in
                        Text(file.lastPathComponent)
                            .font(.footnote.monospaced())
                    }
                    .onDelete { offsets in
                        attempt { try library.delete(at: offsets) }
                    }
                }
            }
            .navigationTitle("Flick Recorder")
            .toolbar {
                ShareLink(items: library.files) {
                    Label("Export all", systemImage: "square.and.arrow.up")
                }
                .disabled(library.files.isEmpty)
            }
            .fullScreenCover(item: $liveRecording) { recording in
                RecordingView(recording: recording) { stop(recording) }
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { attempt { try library.reload() } }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background, let recording = liveRecording else { return }
                stop(recording)
            }
        }
    }

    private func options(_ activities: [Activity]) -> some View {
        ForEach(activities, id: \.self) { Text($0.title).tag($0) }
    }

    private func start() {
        let recording = LiveRecording(activity: activity, participant: participant)
        motion.start(recording)
        liveRecording = recording
    }

    private func stop(_ recording: LiveRecording) {
        motion.stop()
        liveRecording = nil
        let finished = recording.finish(at: microseconds(sinceBoot: ProcessInfo.processInfo.systemUptime))
        guard finished.frames.count >= 2 else {
            errorMessage = "The recording was too short to save."
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await library.save(finished)
            } catch {
                errorMessage = "The recording couldn't be saved: \(error.localizedDescription)"
            }
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
