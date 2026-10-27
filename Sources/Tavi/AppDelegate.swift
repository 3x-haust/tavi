import AppKit
import Carbon
import TaviCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = InputMethodRuntime.shared
    private let installer = InputMethodInstaller()
    private var item: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var statusItem: NSMenuItem?
    private var preferences: PreferencesWindow?
    private var observers: [NSObjectProtocol] = []
    private var sourceObserver: NSObjectProtocol?
    private var enabledSourcesObserver: NSObjectProtocol?
    private var preferencesObserver: NSObjectProtocol?
    private var updateObserver: NSObjectProtocol?
    /// Opened by the input method only to update; no window, menu bar item or Dock icon.
    private let background = CommandLine.arguments.contains(Updater.backgroundArgument)
    /// An update of an already added Tavi shows nothing until it is done.
    private var updatingQuietly = false
    private var updatingApp = false

    /// A Tavi the user already added keeps its normal window while its component updates.
    private var displayedState: InputMethodSetupState {
        updatingQuietly || (installer.state == .updateAvailable && InputSourceSetup.isAdded)
            ? .ready : installer.state
    }

    private var status: String {
        if let error = runtime.error { return error }
        guard installer.state == .ready else { return "Tavi 앱에서 Tavi를 추가해 주세요" }
        guard InputSourceSetup.isSelected else { return "입력 소스에서 Tavi를 선택해 주세요" }
        return runtime.enabled ? "Tavi · 자동 한영 입력" : "Tavi · 영문 그대로 입력"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !background {
            installEditingMenu()
            installStatusMenu()
        }
        installer.changed = { [weak self] state in
            guard let self else { return }
            if self.updatingQuietly {
                if case .working = state { return }
                self.updatingQuietly = false
                // After the installer has settled, which can still be inside this callback.
                if self.background { DispatchQueue.main.async { NSApp.terminate(nil) }; return }
            }
            let finishing = state == .ready && self.preferences?.isShowingSetup == true
            self.preferences?.refreshSetup(self.displayedState)
            self.refresh()
            if finishing { self.showPreferences() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: InputMethodRuntime.changed, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        sourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.installer.refresh()
                self?.refresh()
            }
        }
        // Adding Tavi in Keyboard Settings finishes setup: select it and bring Tavi back.
        enabledSourcesObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.installer.state == .needsSelection, InputSourceSetup.isAdded else { return }
                Task { await self.installer.select() }
            }
        }
        updateObserver = DistributedNotificationCenter.default().addObserver(
            forName: Updater.available, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateApp() } }
        installer.refresh()
        if !background { showPreferences() }
        updateApp()
    }

    /// A newer release replaces the app first, since the component is copied out of it;
    /// the relaunched app then updates the component.
    private func updateApp() {
        guard !updatingApp else { return }
        updatingApp = true
        Task {
            let quiet = background || preferences?.window?.isVisible != true
            if await Updater.replaceAppIfNewer(background: quiet) {
                NSApp.terminate(nil)
                return
            }
            updatingApp = false
            updateComponentQuietly()
            if background, !updatingQuietly { NSApp.terminate(nil) }
        }
    }

    private func updateComponentQuietly() {
        guard installer.state == .updateAvailable, InputSourceSetup.isAdded else { return }
        updatingQuietly = true
        Task { await installer.update() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let sourceObserver { DistributedNotificationCenter.default().removeObserver(sourceObserver) }
        if let enabledSourcesObserver { DistributedNotificationCenter.default().removeObserver(enabledSourcesObserver) }
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        if let updateObserver { DistributedNotificationCenter.default().removeObserver(updateObserver) }
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        installer.isWorking ? .terminateCancel : .terminateNow
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Tavi"
        item.button?.setAccessibilityLabel("Tavi")
        self.item = item
        let menu = NSMenu()
        let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusItem = statusItem
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle
        for (title, action) in [
            ("Tavi 입력 소스 선택", #selector(selectInputSource)),
            ("설정과 내 단어…", #selector(showPreferences)),
            ("튜토리얼…", #selector(showTutorial)),
            ("키보드 설정 열기…", #selector(openInputSettings)),
        ] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Tavi 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    private func refresh() {
        statusItem?.title = status
        toggleItem?.title = runtime.enabled ? "자동 한영 끄기" : "자동 한영 켜기"
        item?.button?.toolTip = status
        preferences?.refresh(enabled: runtime.enabled, learning: runtime.learning, status: status)
    }

    @objc private func toggleEnabled() { runtime.enabled.toggle() }

    @objc private func selectInputSource() {
        installer.refresh()
        guard installer.state == .ready else { showPreferences(); return }
        Task { await installer.select() }
    }

    @objc private func openInputSettings() { InputSourceSetup.openSettings() }

    private func startSetup() {
        Task { await installer.start() }
    }

    private func openApplications() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Applications")
    }

    private func removeInputMethod() {
        let alert = NSAlert()
        alert.messageText = "Tavi 입력기를 제거할까요?"
        alert.informativeText = "개인 사전과 설정은 그대로 남습니다. Tavi 앱에서 다시 설치할 수 있어요."
        alert.addButton(withTitle: "입력기 제거")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await installer.remove() }
    }

    @objc private func showTutorial() {
        showPreferences()
        preferences?.showTutorial()
    }

    @objc private func showPreferences() {
        runtime.reloadWords()
        guard let store = runtime.store else {
            let alert = NSAlert()
            alert.messageText = "개인 사전을 열 수 없어요"
            alert.informativeText = runtime.error ?? ""
            alert.runModal()
            return
        }
        if preferences == nil {
            preferences = PreferencesWindow(
                store: store,
                onEnabled: { [weak self] in self?.runtime.enabled = $0 },
                onLearning: { [weak self] in self?.runtime.learning = $0 },
                onInputSettings: { InputSourceSetup.openSettings() },
                onStart: { [weak self] in self?.startSetup() },
                onOpenApplications: { [weak self] in self?.openApplications() },
                onRemoveInputMethod: { [weak self] in self?.removeInputMethod() }
            )
            preferencesObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: preferences?.window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.preferences = nil
                    if let observer = self?.preferencesObserver { NotificationCenter.default.removeObserver(observer) }
                    self?.preferencesObserver = nil
                }
            }
        }
        installer.refresh()
        preferences?.refreshSetup(displayedState)
        refresh()
        preferences?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installEditingMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Tavi 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: #selector(undoEditing), keyEquivalent: "z").target = self
        let redo = edit.addItem(withTitle: "다시 실행", action: #selector(redoEditing), keyEquivalent: "z")
        redo.target = self
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func undoEditing() {
        let responder = NSApp.keyWindow?.firstResponder
        (responder as? InlineEditor)?.finish(learn: false)
        responder?.undoManager?.undo()
    }

    @objc private func redoEditing() {
        let responder = NSApp.keyWindow?.firstResponder
        (responder as? InlineEditor)?.finish(learn: false)
        responder?.undoManager?.redo()
    }
}
