import Foundation

// GUI launches may omit LANG. A byte-oriented C locale makes ZLE escape UTF-8 input.
enum TerminalEnvironment {
    static func isUTF8(_ locale: String?) -> Bool {
        guard let locale else { return false }
        return locale.uppercased().replacingOccurrences(of: "-", with: "").contains("UTF8")
    }
    static func make(_ inherited: [String: String], authentication: Bool = false) -> [String: String] {
        var environment = inherited
        let encodingLocale = [inherited["LC_ALL"], inherited["LC_CTYPE"], inherited["LANG"]].compactMap { $0 }.first { isUTF8($0) } ?? "en_US.UTF-8"
        if !isUTF8(environment["LANG"]) { environment["LANG"] = encodingLocale }
        if !isUTF8(environment["LC_CTYPE"]) { environment["LC_CTYPE"] = encodingLocale }
        if !isUTF8(environment["LC_ALL"]) || authentication {
            environment.removeValue(forKey: "LC_ALL")
            environment["LC_CTYPE"] = encodingLocale
        }
        // Askpass recognizes OpenSSH's English password prompt; do not change character encoding.
        if authentication { environment["LC_MESSAGES"] = "C" }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        return environment
    }
}
