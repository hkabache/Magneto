import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", initial: .init(.space, modifiers: [.option]))
    static let cancelDictation = Self("cancelDictation", initial: .init(.escape))
}
