import SwiftUI

struct SettingsButton: View {
    let controller: HostController
    @Binding var showsFrameTimes: Bool
    @State private var isOpen = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { isOpen = false }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    isOpen.toggle()
                } label: {
                    Image(systemName: isOpen ? "xmark" : "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Programme.paper)
                .background(Programme.navy, in: RoundedRectangle(cornerRadius: Programme.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Programme.cornerRadius, style: .continuous).inset(by: 3).strokeBorder(Programme.paper.opacity(0.5), lineWidth: 1))
                .help("Settings")
                .accessibilityLabel(isOpen ? "Close settings" : "Settings")
                if isOpen {
                    SettingsCard(controller: controller, showsFrameTimes: $showsFrameTimes, close: { isOpen = false })
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
            .padding(16)
        }
        .animation(.easeOut(duration: 0.18), value: isOpen)
    }
}

private struct SettingsCard: View {
    let controller: HostController
    @Binding var showsFrameTimes: Bool
    let close: () -> Void

    private var match: Match {
        controller.match
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Settings")
                    .font(Programme.title(22))
                Spacer()
                Text("★")
                    .font(Programme.title(14))
                    .foregroundStyle(Programme.navy)
                    .accessibilityHidden(true)
            }
            if !controller.isViewer {
                SettingsSection("Match") {
                    ActionRow(title: "New Game…", detail: "⌘N") {
                        close()
                        match.chooseNewGame()
                    }
                    ActionRow(title: match.isPaused ? "Resume" : "Pause", detail: "ESC") {
                        close()
                        match.togglePause()
                    }
                    .disabled(!match.hasStarted || match.isGameOver || match.isHeld || match.isWaitingForADevice)
                }
                if !match.isSolo {
                    SettingsSection("Camera") {
                        CameraChoice(selection: Binding(get: { match.camera }, set: { match.camera = $0 }))
                            .padding(.vertical, 8)
                    }
                }
                SettingsSection("Sound") {
                    SwitchRow(title: "Commentary", isOn: Bindable(match.referee).commentates)
                }
            }
            if !controller.isViewer {
                SettingsSection("Help") {
                    ActionRow(title: "How to Play", stub: "SHOW") {
                        close()
                        match.showsTutorial = true
                    }
                    SwitchRow(title: "Keyboard Controls", isOn: Bindable(match).showsKeyboardControls)
                }
            }
            SettingsSection("This Mac") {
                if controller.isViewer || !match.isSolo {
                    SwitchRow(title: "Player B’s Screen", isOn: Binding(get: { controller.isViewer }, set: controller.setViewer))
                        .disabled(!controller.isViewer && match.hasStarted && !match.isGameOver)
                }
                SwitchRow(title: "Frame Times", isOn: $showsFrameTimes)
            }
        }
        .padding(24)
        .frame(width: 300, alignment: .leading)
        .programmeCard()
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(Programme.title(10))
                    .tracking(1.6)
                    .foregroundStyle(Programme.navy)
                Rectangle()
                    .fill(Programme.navy.opacity(0.35))
                    .frame(height: 1)
            }
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Programme.ink.opacity(0.12))
                            .frame(height: 1)
                    }
                    row
                }
            }
        }
    }
}

private struct ActionRow: View {
    let title: String
    var detail: String?
    var stub: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Programme.body(14))
                Spacer()
                if let detail {
                    Text(detail)
                        .font(Programme.title(10))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
                if let stub {
                    Text(stub)
                        .font(Programme.title(10))
                        .tracking(0.8)
                        .foregroundStyle(isHovered && isEnabled ? Programme.paper : Programme.ink)
                        .frame(width: 72, height: 22)
                        .background(isHovered && isEnabled ? Programme.navy : .clear, in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Programme.ink.opacity(0.6), lineWidth: 1))
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(Programme.navy.opacity(isHovered && isEnabled ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovered = $0 }
        .padding(.horizontal, -6)
    }
}

private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(Programme.body(14))
                Spacer()
                HStack(spacing: 0) {
                    stub("ON", selected: isOn)
                    stub("OFF", selected: !isOn)
                }
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Programme.ink.opacity(0.6), lineWidth: 1))
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private func stub(_ word: String, selected: Bool) -> some View {
        Text(word)
            .font(Programme.title(10))
            .tracking(0.8)
            .foregroundStyle(selected ? Programme.paper : Programme.ink.opacity(0.45))
            .frame(width: 36, height: 22)
            .background(selected ? Programme.navy : .clear)
    }
}

private struct CameraChoice: View {
    @Binding var selection: CameraView

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(CameraView.allCases.enumerated()), id: \.element) { index, camera in
                if index > 0 {
                    Rectangle()
                        .fill(Programme.ink.opacity(0.6))
                        .frame(width: 1)
                }
                Button {
                    selection = camera
                } label: {
                    Text(camera.shortTitle.uppercased())
                        .font(Programme.title(10))
                        .tracking(0.8)
                        .foregroundStyle(selection == camera ? Programme.paper : Programme.ink)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(selection == camera ? Programme.navy : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == camera ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Programme.ink.opacity(0.6), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

private extension CameraView {
    var shortTitle: String {
        switch self {
        case .playerAEnd: "A’s End"
        case .playerBEnd: "B’s End"
        case .split: "Split"
        }
    }
}
