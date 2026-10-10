import CryptoKit
import Combine
import Foundation
import WebKit

struct BlockerStatistics: Equatable {
    /// WebKit does not expose per-request rule matches to WKWebView clients.
    var blockedRequests: Int? = nil
    var blockedTrackers: Int? = nil
    var cosmeticMatchesAtLoad = 0
    /// Counts are observed DOM replacements, never network request matches.
    var visualRegionsReplaced = 0
    var visualRegionsCollapsed = 0
}

struct BlockerPolicy {
    var enabled = true
    var disabledForDomains: Set<String> = []

    func allowsBlocking(_ url: URL?) -> Bool {
        guard enabled, let host = url?.host?.lowercased() else { return enabled }
        return !disabledForDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

@MainActor
final class ContentBlockerEngine: ObservableObject {
    private struct SourceRecord: Codable {
        let ruleVersion: Int
        let hash: String
        let identifiers: [String]
        let networkCount: Int
        let rawLineCount: Int
        let ignoredCount: Int
        let duplicateCount: Int
        let exceptionCount: Int
        let partitionCounts: [String: Int]
        let cosmetic: [CosmeticFilterRule]
        let unsupportedByReason: [String: Int]
        let omittedForLimit: Int
        let upstreamVersion: String?
        let sourceLastModified: String?
        let compiledAt: Date
        var lastChecked: Date
        let compatibilityKey: String?
        let origin: String?
        let seedHash: String?
        let profile: BlockerStageProfile?
        let partitionSize: Int?
    }
    private struct LegacySourceRecord: Codable {
        let hash: String
        let identifiers: [String]
        let networkCount: Int
        let cosmetic: [CosmeticFilterRule]
        let unsupportedByReason: [String: Int]
        let omittedForLimit: Int
        let upstreamVersion: String?
        let sourceLastModified: String?
        let compiledAt: Date
        var lastChecked: Date

        var migrated: SourceRecord {
            SourceRecord(ruleVersion: 3, hash: hash, identifiers: identifiers,
                         networkCount: networkCount, rawLineCount: 0, ignoredCount: 0,
                         duplicateCount: 0, exceptionCount: 0,
                         partitionCounts: ["legacy": identifiers.count], cosmetic: cosmetic,
                         unsupportedByReason: unsupportedByReason, omittedForLimit: omittedForLimit,
                         upstreamVersion: upstreamVersion, sourceLastModified: sourceLastModified,
                         compiledAt: compiledAt, lastChecked: lastChecked,
                         compatibilityKey: nil, origin: nil, seedHash: nil, profile: nil,
                         partitionSize: nil)
        }
    }
    private struct Manifest: Codable {
        let version: Int
        var sources: [String: SourceRecord]
    }
    private struct LegacyManifest: Codable {
        let version: Int
        let sources: [String: LegacySourceRecord]
    }

    static let cacheVersion = 5
    static let updateInterval: TimeInterval = 4 * 24 * 60 * 60
    static var compatibilityKey: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS-\(version.majorVersion).\(version.minorVersion)"
    }
    private let directory: URL
    private let store: WKContentRuleListStore
    private let partitionSize: Int
    private var records: [String: SourceRecord] = [:]
    private var compiledBySource: [String: [WKContentRuleList]] = [:]
    private var updating = false
    private(set) var lastError: String?
    private(set) var cacheHits = 0
    private(set) var compileDurations: [String: TimeInterval] = [:]
    private(set) var parseDurations: [String: TimeInterval] = [:]
    private(set) var stageProfiles: [String: BlockerStageProfile] = [:]
    private(set) var initializationDuration: TimeInterval = 0
    private(set) var cachedLoadDuration: TimeInterval = 0
    @Published private(set) var revision = 0
    var onChange: (() -> Void)?
    var policy: BlockerPolicy {
        didSet { publishChange() }
    }
    var cosmeticEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cosmeticEnabled, forKey: "paper.blocker.cosmeticEnabled")
            publishChange()
        }
    }
    var sourceTitles: [String] { FilterSource.defaults.map(\.title) }
    var lastUpdateDate: Date? { UserDefaults.standard.object(forKey: "paper.blocker.lastUpdateAttempt") as? Date }

    var rules: [WKContentRuleList] {
        FilterSource.defaults.flatMap { compiledBySource[$0.id] ?? [] }
    }
    var cosmeticRules: [CosmeticFilterRule] {
        FilterSource.defaults.flatMap { records[$0.id]?.cosmetic ?? [] }
    }
    var cosmeticCacheKey: String {
        FilterSource.defaults.map { "\($0.id):\(records[$0.id]?.hash ?? "missing")" }.joined(separator: "|")
    }
    var isActive: Bool { !rules.isEmpty && policy.enabled }
    var diagnostics: String {
        let sources = FilterSource.defaults.map { source in
            guard let record = records[source.id] else { return "\(source.title): unavailable" }
            let unsupported = record.unsupportedByReason.values.reduce(0, +)
            let reasons = record.unsupportedByReason.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            let compilation = compileDurations[source.id].map { String(format: "%.3fs", $0) } ?? "cache"
            let parsing = parseDurations[source.id].map { String(format: "%.3fs", $0) } ?? "cache"
            let partitions = record.partitionCounts.sorted { $0.key > $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            let profile = stageProfiles[source.id] ?? record.profile
            let stages = profile.map { String(format: "load %.3fs, prepared %.3fs, scan+dedup %.3fs, normalize %.3fs, rank %.3fs, partition %.3fs, fingerprint %.3fs, JSON %.3fs/%d bytes, WebKit %.3fs, store %.3fs, reused %d",
                                               $0.sourceLoad, $0.preparedRead ?? 0,
                                               $0.scanAndDeduplicate, $0.normalize,
                                               $0.rank, $0.partition, $0.fingerprint ?? 0, $0.serialize, $0.jsonBytes,
                                               $0.webKitCompile, $0.cacheStore, $0.reusedPartitions) } ?? "stage profile unavailable"
            return "\(source.title) \(record.upstreamVersion ?? "unknown") \(record.hash.prefix(12)) <\(source.url.absoluteString)>: \(record.rawLineCount) raw, \(record.networkCount) network, \(record.cosmetic.count) cosmetic, \(record.exceptionCount) parsed network exceptions, \(record.duplicateCount) deduplicated, \(record.ignoredCount) ignored, \(unsupported) unsupported [\(reasons)], \(record.omittedForLimit) omitted; \(record.identifiers.count) partitions [\(partitions)]; parse \(parsing), compile \(compilation); \(stages); activated \(record.compiledAt.ISO8601Format()), checked \(record.lastChecked.ISO8601Format())"
        }.joined(separator: "\n")
        return "cache hits: \(cacheHits)\n" + sources + (lastError.map { "\nerror: " + $0 } ?? "")
    }

    init(directory: URL? = nil, store: WKContentRuleListStore? = nil,
         partitionSize: Int = RulePartitioner.maxRulesPerPartition) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paper/Privacy", isDirectory: true)
        self.directory = base
        self.partitionSize = partitionSize
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let storeURL = base.appendingPathComponent("CompiledRules", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        self.store = store ?? WKContentRuleListStore(url: storeURL) ?? .default()
        let domains = UserDefaults.standard.stringArray(forKey: "paper.blocker.disabledDomains") ?? []
        self.policy = BlockerPolicy(enabled: UserDefaults.standard.object(forKey: "paper.blocker.enabled") as? Bool ?? true,
                                    disabledForDomains: Set(domains.compactMap { SiteIdentity.shared.domain(forHost: $0) }))
        self.cosmeticEnabled = UserDefaults.standard.object(forKey: "paper.blocker.cosmeticEnabled") as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        policy.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "paper.blocker.enabled")
    }

    func setDisabled(_ disabled: Bool, forDomain domain: String) {
        let normalized = SiteIdentity.shared.domain(forHost: domain) ?? ""
        guard normalized == "localhost" || normalized.contains(":") ||
                normalized.range(of: "^[a-z0-9-]+(\\.[a-z0-9-]+)+$", options: .regularExpression) != nil else { return }
        if disabled { policy.disabledForDomains.insert(normalized) }
        else { policy.disabledForDomains.remove(normalized) }
        UserDefaults.standard.set(Array(policy.disabledForDomains).sorted(), forKey: "paper.blocker.disabledDomains")
    }

    func start() async {
        let began = Date()
        defer { initializationDuration = Date().timeIntervalSince(began) }
        let cacheBegan = Date()
        await loadCachedRules()
        cachedLoadDuration = Date().timeIntervalSince(cacheBegan)
        await Task.yield()
        for source in FilterSource.defaults {
            let sourceBegan = Date()
            guard let url = Bundle.main.url(forResource: source.id, withExtension: "txt"),
                  let seedData = try? Data(contentsOf: url) else {
                lastError = "Bundled \(source.title) rules unavailable"
                continue
            }
            let seedHash = Self.hash(seedData)
            let record = records[source.id]
            let current = record?.ruleVersion == Self.cacheVersion &&
                record?.compatibilityKey == Self.compatibilityKey &&
                record?.partitionSize == partitionSize &&
                compiledBySource[source.id] != nil
            if current && (record?.origin != "bundled" || record?.seedHash == seedHash) { continue }
            guard let seedText = String(data: seedData, encoding: .utf8) else {
                lastError = "Bundled \(source.title) rules are not UTF-8"
                continue
            }
            let cachedText = record?.origin == "downloaded" ? cachedSourceText(for: source, hash: record!.hash) : nil
            await install(cachedText ?? seedText, for: source, checkedAt: Date(),
                          origin: cachedText == nil ? "bundled" : "downloaded", seedHash: seedHash,
                          sourceLoad: Date().timeIntervalSince(sourceBegan))
        }
        let lastAttempt = UserDefaults.standard.object(forKey: "paper.blocker.lastUpdateAttempt") as? Date
        let updateDue = lastAttempt.map { Date().timeIntervalSince($0) >= Self.updateInterval } ?? true
        if updateDue,
           FilterSource.defaults.contains(where: { source in
            guard let checked = records[source.id]?.lastChecked else { return true }
            return Date().timeIntervalSince(checked) >= Self.updateInterval
        }) {
            await updateFilters()
        }
    }

    func updateFilters() async {
        guard !updating else { return }
        updating = true
        lastError = nil
        UserDefaults.standard.set(Date(), forKey: "paper.blocker.lastUpdateAttempt")
        defer { updating = false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for source in FilterSource.defaults {
            do {
                let (data, response) = try await session.data(from: source.url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      (100_000...8_000_000).contains(data.count),
                      let text = String(data: data, encoding: .utf8),
                      text.hasPrefix("[Adblock Plus") else {
                    throw BlockerError.invalidSource
                }
                let hash = Self.hash(data)
                if records[source.id]?.hash == hash,
                   records[source.id]?.ruleVersion == Self.cacheVersion,
                   records[source.id]?.compatibilityKey == Self.compatibilityKey,
                   records[source.id]?.partitionSize == partitionSize,
                   compiledBySource[source.id] != nil {
                    records[source.id]?.lastChecked = Date()
                    saveManifest()
                } else {
                    await install(text, for: source, checkedAt: Date(), origin: "downloaded")
                }
            } catch {
                lastError = "\(source.title) update failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadCachedRules() async {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        let manifest = try? decoder.decode(Manifest.self, from: data)
        let legacy = try? decoder.decode(LegacyManifest.self, from: data)
        let sourceRecords: [String: SourceRecord]
        if let manifest, [Self.cacheVersion, 4].contains(manifest.version) { sourceRecords = manifest.sources }
        else if let legacy, legacy.version == 3 { sourceRecords = legacy.sources.mapValues(\.migrated) }
        else { return }
        for source in FilterSource.defaults {
            guard let record = sourceRecords[source.id] else { continue }
            var lists: [WKContentRuleList] = []
            for identifier in record.identifiers {
                guard let list = try? await store.contentRuleList(forIdentifier: identifier) else {
                    lists.removeAll()
                    break
                }
                lists.append(list)
            }
            guard lists.count == record.identifiers.count, !lists.isEmpty else { continue }
            records[source.id] = record
            compiledBySource[source.id] = lists
            cacheHits += 1
        }
        publishChange()
    }

    func install(_ text: String, for source: FilterSource, checkedAt: Date,
                 origin: String = "downloaded", seedHash: String? = nil,
                 sourceLoad: TimeInterval = 0) async {
        let data = Data(text.utf8)
        let hash = Self.hash(data)
        if records[source.id]?.hash == hash,
           records[source.id]?.ruleVersion == Self.cacheVersion,
           records[source.id]?.compatibilityKey == Self.compatibilityKey,
           records[source.id]?.partitionSize == partitionSize,
           compiledBySource[source.id] != nil { return }
        var profile = BlockerStageProfile()
        profile.sourceLoad = sourceLoad
        let parsed: ParsedFilterList
        let preparedBegan = Date()
        if let cached = cachedPrepared(for: source, hash: hash) {
            parsed = cached
            profile.preparedRead = Date().timeIntervalSince(preparedBegan)
            profile.preparedCacheHit = true
            parseDurations[source.id] = 0
        } else {
            let parseBegan = Date()
            parsed = await Task.detached(priority: .utility) { FilterParser.parse(text) }.value
            parseDurations[source.id] = Date().timeIntervalSince(parseBegan)
            profile.scanAndDeduplicate = parsed.timings.scanAndDeduplicate
            profile.normalize = parsed.timings.normalize
            profile.rank = parsed.timings.rank
            let storeBegan = Date()
            savePrepared(parsed, for: source, hash: hash)
            profile.cacheStore += Date().timeIntervalSince(storeBegan)
        }
        guard !parsed.network.isEmpty else { lastError = "No supported \(source.title) network rules"; return }
        let partitionBegan = Date()
        let partitions = RulePartitioner.partitions(for: parsed.network, size: partitionSize)
        profile.partition = Date().timeIntervalSince(partitionBegan)
        var staged: [WKContentRuleList] = []
        var newlyCompiledIdentifiers: [String] = []
        do {
            for partition in partitions {
                let fingerprintBegan = Date()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let fingerprint = try Self.hash(encoder.encode(partition.rules))
                profile.fingerprint = (profile.fingerprint ?? 0) + Date().timeIntervalSince(fingerprintBegan)
                let identifier = "paper.v\(Self.cacheVersion).\(source.id).\(Self.compatibilityKey).\(fingerprint)"
                if let existing = try? await store.contentRuleList(forIdentifier: identifier) {
                    staged.append(existing)
                    profile.reusedPartitions += 1
                    continue
                }
                let json: String
                if let cached = cachedJSON(for: source, partitionHash: fingerprint) {
                    json = cached
                } else {
                    let serializationBegan = Date()
                    json = try await Task.detached(priority: .utility) {
                        try RuleCompiler.json(for: partition.rules)
                    }.value
                    profile.serialize += Date().timeIntervalSince(serializationBegan)
                    let storeBegan = Date()
                    saveJSON(json, for: source, partitionHash: fingerprint)
                    profile.cacheStore += Date().timeIntervalSince(storeBegan)
                }
                profile.jsonBytes += json.utf8.count
                let compileBegan = Date()
                guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
                    throw BlockerError.compilationReturnedNoList
                }
                profile.webKitCompile += Date().timeIntervalSince(compileBegan)
                staged.append(list)
                newlyCompiledIdentifiers.append(identifier)
            }
        } catch {
            for identifier in newlyCompiledIdentifiers { try? await store.removeContentRuleList(forIdentifier: identifier) }
            lastError = "\(source.title) compilation failed: \(error.localizedDescription)"
            return
        }
        let storeBegan = Date()
        saveSourceText(data, for: source, hash: hash)
        pruneDiskCache(for: source, activeHash: hash, activeIdentifiers: staged.map(\.identifier))
        profile.cacheStore += Date().timeIntervalSince(storeBegan)
        compileDurations[source.id] = profile.webKitCompile
        stageProfiles[source.id] = profile
        let old = records[source.id]
        records[source.id] = SourceRecord(ruleVersion: Self.cacheVersion, hash: hash,
                                          identifiers: staged.map(\.identifier),
                                          networkCount: parsed.network.count,
                                          rawLineCount: parsed.totalLines, ignoredCount: parsed.ignored,
                                          duplicateCount: parsed.duplicateCount,
                                          exceptionCount: parsed.networkExceptions.count,
                                          partitionCounts: Dictionary(grouping: partitions, by: {
                                              "priority\($0.highestPriority)-\($0.lowestPriority)"
                                          })
                                              .mapValues(\.count),
                                          cosmetic: parsed.cosmetic,
                                          unsupportedByReason: parsed.unsupportedByReason,
                                          omittedForLimit: parsed.omittedForLimit,
                                          upstreamVersion: Self.header("Version", in: text),
                                          sourceLastModified: Self.header("Last modified", in: text),
                                          compiledAt: Date(), lastChecked: checkedAt,
                                          compatibilityKey: Self.compatibilityKey, origin: origin,
                                          seedHash: seedHash, profile: profile,
                                          partitionSize: partitionSize)
        compiledBySource[source.id] = staged
        saveManifest()
        publishChange()
        if let old {
            let active = Set(staged.map(\.identifier))
            for identifier in old.identifiers where !active.contains(identifier) {
                try? await store.removeContentRuleList(forIdentifier: identifier)
            }
        }
    }

    private func preparedURL(for source: FilterSource, hash: String) -> URL {
        directory.appendingPathComponent("Prepared", isDirectory: true)
            .appendingPathComponent("\(source.id)-\(hash).json")
    }

    private func cachedPrepared(for source: FilterSource, hash: String) -> ParsedFilterList? {
        let bundled = Bundle.main.url(forResource: "\(source.id)-prepared-v\(Self.cacheVersion)", withExtension: "json")
        for url in [preparedURL(for: source, hash: hash), bundled].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let artifact = try? JSONDecoder().decode(PreparedFilterArtifact.self, from: data),
                  artifact.version == Self.cacheVersion,
                  artifact.compatibilityKey == "portable",
                  artifact.sourceHash == hash else { continue }
            return artifact.parsed
        }
        return nil
    }

    private func savePrepared(_ parsed: ParsedFilterList, for source: FilterSource, hash: String) {
        let url = preparedURL(for: source, hash: hash)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let artifact = PreparedFilterArtifact(version: Self.cacheVersion,
                                              compatibilityKey: "portable",
                                              sourceHash: hash, parsed: parsed)
        if let data = try? JSONEncoder().encode(artifact) { try? data.write(to: url, options: .atomic) }
    }

    private func jsonURL(for source: FilterSource, partitionHash: String) -> URL {
        directory.appendingPathComponent("WebKitJSON", isDirectory: true)
            .appendingPathComponent("\(source.id)-\(partitionHash).json")
    }

    private func cachedJSON(for source: FilterSource, partitionHash: String) -> String? {
        guard let data = try? Data(contentsOf: jsonURL(for: source, partitionHash: partitionHash)),
              let artifact = try? JSONDecoder().decode(CachedRuleJSON.self, from: data),
              artifact.version == Self.cacheVersion,
              artifact.compatibilityKey == Self.compatibilityKey,
              artifact.partitionHash == partitionHash,
              Self.hash(Data(artifact.json.utf8)) == artifact.jsonHash else { return nil }
        return artifact.json
    }

    private func saveJSON(_ json: String, for source: FilterSource, partitionHash: String) {
        let url = jsonURL(for: source, partitionHash: partitionHash)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let artifact = CachedRuleJSON(version: Self.cacheVersion,
                                      compatibilityKey: Self.compatibilityKey,
                                      partitionHash: partitionHash,
                                      jsonHash: Self.hash(Data(json.utf8)), json: json)
        if let data = try? JSONEncoder().encode(artifact) { try? data.write(to: url, options: .atomic) }
    }

    private func sourceURL(for source: FilterSource, hash: String) -> URL {
        directory.appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("\(source.id)-\(hash).txt")
    }

    private func cachedSourceText(for source: FilterSource, hash: String) -> String? {
        guard let data = try? Data(contentsOf: sourceURL(for: source, hash: hash)),
              Self.hash(data) == hash else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveSourceText(_ data: Data, for source: FilterSource, hash: String) {
        let url = sourceURL(for: source, hash: hash)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func pruneDiskCache(for source: FilterSource, activeHash: String,
                                activeIdentifiers: [String]) {
        let activeJSON = Set(activeIdentifiers.compactMap { $0.split(separator: ".").last }
            .map { "\(source.id)-\($0).json" })
        for (folder, limit) in [("Prepared", 3), ("Sources", 2), ("WebKitJSON", 60)] {
            let url = directory.appendingPathComponent(folder, isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            let protected: Set<String>
            switch folder {
            case "Prepared": protected = ["\(source.id)-\(activeHash).json"]
            case "Sources": protected = ["\(source.id)-\(activeHash).txt"]
            default: protected = activeJSON
            }
            let matching = files.filter {
                $0.lastPathComponent.hasPrefix(source.id + "-") && !protected.contains($0.lastPathComponent)
            }
                .sorted { lhs, rhs in
                    let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return left > right
                }
            for old in matching.dropFirst(max(0, limit - protected.count)) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    private func saveManifest() {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? JSONEncoder().encode(Manifest(version: Self.cacheVersion, sources: records)) else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { lastError = "Unable to persist blocker cache: \(error.localizedDescription)" }
    }

    private func publishChange() {
        revision += 1
        onChange?()
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func header(_ key: String, in text: String) -> String? {
        text.split(separator: "\n", maxSplits: 20).first { $0.hasPrefix("! \(key): ") }
            .map { String($0.dropFirst(key.count + 4)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private enum BlockerError: LocalizedError {
        case invalidSource, compilationReturnedNoList
        var errorDescription: String? {
            switch self {
            case .invalidSource: "Invalid or incomplete filter download"
            case .compilationReturnedNoList: "WebKit returned no compiled rule list"
            }
        }
    }
}
