import AppKit
import AVFoundation
import AVKit

/// First-run page: the Keyboard Settings recording plays inline while one button
/// prepares Tavi and opens Keyboard Settings, where the user adds Tavi once.
final class InputMethodSetupView: NSView {
    private enum Metrics {
        static let contentInset: CGFloat = 24
        static let columnWidth: CGFloat = 240
        static let sectionSpacing: CGFloat = 16
        static let controlSpacing: CGFloat = 8
        static let panelRadius: CGFloat = 16
    }

    private static let steps = ["키보드 설정 열기", "입력 소스의 편집…", "+ → 한국어 → Tavi → 추가"]

    private let onStart: () -> Void
    private let onOpenApplications: () -> Void

    private let titleLabel = NSTextField(labelWithString: "Tavi 추가하기")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let primaryButton = NSButton()
    private let playerView = AVPlayerView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var state: InputMethodSetupState = .notInstalled

    init(onStart: @escaping () -> Void, onOpenApplications: @escaping () -> Void) {
        self.onStart = onStart
        self.onOpenApplications = onOpenApplications
        super.init(frame: .zero)
        buildInterface()
        refresh(.notInstalled)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(_ state: InputMethodSetupState) {
        self.state = state

        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        errorLabel.isHidden = true
        primaryButton.isEnabled = true
        messageLabel.stringValue = ""

        switch state {
        case .moveToApplications:
            messageLabel.stringValue = "Tavi.app을 응용 프로그램 폴더로 옮긴 뒤 다시 열어 주세요."
            primaryButton.title = "응용 프로그램 폴더 열기"
        case .notInstalled:
            primaryButton.title = "키보드 설정 열기"
        case .updateAvailable:
            messageLabel.stringValue = "새 버전의 Tavi 입력기가 있어요."
            primaryButton.title = "업데이트"
        case let .working(message):
            messageLabel.stringValue = message
            primaryButton.title = "키보드 설정 열기"
            primaryButton.isEnabled = false
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        case .needsSelection:
            messageLabel.stringValue = "Tavi를 추가하면 바로 이어져요."
            primaryButton.title = "키보드 설정 열기"
        case .ready:
            messageLabel.stringValue = "Tavi가 추가되었어요."
            primaryButton.title = "시작하기"
        case let .failed(message):
            messageLabel.stringValue = "준비하지 못했어요."
            errorLabel.stringValue = message
            errorLabel.toolTip = message
            errorLabel.isHidden = false
            primaryButton.title = "다시 시도"
        }
        messageLabel.isHidden = messageLabel.stringValue.isEmpty
    }

    func play() {
        guard player == nil, let url = Bundle.main.url(forResource: "setup-guide", withExtension: "mp4") else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        self.player = player
        playerView.player = player
        player.play()
    }

    func stop() {
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        playerView.player = nil
        player = nil
    }

    private func buildInterface() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        titleLabel.textColor = .labelColor

        let steps = NSStackView(views: Self.steps.enumerated().map { makeStep($0.offset + 1, $0.element) })
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = Metrics.sectionSpacing
        steps.setAccessibilityLabel("Tavi 추가 순서")

        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 6
        errorLabel.setAccessibilityLabel("Tavi 준비 오류")

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.setAccessibilityLabel("Tavi 준비 중")

        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .large
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(performPrimaryAction)

        let statusRow = NSStackView(views: [progressIndicator, messageLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = Metrics.controlSpacing

        let column = NSStackView(views: [titleLabel, steps, primaryButton, statusRow, errorLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = Metrics.controlSpacing
        column.setCustomSpacing(Metrics.contentInset, after: titleLabel)
        column.setCustomSpacing(Metrics.contentInset, after: steps)
        column.setCustomSpacing(Metrics.sectionSpacing, after: primaryButton)
        column.translatesAutoresizingMaskIntoConstraints = false
        [messageLabel, errorLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.columnWidth).isActive = true
        }

        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.setAccessibilityLabel("키보드 설정에서 Tavi를 추가하는 영상")
        let video = NSView()
        video.wantsLayer = true
        video.layer?.backgroundColor = NSColor.black.cgColor
        video.layer?.cornerRadius = Metrics.panelRadius
        video.layer?.masksToBounds = true
        video.translatesAutoresizingMaskIntoConstraints = false
        playerView.translatesAutoresizingMaskIntoConstraints = false
        video.addSubview(playerView)

        addSubview(column)
        addSubview(video)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentInset),
            column.widthAnchor.constraint(equalToConstant: Metrics.columnWidth),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Metrics.contentInset),

            video.leadingAnchor.constraint(equalTo: column.trailingAnchor, constant: Metrics.contentInset),
            video.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.contentInset),
            video.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.contentInset),
            video.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.contentInset),
            playerView.leadingAnchor.constraint(equalTo: video.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: video.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: video.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: video.bottomAnchor),
        ])
    }

    private func makeStep(_ number: Int, _ text: String) -> NSView {
        let digit = NSTextField(labelWithString: "\(number)")
        digit.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        digit.textColor = .white
        digit.translatesAutoresizingMaskIntoConstraints = false
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        badge.layer?.cornerRadius = 10
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(digit)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
            digit.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            digit.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .labelColor
        let row = NSStackView(views: [badge, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    @objc private func performPrimaryAction() {
        switch state {
        case .moveToApplications: onOpenApplications()
        case .working: break
        default: onStart()
        }
    }
}
