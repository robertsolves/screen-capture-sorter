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

// POSIX locale so a non-Gregorian system calendar doesn't change the folder names.
func formatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = format
    return f
}
let dayFormat = formatter("yyyy-MM-dd")
let hourFormat = formatter("HH")
let dayPattern = try! Regex(#"\d{4}-\d{2}-\d{2}"#)
let hourPattern = try! Regex(#"\d{2}"#)

// The newest day folder, and the newest hour folder inside it, carry this prefix so they are
// easy to spot. Not "LATEST:", because Finder shows a colon in a file name as "/".
let latestPrefix = "LATEST_"

// Size seen on the previous scan. A file is moved only once its size holds across two scans,
// so a capture still being written is left alone.
var lastSize: [URL: Int] = [:]
var rescanQueued = false

func plainName(_ name: String) -> String {
    name.hasPrefix(latestPrefix) ? String(name.dropFirst(latestPrefix.count)) : name
}

// Day or hour folders in `parent` with their plain names, whether or not they carry the prefix.
func dateFolders(in parent: URL, matching pattern: Regex<AnyRegexOutput>) -> [(name: String, url: URL)] {
    let items = (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    return items.compactMap { item in
        guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        let name = plainName(item.lastPathComponent)
        return name.wholeMatch(of: pattern) != nil ? (name, item) : nil
    }
}

// The folder in `parent` for `name`, creating it if neither `name` nor LATEST_`name` exists.
func folder(_ name: String, in parent: URL, matching pattern: Regex<AnyRegexOutput>) -> URL? {
    if let existing = dateFolders(in: parent, matching: pattern).first(where: { $0.name == name }) {
        return existing.url
    }
    let created = parent.appendingPathComponent(name, isDirectory: true)
    do {
        try fm.createDirectory(at: created, withIntermediateDirectories: true)
        return created
    } catch {
        log("cannot create \(created.path): \(error)")
        return nil
    }
}

// Renames `folder` to `name`. If a folder of that name already exists, moves the contents in.
func rename(_ folder: URL, to name: String) {
    let target = folder.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    guard target.lastPathComponent != folder.lastPathComponent else { return }
    do {
        if fm.fileExists(atPath: target.path) {
            for item in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                try fm.moveItem(at: item, to: uniqueURL(in: target, for: item.lastPathComponent))
            }
            try fm.removeItem(at: folder)
        } else {
            try fm.moveItem(at: folder, to: target)
        }
    } catch {
        log("cannot rename \(folder.path) to \(name): \(error)")
    }
}

// Gives the newest folder in `parent` the prefix and takes it off the others; with
// `markNewest` false, takes it off all of them. Returns the folders as renamed.
@discardableResult
func markNewest(in parent: URL, matching pattern: Regex<AnyRegexOutput>, markNewest: Bool) -> [(name: String, url: URL)] {
    let folders = dateFolders(in: parent, matching: pattern)
    let newest = folders.map(\.name).max()
    for (name, url) in folders where fm.fileExists(atPath: url.path) {
        rename(url, to: markNewest && name == newest ? latestPrefix + name : name)
    }
    return dateFolders(in: parent, matching: pattern)
}

// Moves the prefix onto the newest day and its newest hour, and off everything else.
func refreshLatest() {
    let days = markNewest(in: root, matching: dayPattern, markNewest: true)
    let newestDay = days.map(\.name).max()
    for (name, url) in days {
        markNewest(in: url, matching: hourPattern, markNewest: name == newestDay)
    }
}

func uniqueURL(in folder: URL, for fileName: String) -> URL {
    let file = URL(fileURLWithPath: fileName)
    let base = file.deletingPathExtension().lastPathComponent
    let ext = file.pathExtension
    var target = folder.appendingPathComponent(fileName)
    var n = 2
    while fm.fileExists(atPath: target.path) {
        target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
        n += 1
    }
    return target
}

// Creates the day and hour folders for `created` if needed, refreshes the LATEST_ markers, and
// returns where the file should go under whatever name its hour folder now has.
func destination(for file: URL, created: Date) -> URL? {
    let day = dayFormat.string(from: created)
    let hour = hourFormat.string(from: created)
    guard let dayFolder = folder(day, in: root, matching: dayPattern),
          folder(hour, in: dayFolder, matching: hourPattern) != nil else { return nil }
    refreshLatest()
    guard let renamedDay = folder(day, in: root, matching: dayPattern),
          let hourFolder = folder(hour, in: renamedDay, matching: hourPattern) else { return nil }
    return uniqueURL(in: hourFolder, for: file.lastPathComponent)
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
        guard let target = destination(for: file, created: created) else { continue }
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
refreshLatest()
queueScan(after: 0)
dispatchMain()
