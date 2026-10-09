import Foundation

nonisolated struct BlockerStageProfile: Codable, Sendable {
    var sourceLoad: TimeInterval = 0
    var preparedRead: TimeInterval?
    var scanAndDeduplicate: TimeInterval = 0
    var normalize: TimeInterval = 0
    var rank: TimeInterval = 0
    var partition: TimeInterval = 0
    var fingerprint: TimeInterval?
    var serialize: TimeInterval = 0
    var webKitCompile: TimeInterval = 0
    var cacheStore: TimeInterval = 0
    var jsonBytes = 0
    var reusedPartitions = 0
    var preparedCacheHit = false

    var total: TimeInterval {
        sourceLoad + (preparedRead ?? 0) + scanAndDeduplicate + normalize + rank + partition +
        (fingerprint ?? 0) +
        serialize + webKitCompile + cacheStore
    }
}

nonisolated struct PreparedFilterArtifact: Codable, Sendable {
    let version: Int
    let compatibilityKey: String
    let sourceHash: String
    let parsed: ParsedFilterList
}

nonisolated struct CachedRuleJSON: Codable, Sendable {
    let version: Int
    let compatibilityKey: String
    let partitionHash: String
    let jsonHash: String
    let json: String
}
