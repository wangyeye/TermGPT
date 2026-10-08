import AppKit
import Foundation

/// Recognize a fragmented ZRQINIT (remote sz) or ZRINIT (remote rz) header.
struct ZmodemDetector {
    private(set) var pending = Data()
    mutating func append(_ bytes: Data) -> (display: Data, direction: Bool?, protocolData: Data) {
        pending.append(bytes)
        let signatures = [Data([42, 42, 24, 66, 48, 48]), Data([42, 42, 24, 66, 48, 49])]
        let found = signatures.enumerated().compactMap { index, signature -> (Int, Range<Data.Index>)? in
            pending.range(of: signature).map { (index, $0) }
        }.min { $0.1.lowerBound < $1.1.lowerBound }
        if let found {
            let before = Data(pending[..<found.1.lowerBound]), stream = Data(pending[found.1.lowerBound...])
            pending.removeAll(); return (before, found.0 == 0, stream)
        }
        var held = 0
        for signature in signatures {
            for count in 1..<signature.count where pending.count >= count {
                if pending.suffix(count) == signature.prefix(count) { held = max(held, count) }
            }
        }
        let display = Data(pending.dropLast(held)); pending = Data(pending.suffix(held))
        return (display, nil, Data())
    }
}

final class ZmodemTransfer {
    weak var view: WorkTerminal?
    var changed: ((String, Bool) -> Void)?
    private var detector = ZmodemDetector()
    private(set) var active = false
    private var buffered = Data()
    private var helper: Process?
    private var input: Pipe?
    private var diagnostic = Data()
    private let io = DispatchQueue(label: "TermGPT.Zmodem.input")
    private var destination: URL?
    private var staging: URL?
    init(view: WorkTerminal) { self.view = view }
    func receive(_ bytes: Data) {
        if !active && helper != nil { view?.displayTerminalData(bytes); return }
        if active {
            if let input { write(bytes, to: input) }
            else {
                buffered.append(bytes)
                if buffered.count > 1024 * 1024 { cancel() }
            }
            return
        }
        let result = detector.append(bytes)
        if !result.display.isEmpty { view?.displayTerminalData(result.display) }
        if let downloading = result.direction {
            active = true; buffered = result.protocolData
            changed?(L("ZMODEM 等待选择文件…"), true)
            // Defer the modal UI so the PTY read callback has returned.
            DispatchQueue.main.async { [weak self] in self?.select(downloading: downloading) }
        }
    }
    private func select(downloading: Bool) {
        guard active, view?.process.running == true else { cancel(); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = downloading; panel.canChooseFiles = !downloading
        panel.allowsMultipleSelection = !downloading
        panel.message = L(downloading ? "选择 sz 下载文件的保存目录" : "选择上传给远端 rz 的文件")
        guard panel.runModal() == .OK, active else { cancel(); return }
        do {
            let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/" + (downloading ? "TermGPTRZ" : "TermGPTSZ"))
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw AppError.message("缺少 ZMODEM 组件，请使用完整安装包") }
            let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
            process.executableURL = executable
            if downloading {
                guard let folder = panel.url else { cancel(); return }
                destination = folder
                let temporary = folder.appendingPathComponent(".termgpt-zmodem-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                staging = temporary; process.currentDirectoryURL = temporary
                process.arguments = ["--restricted", "--rename", "--binary", "--verbose", "--verbose", "--syslog=off"]
            } else {
                process.arguments = ["--binary", "--escape", "--verbose", "--verbose", "--syslog=off", "--"] + panel.urls.map(\.path)
            }
            var env = ProcessInfo.processInfo.environment; env["LC_ALL"] = "C"; process.environment = env
            process.standardInput = input; process.standardOutput = output; process.standardError = errors
            self.input = input; helper = process
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty { DispatchQueue.main.async { self?.view?.process.send(data: Array(data)[...]) } }
            }
            errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                DispatchQueue.main.async {
                    guard let self, !data.isEmpty else { return }
                    self.diagnostic.append(data); self.diagnostic = Data(self.diagnostic.suffix(4096))
                    let text = String(decoding: self.diagnostic, as: UTF8.self).components(separatedBy: .newlines).last(where: { !$0.isEmpty }) ?? "ZMODEM"
                    self.changed?(String(text.suffix(200)), true)
                }
            }
            process.terminationHandler = { [weak self] process in
                output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { self?.finish(success: process.terminationStatus == 0) }
            }
            try process.run()
            let waiting = buffered; buffered.removeAll(); write(waiting, to: input)
            changed?(L(downloading ? "ZMODEM 正在下载…" : "ZMODEM 正在上传…"), true)
        } catch { cancel(); changed?(error.localizedDescription, false) }
    }
    private func write(_ data: Data, to input: Pipe) {
        io.async { [weak self] in
            do { try input.fileHandleForWriting.write(contentsOf: data) }
            catch { DispatchQueue.main.async { self?.cancel() } }
        }
    }
    func cancel() {
        guard active else { return }
        active = false
        // Standard ZMODEM cancel sequence; do not inject a shell command or Ctrl-C.
        view?.process.send(data: Array(repeating: UInt8(24), count: 8)[...])
        if helper?.isRunning == true { helper?.terminate() }
        else { cleanup() }
        changed?(L("ZMODEM 传输已取消"), false)
    }
    private func finish(success: Bool) {
        guard active else { cleanup(); return }
        do {
            if success, let staging, let destination {
                // Receive into a fresh directory, then move only regular files.
                // Existing local filenames are never replaced silently.
                for file in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    var target = destination.appendingPathComponent(file.lastPathComponent), suffix = 1
                    while FileManager.default.fileExists(atPath: target.path) {
                        target = destination.appendingPathComponent(file.lastPathComponent + "." + String(suffix)); suffix += 1
                    }
                    try FileManager.default.moveItem(at: file, to: target)
                }
            }
            changed?(success ? L("ZMODEM 传输完成") : L("ZMODEM 传输失败：%@", String(decoding: diagnostic, as: UTF8.self)), false)
        } catch { changed?(error.localizedDescription, false) }
        active = false; cleanup()
    }
    private func cleanup() {
        helper = nil; input = nil; buffered.removeAll(); diagnostic.removeAll(); detector = ZmodemDetector()
        if let staging { try? FileManager.default.removeItem(at: staging) }
        staging = nil; destination = nil
    }
}
