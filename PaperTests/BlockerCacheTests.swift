import CryptoKit
import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
struct BlockerCacheTests {
    @Test func bundledPreparedArtifactsMatchBundledSources() throws {
        for source in FilterSource.defaults {
            let sourceURL = try #require(Bundle.main.url(forResource: source.id, withExtension: "txt"))
            let preparedURL = try #require(Bundle.main.url(
                forResource: "\(source.id)-prepared-v\(ContentBlockerEngine.cacheVersion)", withExtension: "json"))
            let sourceData = try Data(contentsOf: sourceURL)
            let artifact = try JSONDecoder().decode(PreparedFilterArtifact.self, from: Data(contentsOf: preparedURL))
            let hash = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
            #expect(artifact.version == ContentBlockerEngine.cacheVersion)
            #expect(artifact.compatibilityKey == "portable")
            #expect(artifact.sourceHash == hash)
            #expect(artifact.parsed.network.count == FilterParser.maxNetworkRulesPerSource)
        }
    }

    @Test func exportPortableBundledPreparedArtifacts() throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-export-prepared") else { return }
        let output = URL(fileURLWithPath: "/private/tmp/paper-phase2d2-prepared", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for source in FilterSource.defaults {
            let url = try #require(Bundle.main.url(forResource: source.id, withExtension: "txt"))
            let data = try Data(contentsOf: url)
            let text = try #require(String(data: data, encoding: .utf8))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let artifact = PreparedFilterArtifact(version: ContentBlockerEngine.cacheVersion,
                                                  compatibilityKey: "portable", sourceHash: hash,
                                                  parsed: FilterParser.parse(text))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(artifact).write(to: output.appendingPathComponent(
                "\(source.id)-prepared-v\(ContentBlockerEngine.cacheVersion).json"), options: .atomic)
        }
    }

    @Test func preparedAndJSONArtifactsRecoverMissingCompiledList() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-cache-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiled = directory.appendingPathComponent("CompiledRules")
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        let store = try #require(WKContentRuleListStore(url: compiled))
        let source = FilterSource.defaults[0]
        let text = (0..<1_205).map { "||host\($0).example.com^$script" }.joined(separator: "\n")
        let first = ContentBlockerEngine(directory: directory, store: store)
        await first.install(text, for: source, checkedAt: Date())
        #expect(first.rules.count == 2)
        #expect(first.stageProfiles[source.id]?.preparedCacheHit == false)
        let identifiers = first.rules.map(\.identifier)
        try await store.removeContentRuleList(forIdentifier: identifiers[1])

        let recovered = ContentBlockerEngine(directory: directory, store: store)
        await recovered.install(text, for: source, checkedAt: Date())
        #expect(recovered.rules.count == 2)
        #expect(recovered.stageProfiles[source.id]?.preparedCacheHit == true)
        #expect(recovered.stageProfiles[source.id]?.reusedPartitions == 1)
        #expect(recovered.stageProfiles[source.id]?.serialize == 0)
        #expect(recovered.rules[0].identifier == identifiers[0])

        let revision = recovered.revision
        await recovered.install(text, for: source, checkedAt: Date())
        #expect(recovered.revision == revision)
        let changed = text.replacingOccurrences(of: "host1204.example.com", with: "changed1204.example.com")
        await recovered.install(changed, for: source, checkedAt: Date())
        #expect(recovered.rules.count == 2)
        #expect(recovered.stageProfiles[source.id]?.reusedPartitions == 1)
        #expect(recovered.rules[0].identifier == identifiers[0])
        let active = recovered.rules.map(\.identifier)
        await recovered.install("invalid", for: source, checkedAt: Date())
        #expect(recovered.rules.map(\.identifier) == active)
    }

    @Test func incompatiblePreparedArtifactIsIgnored() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-cache-version-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiled = directory.appendingPathComponent("CompiledRules")
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        let store = try #require(WKContentRuleListStore(url: compiled))
        let source = FilterSource.defaults[0]
        let text = "||ads.example.com^$script"
        let first = ContentBlockerEngine(directory: directory, store: store)
        await first.install(text, for: source, checkedAt: Date())
        let identifier = try #require(first.rules.first?.identifier)
        try await store.removeContentRuleList(forIdentifier: identifier)
        let preparedDirectory = directory.appendingPathComponent("Prepared")
        let artifactURL = try #require(FileManager.default.contentsOfDirectory(at: preparedDirectory,
                                                 includingPropertiesForKeys: nil).first)
        let data = try Data(contentsOf: artifactURL)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["compatibilityKey"] = "incompatible-webkit"
        try JSONSerialization.data(withJSONObject: object).write(to: artifactURL, options: .atomic)
        let restored = ContentBlockerEngine(directory: directory, store: store)
        await restored.install(text, for: source, checkedAt: Date())
        #expect(restored.rules.count == 1)
        #expect(restored.stageProfiles[source.id]?.preparedCacheHit == false)
        #expect((restored.stageProfiles[source.id]?.scanAndDeduplicate ?? 0) > 0)
    }
}
