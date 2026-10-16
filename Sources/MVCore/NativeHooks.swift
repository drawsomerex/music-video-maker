import Foundation

/// Set by the native build (MVNative) at launch: speech and prompt-writing then run inside the app with Swift MLX,
/// and nothing is sent to oMLX. In the normal build these stay nil.
public enum NativeHooks {
    nonisolated(unsafe) public static var wordTimes: (@Sendable (String) async throws -> [TimedWord])?
    nonisolated(unsafe) public static var chat: (@Sendable (String, Int) async throws -> String)?
    nonisolated(unsafe) public static var isReady: (@Sendable () -> String?)?        // nil = ready, otherwise a "run setup" message
    public static var active: Bool { chat != nil }
}
