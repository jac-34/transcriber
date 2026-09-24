import Foundation
import Observation

/// User preferences backed by UserDefaults.
@MainActor @Observable
public final class Settings {
    private enum Key {
        static let modelChoice = "modelChoice"
        static let libraryFolder = "libraryFolder"
    }

    private let defaults: UserDefaults

    public var modelChoice: ModelChoice {
        didSet { defaults.set(modelChoice.rawValue, forKey: Key.modelChoice) }
    }

    public var libraryFolder: URL {
        didSet { defaults.set(libraryFolder.path, forKey: Key.libraryFolder) }
    }

    public static var defaultLibraryFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcripciones", isDirectory: true)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.modelChoice = defaults.string(forKey: Key.modelChoice).flatMap(ModelChoice.init(rawValue:)) ?? .preciso
        if let path = defaults.string(forKey: Key.libraryFolder) {
            self.libraryFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            self.libraryFolder = Settings.defaultLibraryFolder
        }
    }
}
