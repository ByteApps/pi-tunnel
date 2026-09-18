import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigStore()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var timerInterval: Double = 0
    private var lastResult: ProbeResult?
    private var probing = false
    private var menuIsOpen = false

    private let showCountKey = "showCount"
    private var showCount: Bool {
        get { UserDefaults.standard.bool(forKey: showCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: showCountKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.ensureExists()
        store.reloadIfChanged()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        updateStatusItem()
        rebuildMenu()
        restartTimerIfNeeded()
        probe()
        if CommandLine.arguments.contains("--edit-ports") { editPorts() }
    }

    // MARK: polling

    private func restartTimerIfNeeded() {
        let interval = max(store.config.intervalSeconds, 1)
        guard interval != timerInterval else { return }
        timerInterval = interval
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.probe() }
        timer?.tolerance = interval * 0.2
    }

    @objc private func probe() {
        if store.reloadIfChanged() { restartTimerIfNeeded() }
        guard !probing else { return }
        probing = true
        let ports = store.config.allPorts.map { $0.port }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = PortProbe.probe(ports: ports)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.probing = false
                self.lastResult = result
                self.updateStatusItem()
                self.rebuildMenu()
            }
        }
    }

    private var openCount: Int { lastResult?.openCount() ?? 0 }
    private var totalCount: Int { store.config.allPorts.count }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = TunnelIcon.image(total: totalCount, open: openCount)
        button.title = showCount ? " \(openCount)/\(totalCount)" : ""
        button.toolTip = "Pi tunnel: \(openCount) of \(totalCount) ports open"
    }

    // MARK: menu

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        probe()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let cfg = store.config
        let states = lastResult?.states ?? [:]

        let header = NSMenuItem(title: "Raspberry Pi tunnel", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "Raspberry Pi tunnel",
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        menu.addItem(header)

        let subline: String
        if lastResult == nil {
            subline = "\(cfg.host) · checking…"
        } else {
            subline = "\(cfg.host) · \(openCount) of \(totalCount) ports open"
        }
        let sub = NSMenuItem(title: subline, action: nil, keyEquivalent: "")
        sub.isEnabled = false
        sub.attributedTitle = NSAttributedString(string: subline, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor])
        menu.addItem(sub)
        if let err = store.lastError {
            let e = NSMenuItem(title: err, action: nil, keyEquivalent: "")
            e.isEnabled = false
            e.attributedTitle = NSAttributedString(string: err, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.systemOrange])
            menu.addItem(e)
        }
        menu.addItem(.separator())

        for group in cfg.groups {
            menu.addItem(sectionHeader(group.name))
            for entry in group.ports {
                let state = states[entry.port] ?? .closed
                let item = NSMenuItem(title: "\(entry.port) \(entry.name)", action: #selector(portClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry
                item.image = TunnelIcon.dot(state)
                item.attributedTitle = portTitle(entry, state: state)
                item.toolTip = entry.url != nil ? "Open \(entry.url!)" : "Copy 127.0.0.1:\(entry.port)"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let missing = cfg.allPorts.map { $0.port }.filter { states[$0] != .open && states[$0] != .busy }
        let openItem = NSMenuItem(
            title: missing.isEmpty ? "All ports open" : "Open missing ports (\(missing.count))",
            action: #selector(openMissing), keyEquivalent: "o")
        openItem.target = self
        openItem.isEnabled = !missing.isEmpty && lastResult != nil
        menu.addItem(openItem)

        let pids = lastResult?.sshPIDs ?? []
        let closeItem = NSMenuItem(title: "Close all tunnels", action: #selector(closeAll), keyEquivalent: "")
        closeItem.target = self
        closeItem.isEnabled = !pids.isEmpty
        menu.addItem(closeItem)

        menu.addItem(.separator())
        let check = NSMenuItem(title: "Check now", action: #selector(checkNow), keyEquivalent: "r")
        check.target = self
        menu.addItem(check)

        let count = NSMenuItem(title: "Show count in menu bar", action: #selector(toggleCount), keyEquivalent: "")
        count.target = self
        count.state = showCount ? .on : .off
        menu.addItem(count)

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let edit = NSMenuItem(title: "Edit Ports…", action: #selector(editPorts), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())
        let more = NSMenuItem(title: "More from ByteApps…", action: #selector(openByteApps), keyEquivalent: "")
        more.target = self
        more.toolTip = "Open byteapps.com"
        menu.addItem(more)
        let quit = NSMenuItem(title: "Quit Pi Tunnel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor])
        return item
    }

    private func portTitle(_ entry: PortEntry, state: PortState) -> NSAttributedString {
        let size = NSFont.systemFontSize
        let s = NSMutableAttributedString()
        let portText = String(entry.port).padding(toLength: 6, withPad: " ", startingAt: 0)
        s.append(NSAttributedString(string: portText, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)]))
        s.append(NSAttributedString(string: entry.name, attributes: [
            .font: NSFont.menuFont(ofSize: size)]))
        let status: String
        switch state {
        case .open: status = "open"
        case .busy: status = "busy, not ssh"
        case .closed: status = "down"
        }
        s.append(NSAttributedString(string: "   \(status)", attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor]))
        return s
    }

    // MARK: actions

    @objc private func portClicked(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? PortEntry else { return }
        if let urlString = entry.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("127.0.0.1:\(entry.port)", forType: .string)
        }
    }

    @objc private func openMissing() {
        let states = lastResult?.states ?? [:]
        let cfg = store.config
        let missing = cfg.allPorts.map { $0.port }.filter { states[$0] != .open && states[$0] != .busy }
        guard !missing.isEmpty else { return }
        TunnelController.open(ports: missing, host: cfg.host) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error { self?.alert("Could not open the tunnel", error) }
                self?.probe()
            }
        }
    }

    @objc private func closeAll() {
        TunnelController.close(pids: lastResult?.sshPIDs ?? [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.probe() }
    }

    @objc private func checkNow() { probe() }

    @objc private func openByteApps() {
        NSWorkspace.shared.open(URL(string: "https://byteapps.com/")!)
    }

    @objc private func toggleCount() {
        showCount.toggle()
        updateStatusItem()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Launch at login", error.localizedDescription)
        }
        rebuildMenu()
    }

    private var portsEditor: PortsEditorWindowController?

    @objc private func editPorts() {
        store.ensureExists()
        store.reloadIfChanged()
        if portsEditor == nil {
            portsEditor = PortsEditorWindowController(store: store) { [weak self] in
                self?.restartTimerIfNeeded()
                self?.updateStatusItem()
                self?.rebuildMenu()
                self?.probe()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        portsEditor?.showWindow(nil)
        portsEditor?.window?.makeKeyAndOrderFront(nil)
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
