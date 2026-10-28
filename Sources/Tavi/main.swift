import AppKit
import CryptoKit
import Foundation
import Darwin
import TaviCore

#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--render-setup"),
   CommandLine.arguments.indices.contains(index + 1) {
    do {
        try MainActor.assumeIsolated {
            try SetupRenderCheck.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        exit(0)
    } catch { fputs("SETUP_RENDER_FAILED: \(error)\n", stderr); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of: "--check-update-archive"),
   CommandLine.arguments.indices.contains(index + 2) {
    let archive = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    do { print("UPDATE_ARCHIVE_OK \(try Updater.unpack(archive, version: CommandLine.arguments[index + 2]).path)"); exit(0) }
    catch { fputs("UPDATE_ARCHIVE_FAILED: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--check-editor") {
    do { try EditorCheck.run(); exit(0) }
    catch { fputs("EDITOR_CHECK_FAILED: \(error)\n", stderr); exit(1) }
}
#endif

if CommandLine.arguments.contains("--register-input-source") {
    let result = InputSourceSetup.register()
    print("registration=\(result)")
    exit(result == noErr ? 0 : 1)
} else if CommandLine.arguments.contains("--select-input-source") {
    let result = InputSourceSetup.select()
    print("selection=\(result)")
    exit(result == noErr ? 0 : 1)
} else if CommandLine.arguments.contains("--input-source-registered") {
    let registered = InputSourceSetup.isRegistered
    print("registered=\(registered)")
    exit(registered ? 0 : 1)
} else if let index = CommandLine.arguments.firstIndex(of: "--predict") {
    var engine = CompositionEngine()
    for token in CommandLine.arguments.dropFirst(index + 1) {
        engine.append(token)
        print("\(token)\t\(engine.text)\t\(engine.confidence)")
        _ = engine.commit(learn: false)
    }
} else if CommandLine.arguments.contains("--benchmark") {
    let stress = CommandLine.arguments.contains("--stress")
    let cases = ["APIfmf", "dkssudgktpdy", "hello", "githubdp", "3xhaust", "gksrmf", "PDFvkdlf", "world"]
        + (stress ? [String(repeating: "abcdefgh", count: 8)] : [])
    var engine = CompositionEngine()
    if stress {
        engine.words = (0..<2_000).map { LearnedWord(raw: "handle\($0)", text: "Handle\($0)", confirmations: 3) }
    }
    let coldStart = DispatchTime.now().uptimeNanoseconds
    engine.append(cases[0])
    let coldMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1_000_000
    _ = engine.cancel()
    var timings: [Double] = []
    var checksum = 0
    var before = rusage()
    getrusage(RUSAGE_SELF, &before)
    let sampleStart = DispatchTime.now().uptimeNanoseconds
    let iterations = stress ? 1_000 : 10_000
    for index in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        engine.append(cases[index % cases.count])
        checksum += engine.text.utf8.count
        _ = engine.commit(learn: false)
        timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    timings.sort()
    let wallSeconds = Double(DispatchTime.now().uptimeNanoseconds - sampleStart) / 1_000_000_000
    var after = rusage()
    getrusage(RUSAGE_SELF, &after)
    func cpuSeconds(_ usage: rusage) -> Double {
        Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    let report: [String: Any] = [
        "iterations": timings.count, "p50_ms": timings[iterations / 2],
        "p95_ms": timings[iterations * 95 / 100], "p99_ms": timings[iterations * 99 / 100],
        // Not `timings.last ?? 0`: older compilers box that as an Optional, which JSON cannot write.
        "max_ms": timings[timings.count - 1], "checksum": checksum,
        "personal_words": engine.words.count, "profile": stress ? "full-dictionary-and-64-key-token" : "short-typing",
        "cold_first_decision_ms": coldMilliseconds,
        "cpu_seconds": cpuSeconds(after) - cpuSeconds(before),
        "wall_seconds": wallSeconds,
        "peak_rss_bytes": after.ru_maxrss,
        "scope": "warm core decision and commit; not cross-process editor latency",
    ]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
       let json = String(data: data, encoding: .utf8) { print(json) }
} else if let index = CommandLine.arguments.firstIndex(of: "--accuracy") {
    // Types each word of the fixed set into a fresh session, as keys then Space, and counts exact commits.
    let path = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "Tests/Accuracy/eval-v1.tsv"
    guard let data = FileManager.default.contents(atPath: path), let source = String(data: data, encoding: .utf8) else {
        fputs("ACCURACY_FAILED: cannot read \(path)\n", stderr); exit(1)
    }
    var totals: [String: (correct: Int, total: Int, misses: [String])] = [:]
    for line in source.split(separator: "\n") where !line.hasPrefix("#") {
        let fields = line.split(separator: "\t").map(String.init)
        guard fields.count == 2 else { continue }
        let raw = Hangul.keys(for: fields[1])
        var session = InputSession()
        for key in raw { _ = session.handle(.text(String(key))) }
        guard case .commit(let text, _, _) = session.handle(.space) else { continue }
        let committed = String(text.dropLast())
        var tally = totals[fields[0], default: (0, 0, [])]
        tally.total += 1
        if committed == fields[1] { tally.correct += 1 } else if tally.misses.count < 10 {
            tally.misses.append("\(raw) → \(committed) (expected \(fields[1]))")
        }
        totals[fields[0]] = tally
    }
    let correct = totals.values.map(\.correct).reduce(0, +), total = totals.values.map(\.total).reduce(0, +)
    var report: [String: Any] = [
        "set": path, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
        "total": total, "accuracy": total == 0 ? 0 : Double(correct) / Double(total),
    ]
    for (category, tally) in totals {
        report[category] = ["total": tally.total, "accuracy": Double(tally.correct) / Double(tally.total), "misses": tally.misses]
    }
    if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
       let text = String(data: json, encoding: .utf8) { print(text) }
} else if CommandLine.arguments.contains("--diagnose") {
    print("mode=\(InputSourceSetup.isInputMethodProcess ? "input-method" : "application")")
    print("selected=\(InputSourceSetup.isSelected)")
    print("source=\(SourceMonitor.currentLanguage()?.rawValue ?? "unsupported")")
} else {
    InputSourceSetup.migrateLegacyPreferences()
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate: NSApplicationDelegate = InputSourceSetup.isInputMethodProcess
            ? InputMethodServiceDelegate() : AppDelegate()
        let background = InputSourceSetup.isInputMethodProcess
            || CommandLine.arguments.contains(Updater.backgroundArgument)
        app.setActivationPolicy(background ? .accessory : .regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
