import AppKit
import TaviCore

final class PreferencesWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private enum Metrics {
        static let windowSize = NSSize(width: 720, height: 560)
        static let minimumWindowSize = NSSize(width: 640, height: 500)
        /// Large enough for the Keyboard Settings recording to stay readable.
        static let setupWindowSize = NSSize(width: 900, height: 640)
        static let sidebarWidth: CGFloat = 168
        static let contentInset: CGFloat = 24
        static let sectionSpacing: CGFloat = 16
        static let controlSpacing: CGFloat = 8
        static let compactSpacing: CGFloat = 4
        static let panelRadius: CGFloat = 16
        static let controlRadius: CGFloat = 8
    }

    private enum Section: Int, CaseIterable {
        case overview
        case words
        case settings

        var title: String {
            switch self {
            case .overview: return "시작하기"
            case .words: return "내 단어"
            case .settings: return "설정"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .overview: return "개요"
            case .words: return "나의 단어"
            case .settings: return "설정"
            }
        }
    }

    private let store: LearningStore
    private let onEnabled: (Bool) -> Void
    private let onLearning: (Bool) -> Void
    private let onInputSettings: () -> Void
    private let onRemoveInputMethod: () -> Void

    private let mainView = NSView()
    private let sectionContainer = NSView()
    private var sectionButtons: [NSButton] = []
    private var activeSection: Section = .overview
    private var tutorial = TutorialProgress(
        completed: InputMethodRuntime.preferences.bool(forKey: "tutorialCompleted")
    )
    private let tutorialTitle = NSTextField(labelWithString: "")
    private let tutorialPrompt = NSTextField(wrappingLabelWithString: "")
    private let tutorialCounter = NSTextField(labelWithString: "")
    private let tutorialNext = NSButton()
    private let tutorialSkip = NSButton()
    private let tutorialReplay = NSButton()

    private let editorErrorLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var inlineEditor = InlineEditor(store: store) { [weak self] message in
        self?.editorErrorLabel.stringValue = message ?? ""
        self?.editorErrorLabel.isHidden = message == nil
        self?.reloadWords()
    }
    private let wordsTable = WordTableView(frame: .zero)
    private let rawField = NSTextField()
    private let preferredField = NSTextField()
    private let wordsErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let enabledSwitch = NSSwitch()
    private let learningSwitch = NSSwitch()
    private let inputStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let setupView: InputMethodSetupView
    private(set) var isShowingSetup = false

    init(
        store: LearningStore,
        onEnabled: @escaping (Bool) -> Void,
        onLearning: @escaping (Bool) -> Void,
        onInputSettings: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onOpenApplications: @escaping () -> Void,
        onRemoveInputMethod: @escaping () -> Void
    ) {
        self.store = store
        self.onEnabled = onEnabled
        self.onLearning = onLearning
        self.onInputSettings = onInputSettings
        self.onRemoveInputMethod = onRemoveInputMethod
        setupView = InputMethodSetupView(onStart: onStart, onOpenApplications: onOpenApplications)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tavi"
        window.minSize = Metrics.minimumWindowSize
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = NSView()

        super.init(window: window)
        window.delegate = self
        buildInterface()
        show(section: .overview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func refresh(enabled: Bool, learning: Bool, status: String) {
        enabledSwitch.state = enabled ? .on : .off
        learningSwitch.state = learning ? .on : .off
        inputStatusLabel.stringValue = status
        inlineEditor.learning = learning
        inlineEditor.assistanceEnabled = enabled
        reloadWords()
        updatePlayground()
    }

    /// Until Tavi is in the user's input sources the window is only the setup page;
    /// once it is, the window turns into the regular sidebar layout on the tutorial.
    func refreshSetup(_ state: InputMethodSetupState) {
        setupView.refresh(state)
        let setup = state != .ready
        guard setup != isShowingSetup else { return }
        isShowingSetup = setup
        setupView.isHidden = !setup
        mainView.isHidden = setup
        if setup {
            resize(to: Metrics.setupWindowSize, growOnly: true)
            setupView.play()
        } else {
            setupView.stop()
            resize(to: Metrics.windowSize, growOnly: false)
            show(section: .overview)
        }
    }

    private func resize(to size: NSSize, growOnly: Bool) {
        guard let window else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        if growOnly {
            frame.size.width = max(frame.width, window.frame.width)
            frame.size.height = max(frame.height, window.frame.height)
        }
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(window.constrainFrameRect(frame, to: window.screen ?? NSScreen.main), display: true)
    }

    func showTutorial() {
        show(section: .overview)
        restartTutorial()
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let sidebar = makeSidebar()
        sectionContainer.translatesAutoresizingMaskIntoConstraints = false

        mainView.addSubview(sidebar)
        mainView.addSubview(sectionContainer)
        setupView.isHidden = true
        for view in [mainView, setupView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                view.topAnchor.constraint(equalTo: contentView.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: mainView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth),

            sectionContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sectionContainer.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            sectionContainer.topAnchor.constraint(equalTo: mainView.topAnchor),
            sectionContainer.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
        ])
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active

        let appTitle = NSTextField(labelWithString: "Tavi")
        appTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        appTitle.textColor = .labelColor
        appTitle.setAccessibilityLabel("Tavi 설정")

        let navigation = NSStackView()
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = Metrics.compactSpacing
        navigation.distribution = .fill

        sectionButtons = Section.allCases.map { section in
            let button = NSButton(title: section.title, target: self, action: #selector(selectSection(_:)))
            button.tag = section.rawValue
            button.bezelStyle = .recessed
            button.controlSize = .large
            button.font = .systemFont(ofSize: 14, weight: .medium)
            button.alignment = .left
            button.setButtonType(.toggle)
            button.setAccessibilityLabel(section.accessibilityLabel)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth - Metrics.contentInset).isActive = true
            navigation.addArrangedSubview(button)
            return button
        }

        let stack = NSStackView(views: [appTitle, navigation])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.sectionSpacing
        stack.setCustomSpacing(Metrics.contentInset, after: appTitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Metrics.sectionSpacing),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -Metrics.controlSpacing),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: Metrics.contentInset),
        ])
        return sidebar
    }

    @objc private func selectSection(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        show(section: section)
    }

    private func show(section: Section) {
        activeSection = section
        sectionButtons.forEach { $0.state = $0.tag == section.rawValue ? .on : .off }
        sectionContainer.subviews.forEach { $0.removeFromSuperview() }

        let view: NSView
        switch section {
        case .overview: view = makeOverview()
        case .words: view = makeWords()
        case .settings: view = makeSettings()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        sectionContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: sectionContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: sectionContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: sectionContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: sectionContainer.bottomAnchor),
        ])
        if section == .overview {
            window?.initialFirstResponder = inlineEditor
            window?.makeFirstResponder(inlineEditor)
        }
    }

    private func makeOverview() -> NSView {
        let playground = makePanel()

        let editorScroll = InlineEditorScrollView()
        editorScroll.documentView = inlineEditor
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .bezelBorder
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorErrorLabel.font = .systemFont(ofSize: 12)
        editorErrorLabel.textColor = .systemRed
        editorErrorLabel.isHidden = true
        let playgroundStack = NSStackView(
            views: [editorScroll, editorErrorLabel]
        )
        playgroundStack.orientation = .vertical
        playgroundStack.alignment = .leading
        playgroundStack.spacing = Metrics.controlSpacing
        playgroundStack.translatesAutoresizingMaskIntoConstraints = false
        playground.addSubview(playgroundStack)

        NSLayoutConstraint.activate([
            playgroundStack.leadingAnchor.constraint(equalTo: playground.leadingAnchor, constant: Metrics.sectionSpacing),
            playgroundStack.trailingAnchor.constraint(equalTo: playground.trailingAnchor, constant: -Metrics.sectionSpacing),
            playgroundStack.topAnchor.constraint(equalTo: playground.topAnchor, constant: Metrics.sectionSpacing),
            playgroundStack.bottomAnchor.constraint(lessThanOrEqualTo: playground.bottomAnchor, constant: -Metrics.sectionSpacing),
            editorScroll.widthAnchor.constraint(equalTo: playgroundStack.widthAnchor),
            editorScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        tutorialTitle.font = .systemFont(ofSize: 30, weight: .semibold)
        tutorialPrompt.font = .systemFont(ofSize: 15)
        tutorialCounter.font = .systemFont(ofSize: 12, weight: .medium)
        tutorialCounter.textColor = .secondaryLabelColor
        tutorialNext.title = "다음"
        tutorialNext.bezelStyle = .rounded
        tutorialNext.target = self
        tutorialNext.action = #selector(nextTutorialStep)
        tutorialSkip.title = "건너뛰기"
        tutorialSkip.bezelStyle = .rounded
        tutorialSkip.target = self
        tutorialSkip.action = #selector(skipTutorial)
        tutorialReplay.title = "튜토리얼 다시 보기"
        tutorialReplay.bezelStyle = .rounded
        tutorialReplay.target = self
        tutorialReplay.action = #selector(restartTutorial)
        inlineEditor.onComposition = { [weak self] raw, text in
            self?.tutorial.composed(raw: raw, text: text)
            self?.updateTutorial()
        }
        inlineEditor.onCorrection = { [weak self] raw, before, after in
            self?.tutorial.corrected(raw: raw, before: before, after: after)
            self?.updateTutorial()
        }
        inlineEditor.onLearned = { [weak self] word in
            self?.tutorial.learned(word)
            self?.updateTutorial()
            self?.reloadWords()
        }
        let actions = NSStackView(views: [tutorialNext, tutorialSkip, tutorialReplay])
        actions.spacing = 8
        updateTutorial()
        return makePage(views: [tutorialCounter, tutorialTitle, tutorialPrompt, playground, actions])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if isShowingSetup {
            setupView.play()
        } else if activeSection == .overview {
            window?.makeFirstResponder(inlineEditor)
        }
    }

    private func updateTutorial() {
        let finished = tutorial.step == .finished
        tutorialCounter.isHidden = finished
        tutorialPrompt.isHidden = finished
        tutorialNext.isHidden = finished
        tutorialSkip.isHidden = finished
        tutorialReplay.isHidden = !finished
        tutorialNext.isEnabled = tutorial.canAdvance
        tutorialNext.title = tutorial.step == .learning ? "시작하기" : "다음"
        tutorialCounter.stringValue = "\(tutorial.step.rawValue + 1) / 3"
        switch tutorial.step {
        case .typing:
            tutorialTitle.stringValue = "입력 소스는 그대로."
            tutorialPrompt.stringValue = "APIfmf를 입력해 보세요."
        case .correction:
            tutorialTitle.stringValue = "원하는 표기로 바꾸기."
            tutorialPrompt.stringValue = "to를 입력하고 \(LanguageKey.name)를 눌러 보세요."
        case .learning:
            tutorialTitle.stringValue = "쓰는 대로, 기억해요."
            if let text = tutorial.learnedText {
                tutorialPrompt.stringValue = "\(text) · \(tutorial.confirmations)/3\n같은 표기를 입력하고 Space로 확정해 보세요."
            } else {
                tutorialPrompt.stringValue = "닉네임을 세 번, 각각 Space로 확정해 보세요.\n예: 3Xhaust"
            }
        case .finished:
            tutorialTitle.stringValue = "그냥, 쓰세요."
        }
    }

    @objc private func nextTutorialStep() {
        guard tutorial.canAdvance else { return }
        inlineEditor.finish(learn: false)
        tutorial.advance()
        if tutorial.step == .finished {
            InputMethodRuntime.preferences.set(true, forKey: "tutorialCompleted")
        } else {
            inlineEditor.string = ""
            inlineEditor.undoManager?.removeAllActions()
        }
        updateTutorial()
        window?.makeFirstResponder(inlineEditor)
    }

    @objc private func skipTutorial() {
        tutorial.skip()
        InputMethodRuntime.preferences.set(true, forKey: "tutorialCompleted")
        updateTutorial()
        window?.makeFirstResponder(inlineEditor)
    }

    @objc private func restartTutorial() {
        inlineEditor.finish(learn: false)
        tutorial.restart()
        InputMethodRuntime.preferences.set(false, forKey: "tutorialCompleted")
        inlineEditor.string = ""
        inlineEditor.undoManager?.removeAllActions()
        updateTutorial()
        window?.makeFirstResponder(inlineEditor)
    }

    private func makeWords() -> NSView {
        let title = makeTitle("내 단어")

        if wordsTable.tableColumns.isEmpty {
            let columns: [(String, String, CGFloat)] = [
                ("raw", "입력한 키", 140),
                ("text", "원하는 표기", 200),
                ("confirmations", "반복", 95),
            ]
            for (identifier, label, width) in columns {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
                column.title = label
                column.width = width
                column.minWidth = 80
                wordsTable.addTableColumn(column)
            }
            wordsTable.headerView = NSTableHeaderView()
            wordsTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            wordsTable.usesAlternatingRowBackgroundColors = true
            wordsTable.allowsEmptySelection = true
            wordsTable.delegate = self
            wordsTable.dataSource = self
            wordsTable.setAccessibilityLabel("저장된 나의 단어")
            wordsTable.toolTip = "Shift+클릭: 범위 선택 · ⌘/Ctrl+클릭: 개별 선택 · ⌘A: 전체 선택"
        }

        let scrollView = NSScrollView()
        scrollView.documentView = wordsTable
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true

        rawField.placeholderString = "영문 키 순서 · 예: dkssud"
        rawField.setAccessibilityLabel("영문 키 시퀀스")
        preferredField.placeholderString = "기억할 표기"
        preferredField.setAccessibilityLabel("원하는 정확한 표기")

        let fields = NSGridView(views: [
            [makeMetadata("입력"), rawField],
            [makeMetadata("표기"), preferredField],
        ])
        fields.rowSpacing = Metrics.controlSpacing
        fields.columnSpacing = Metrics.sectionSpacing
        fields.column(at: 0).xPlacement = .trailing
        fields.column(at: 1).xPlacement = .fill

        let saveButton = NSButton(title: "저장", target: self, action: #selector(saveWord))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.setAccessibilityLabel("단어 추가 또는 업데이트")

        let removeButton = NSButton(title: "선택한 단어 삭제", target: self, action: #selector(removeWord))
        removeButton.bezelStyle = .rounded
        removeButton.setAccessibilityLabel("선택한 단어 삭제")

        let actions = NSStackView(views: [saveButton, removeButton])
        actions.orientation = .horizontal
        actions.spacing = Metrics.controlSpacing

        wordsErrorLabel.font = .systemFont(ofSize: 12)
        wordsErrorLabel.textColor = .systemRed
        wordsErrorLabel.isHidden = true
        wordsErrorLabel.setAccessibilityLabel("개인 사전 오류")

        let page = makePage(views: [title, scrollView, fields, actions, wordsErrorLabel])
        reloadWords()
        return page
    }

    private func makeSettings() -> NSView {
        let title = makeTitle("설정")

        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged)
        enabledSwitch.setAccessibilityLabel("자동 한영 입력")

        learningSwitch.target = self
        learningSwitch.action = #selector(learningChanged)
        learningSwitch.setAccessibilityLabel("내 입력에서 자동 학습")

        let enabledRow = makeSwitchRow(title: "자동 한영 입력", control: enabledSwitch)
        let learningRow = makeSwitchRow(
            title: "내 입력에서 자동으로 배우기",
            control: learningSwitch
        )
        let switches = NSStackView(views: [enabledRow, learningRow])
        switches.orientation = .vertical
        switches.alignment = .leading
        switches.spacing = Metrics.sectionSpacing

        let inputPanel = makePanel()
        let inputTitle = makeSectionTitle("입력 소스")
        inputStatusLabel.font = .systemFont(ofSize: 12)
        inputStatusLabel.textColor = .secondaryLabelColor
        inputStatusLabel.setAccessibilityLabel("Tavi 입력 소스 상태")

        let inputButton = NSButton(
            title: "입력 소스 설정 열기…",
            target: self,
            action: #selector(openInputSettings)
        )
        inputButton.bezelStyle = .rounded
        inputButton.setAccessibilityLabel("키보드 입력 소스 설정 열기")

        let removeButton = NSButton(
            title: "입력기 제거…",
            target: self,
            action: #selector(removeInputMethod)
        )
        removeButton.bezelStyle = .rounded
        removeButton.setAccessibilityLabel("Tavi 입력기 제거")

        let inputActions = NSStackView(views: [inputButton, removeButton])
        inputActions.orientation = .horizontal
        inputActions.spacing = Metrics.controlSpacing

        let inputStack = NSStackView(views: [inputTitle, inputStatusLabel, inputActions])
        inputStack.orientation = .vertical
        inputStack.alignment = .leading
        inputStack.spacing = Metrics.controlSpacing
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        inputPanel.addSubview(inputStack)

        NSLayoutConstraint.activate([
            inputStack.leadingAnchor.constraint(equalTo: inputPanel.leadingAnchor, constant: Metrics.sectionSpacing),
            inputStack.trailingAnchor.constraint(equalTo: inputPanel.trailingAnchor, constant: -Metrics.sectionSpacing),
            inputStack.topAnchor.constraint(equalTo: inputPanel.topAnchor, constant: Metrics.sectionSpacing),
            inputStack.bottomAnchor.constraint(equalTo: inputPanel.bottomAnchor, constant: -Metrics.sectionSpacing),
        ])

        return makePage(views: [title, switches, inputPanel])
    }

    private func makePage(views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        views.forEach { view in
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if !(view is NSStackView) {
                view.translatesAutoresizingMaskIntoConstraints = false
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        let page = NSView()
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: Metrics.contentInset),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -Metrics.contentInset),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: Metrics.contentInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -Metrics.contentInset),
        ])
        return page
    }

    private func makePanel() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = Metrics.panelRadius
        return view
    }

    private func makeTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 32, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makeBody(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        return label
    }

    private func makeMetadata(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        return label
    }

    private func makeSwitchRow(title: String, control: NSSwitch) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = Metrics.sectionSpacing
        return row
    }

    private func updatePlayground() {
        inlineEditor.refreshWords()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.words.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < store.words.count, let tableColumn else { return nil }
        let word = store.words[row]
        let identifier = tableColumn.identifier
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        cell.identifier = identifier

        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Metrics.controlSpacing),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Metrics.controlSpacing),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        switch identifier.rawValue {
        case "raw": label.stringValue = word.raw
        case "text": label.stringValue = word.text
        case "confirmations":
            let established = word.confirmations >= LearningStore.threshold
            label.stringValue = established ? "\(word.confirmations)회" : "\(word.confirmations) / \(LearningStore.threshold)"
            label.toolTip = established ? "자동 교정에 적용 · 많이 쓸수록 우선해요" : "관찰 중 · 자동 교정에는 아직 적용하지 않아요"
        default: label.stringValue = ""
        }
        return cell
    }

    @objc private func wordSelectionChanged() {
        let row = wordsTable.selectedRow
        guard wordsTable.selectedRowIndexes.count == 1, row >= 0, row < store.words.count else {
            rawField.stringValue = ""
            preferredField.stringValue = ""
            return
        }
        let word = store.words[row]
        rawField.stringValue = word.raw
        preferredField.stringValue = word.text
        showWordsError(nil)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        wordSelectionChanged()
    }

    @objc private func saveWord() {
        do {
            try store.set(raw: rawField.stringValue, text: preferredField.stringValue)
            wordsTable.deselectAll(nil)
            rawField.stringValue = ""
            preferredField.stringValue = ""
            showWordsError(nil)
            reloadWords()
            updatePlayground()
        } catch {
            showWordsError(error)
        }
    }

    @objc private func removeWord() {
        let indexes = wordsTable.selectedRowIndexes
        let keys = Set(store.words.enumerated().filter { indexes.contains($0.offset) }.map { $0.element.raw })
        guard !keys.isEmpty else {
            showWordsErrorMessage("삭제할 단어를 먼저 선택해 주세요.")
            return
        }

        do {
            try store.remove(rawKeys: keys)
            wordsTable.deselectAll(nil)
            rawField.stringValue = ""
            preferredField.stringValue = ""
            showWordsError(nil)
            reloadWords()
            updatePlayground()
        } catch {
            showWordsError(error)
        }
    }

    private func reloadWords() {
        wordsTable.reloadData()
    }

    private func showWordsError(_ error: Error?) {
        showWordsErrorMessage(error?.localizedDescription)
    }

    private func showWordsErrorMessage(_ message: String?) {
        wordsErrorLabel.stringValue = message ?? ""
        wordsErrorLabel.isHidden = message == nil
        if let message {
            NSAccessibility.post(element: wordsErrorLabel, notification: .announcementRequested, userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }

    @objc private func enabledChanged() {
        onEnabled(enabledSwitch.state == .on)
    }

    @objc private func learningChanged() {
        onLearning(learningSwitch.state == .on)
    }

    @objc private func openInputSettings() {
        onInputSettings()
    }

    @objc private func removeInputMethod() {
        onRemoveInputMethod()
    }

    func windowWillClose(_ notification: Notification) {
        setupView.stop()
    }
}
