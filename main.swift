// Sorts each new screenshot and screen recording into <root>/YYYY-MM-DD/HH/ and copies it to
// the clipboard. macOS saves captures to <root> (install.sh points `screencapture` there) and
// launchd keeps this running. A compiled binary rather than a script so it can be granted
// Desktop access in Privacy & Security; launchd-spawned scripts are silently denied it.
import AppKit
import UniformTypeIdentifiers

let fm = FileManager.default
let root = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/screen_capture", isDirectory: true)
let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentTypeKey]

// Only captures younger than this reach the clipboard, so files swept up at launch don't.
let clipboardWindow: TimeInterval = 30

func log(_ message: String) {
    FileHandle.standardError.write("\(Date()) \(message)\n".data(using: .utf8)!)
}

let dayFormat = DateFormatter()
dayFormat.dateFormat = "yyyy-MM-dd"
let hourFormat = DateFormatter()
hourFormat.dateFormat = "HH"

// Size seen on the previous scan. A file is moved only once its size holds across two scans,
// so a capture still being written is left alone.
var lastSize: [URL: Int] = [:]
var rescanQueued = false

func destination(for file: URL, created: Date) -> URL {
    let folder = root
        .appendingPathComponent(dayFormat.string(from: created), isDirectory: true)
        .appendingPathComponent(hourFormat.string(from: created), isDirectory: true)
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let base = file.deletingPathExtension().lastPathComponent
    let ext = file.pathExtension
    var target = folder.appendingPathComponent(file.lastPathComponent)
    var n = 2
    while fm.fileExists(atPath: target.path) {
        target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
        n += 1
    }
    return target
}

func copyToClipboard(_ file: URL, type: UTType?) {
    // The file URL (like a Finder copy) lets Finder, chat apps and terminals paste the file
    // itself; images also carry their pixels for apps that paste image data.
    let item = NSPasteboardItem()
    if let type, type.conforms(to: .image) {
        if type.conforms(to: .png), let data = try? Data(contentsOf: file) {
            item.setData(data, forType: .png)
        } else if let tiff = NSImage(contentsOf: file)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
    }
    item.setString(file.absoluteString, forType: .fileURL)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
}

func scan() {
    rescanQueued = false
    let files: [URL]
    do {
        files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
    } catch {
        // Usually a missing Desktop access grant in Privacy & Security > Files & Folders.
        log("cannot read \(root.path): \(error)")
        return
    }
    var unsettled = false
    var newest: (url: URL, created: Date, type: UTType?)?
    for file in files {
        guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
        let size = values.fileSize ?? 0
        if lastSize[file] != size {
            lastSize[file] = size
            unsettled = true
            continue
        }
        lastSize[file] = nil
        let created = values.creationDate ?? Date()
        let target = destination(for: file, created: created)
        do {
            try fm.moveItem(at: file, to: target)
        } catch {
            log("cannot move \(file.path): \(error)")
            continue
        }
        if newest == nil || created > newest!.created {
            newest = (target, created, values.contentType)
        }
    }
    if let newest, Date().timeIntervalSince(newest.created) <= clipboardWindow {
        copyToClipboard(newest.url, type: newest.type)
    }
    if unsettled { queueScan(after: 0.3) }
}

func queueScan(after delay: TimeInterval) {
    guard !rescanQueued else { return }
    rescanQueued = true
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: scan)
}

try? fm.createDirectory(at: root, withIntermediateDirectories: true)
let fd = open(root.path, O_EVTONLY)
guard fd >= 0 else {
    log("cannot watch \(root.path): errno \(errno)")
    exit(1)
}
let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
source.setEventHandler { queueScan(after: 0) }
source.resume()
queueScan(after: 0)
dispatchMain()
