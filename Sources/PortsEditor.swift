import AppKit

/// A window for editing ~/.config/pi-tunnel/ports.json without touching the JSON:
/// host, check interval, and a table of ports (group, port, service, url) with
/// add/remove, Save/Cancel, and a button that opens the raw file.
final class PortsEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Validation {
        case ok(Config)
        case error(String)
    }

    struct Row {
        var group: String
        var port: String
        var name: String
        var url: String
    }

    private let store: ConfigStore
    private let onSave: () -> Void
    private var rows: [Row] = []

    private let hostField = NSTextField()
    private let intervalField = NSTextField()
    private let table = NSTableView()
    private let removeButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")

    init(store: ConfigStore, onSave: @escaping () -> Void) {
        self.store = store
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Pi Tunnel Ports"
        window.minSize = NSSize(width: 520, height: 340)
        window.center()
        super.init(window: window)
        buildUI()
        load()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: data

    private func load() {
        let cfg = store.config
        hostField.stringValue = cfg.host
        intervalField.stringValue = formatInterval(cfg.intervalSeconds)
        rows = cfg.groups.flatMap { g in
            g.ports.map { Row(group: g.name, port: String($0.port), name: $0.name, url: $0.url ?? "") }
        }
        table.reloadData()
        statusLabel.stringValue = "\(rows.count) port\(rows.count == 1 ? "" : "s") · \(ConfigStore.url.path)"
    }

    private func formatInterval(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    /// Validates the table and returns a Config, or an error message.
    private func buildConfig() -> Validation {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        if host.isEmpty { return .error("Host cannot be empty.") }
        guard let interval = Double(intervalField.stringValue.trimmingCharacters(in: .whitespaces)), interval >= 1 else {
            return .error("Check interval must be a number of seconds, 1 or more.")
        }
        var seen = Set<Int>()
        var order: [String] = []
        var grouped: [String: [PortEntry]] = [:]
        for (i, r) in rows.enumerated() {
            let group = r.group.trimmingCharacters(in: .whitespaces)
            let name = r.name.trimmingCharacters(in: .whitespaces)
            let url = r.url.trimmingCharacters(in: .whitespaces)
            guard let port = Int(r.port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else {
                return .error("Row \(i + 1): port must be a number between 1 and 65535.")
            }
            if group.isEmpty { return .error("Row \(i + 1): group cannot be empty.") }
            if name.isEmpty { return .error("Row \(i + 1): service name cannot be empty.") }
            if !seen.insert(port).inserted { return .error("Port \(port) is listed twice.") }
            if !url.isEmpty, URL(string: url)?.scheme == nil {
                return .error("Row \(i + 1): the URL should start with http:// or https://.")
            }
            if grouped[group] == nil { order.append(group); grouped[group] = [] }
            grouped[group]!.append(PortEntry(port: port, name: name, url: url.isEmpty ? nil : url))
        }
        if rows.isEmpty { return .error("Add at least one port.") }
        let groups = order.map { PortGroup(name: $0, ports: grouped[$0]!) }
        return .ok(Config(host: host, intervalSeconds: interval, groups: groups))
    }

    // MARK: actions

    @objc private func addRow() {
        commitPendingEdit()
        let group = rows.last?.group ?? "raspberrypi"
        rows.append(Row(group: group, port: "", name: "", url: ""))
        table.reloadData()
        let idx = rows.count - 1
        table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        table.scrollRowToVisible(idx)
        table.editColumn(1, row: idx, with: nil, select: true)
    }

    @objc private func removeRow() {
        commitPendingEdit()
        let idx = table.selectedRowIndexes
        guard !idx.isEmpty else { return }
        rows = rows.enumerated().filter { !idx.contains($0.offset) }.map { $0.element }
        table.reloadData()
        updateRemoveButton()
    }

    @objc private func save() {
        commitPendingEdit()
        switch buildConfig() {
        case .error(let message):
            let a = NSAlert()
            a.messageText = "Cannot save ports"
            a.informativeText = message
            a.alertStyle = .warning
            a.beginSheetModal(for: window!)
        case .ok(let cfg):
            do {
                try store.save(cfg)
                onSave()
                load()          // refresh the table from what was actually written
            } catch {
                let a = NSAlert()
                a.messageText = "Could not write ports.json"
                a.informativeText = error.localizedDescription
                a.alertStyle = .warning
                a.beginSheetModal(for: window!)
            }
        }
    }

    @objc private func cancel() {
        close()
    }

    @objc private func openJSON() {
        store.ensureExists()
        NSWorkspace.shared.open(ConfigStore.url)
    }

    @objc private func cellEdited(_ sender: NSTextField) {
        let row = table.row(for: sender)
        let col = table.column(for: sender)
        guard row >= 0, col >= 0 else { return }
        switch col {
        case 0: rows[row].group = sender.stringValue
        case 1: rows[row].port = sender.stringValue
        case 2: rows[row].name = sender.stringValue
        case 3: rows[row].url = sender.stringValue
        default: break
        }
    }

    /// Ends any in-progress cell edit so its value lands in `rows` before we act.
    private func commitPendingEdit() {
        window?.makeFirstResponder(table)
    }

    private func updateRemoveButton() {
        removeButton.isEnabled = !table.selectedRowIndexes.isEmpty
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let col = table.tableColumns.firstIndex(of: column) else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell\(col)")
        let field: NSTextField
        if let reused = table.makeView(withIdentifier: id, owner: nil) as? NSTextField {
            field = reused
        } else {
            field = NSTextField()
            field.identifier = id
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.lineBreakMode = .byTruncatingTail
            field.cell?.sendsActionOnEndEditing = true
            field.target = self
            field.action = #selector(cellEdited(_:))
            if col == 1 { field.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }
        }
        let r = rows[row]
        switch col {
        case 0: field.stringValue = r.group; field.placeholderString = "group"
        case 1: field.stringValue = r.port; field.placeholderString = "port"
        case 2: field.stringValue = r.name; field.placeholderString = "service"
        default: field.stringValue = r.url; field.placeholderString = "optional, opens in browser"
        }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateRemoveButton() }

    // MARK: layout

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let hostLabel = NSTextField(labelWithString: "SSH host:")
        hostField.placeholderString = "pi@raspberrypi.local"
        let intervalLabel = NSTextField(labelWithString: "Check every:")
        intervalField.alignment = .right
        intervalField.formatter = nil
        let secondsLabel = NSTextField(labelWithString: "seconds")

        let topRow = NSStackView(views: [hostLabel, hostField, intervalLabel, intervalField, secondsLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        hostField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        intervalField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let columns: [(String, String, CGFloat)] = [("Group", "group", 110), ("Port", "port", 70), ("Service", "name", 170), ("URL", "url", 190)]
        for (title, key, width) in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            c.title = title
            c.width = width
            c.minWidth = 50
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = NSTableHeaderView()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let addButton = NSButton(title: "+", target: self, action: #selector(addRow))
        addButton.bezelStyle = .smallSquare
        addButton.toolTip = "Add a port"
        removeButton.title = "−"
        removeButton.bezelStyle = .smallSquare
        removeButton.target = self
        removeButton.action = #selector(removeRow)
        removeButton.toolTip = "Remove the selected ports"
        removeButton.isEnabled = false
        addButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        removeButton.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let openJSON = NSButton(title: "Open JSON File…", target: self, action: #selector(openJSON))
        openJSON.bezelStyle = .rounded
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottomRow = NSStackView(views: [addButton, removeButton, openJSON, spacer, cancelButton, saveButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8

        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let hint = NSTextField(wrappingLabelWithString: "Click a cell to edit it. Ports in the same group are listed together in the menu. A row with a URL opens it in the browser when clicked; other rows copy 127.0.0.1:<port>.")
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [topRow, scroll, hint, bottomRow, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
}
