import Foundation

public enum ConfidenceTier: String, Codable, Equatable, Sendable {
    case high
    case low

    public var isClosable: Bool { self == .high }
}
