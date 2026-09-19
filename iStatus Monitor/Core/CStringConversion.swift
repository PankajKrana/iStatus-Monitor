import Foundation

extension String {
    /// Decodes a NUL-terminated C character buffer, stopping at the first NUL.
    ///
    /// The POSIX and libproc calls the monitors rely on (`proc_pidpath`,
    /// `proc_name`, `inet_ntop`, `getnameinfo`) all write into a fixed-size
    /// buffer and NUL-terminate, leaving trailing zeros that must be dropped
    /// before decoding. This replaces the deprecated `String(cString:)` array
    /// overload with the explicit truncate-then-decode its deprecation message
    /// recommends.
    ///
    /// Invalid UTF-8 is repaired with replacement characters rather than
    /// failing — a mangled process name is preferable to no reading at all.
    init(nulTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self.init(decoding: bytes, as: UTF8.self)
    }
}
