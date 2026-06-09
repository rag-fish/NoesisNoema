// Project: NoesisNoema
// File: NumpyReader.swift
// Description: Minimal NumPy .npy reader for little-endian float32 arrays.
//   ADR-0011 PR-B (§3-§7): RAGpack v1.2 stores embeddings as embeddings.npy.
//   This is the import-side parser. Pure Foundation, no third-party deps.
// License: MIT License

import Foundation

/// Parses a NumPy `.npy` file (v1.0 / v2.0) holding a little-endian float32
/// (`'<f4'`), C-contiguous array. Throws on every malformation — there is no
/// silent fallback (ADR-0011 §4).
struct NumpyReader {

    /// Reads a float32 `.npy` file.
    /// - Returns: the parsed `shape` (arbitrary rank) and a flat `data` buffer of
    ///   `prod(shape)` floats in C (row-major) order. The caller reshapes.
    static func readFloat32(from url: URL) throws -> (shape: [Int], data: [Float]) {
        let bytes = try Data(contentsOf: url)

        // Header preamble: 6 magic + 2 version + (2 or 4) header-length bytes.
        guard bytes.count >= 10 else { throw NumpyReadError.fileTooSmall }

        // Magic string: \x93 N U M P Y
        let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]
        guard Array(bytes.prefix(6)) == magic else { throw NumpyReadError.badMagic }

        let major = bytes[bytes.startIndex + 6]
        // bytes[startIndex + 7] is the minor version; we only branch on major.

        // Header length is uint16 (v1.x) or uint32 (v2.x), little-endian. The
        // header dict begins right after the length field.
        let headerLenSize: Int
        switch major {
        case 1:
            headerLenSize = 2
        case 2:
            headerLenSize = 4
        default:
            throw NumpyReadError.unsupportedVersion
        }

        let lenStart = bytes.startIndex + 8
        guard bytes.count >= 8 + headerLenSize else { throw NumpyReadError.fileTooSmall }

        var headerLen = 0
        for i in 0..<headerLenSize {
            // Little-endian: least-significant byte first.
            headerLen |= Int(bytes[lenStart + i]) << (8 * i)
        }

        let headerStart = lenStart + headerLenSize
        let headerEnd = headerStart + headerLen
        guard bytes.count >= headerEnd else { throw NumpyReadError.fileTooSmall }

        guard let header = String(data: bytes[headerStart..<headerEnd], encoding: .ascii) else {
            throw NumpyReadError.headerMalformed("header is not valid ASCII")
        }

        // Parse the three fields we care about out of the Python dict literal.
        let descr = try parseStringField("descr", in: header)
        guard descr == "<f4" else { throw NumpyReadError.unsupportedDtype(descr) }

        let fortran = try parseBoolField("fortran_order", in: header)
        guard fortran == false else {
            throw NumpyReadError.headerMalformed("fortran_order: True is not supported")
        }

        let shape = try parseShapeField(in: header)

        // Data payload: prod(shape) little-endian float32 values.
        let expectedCount = shape.reduce(1, *)
        let expectedBytes = expectedCount * 4
        let payload = bytes[headerEnd...]
        guard payload.count == expectedBytes else {
            throw NumpyReadError.dataLengthMismatch(expected: expectedBytes, actual: payload.count)
        }

        // Single-pass copy into [Float]. We re-base the payload into a contiguous
        // Data so the unsafe load offsets are well-defined regardless of the
        // original slice's startIndex. The on-disk bytes are little-endian, which
        // matches every Apple platform we ship, so a raw reinterpret is correct.
        var out = [Float](repeating: 0, count: expectedCount)
        if expectedCount > 0 {
            let contiguous = Data(payload)
            contiguous.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in 0..<expectedCount {
                    out[i] = raw.loadUnaligned(fromByteOffset: i * 4, as: Float.self)
                }
            }
        }

        return (shape, out)
    }

    // MARK: - Header field parsing (hand-written; no regex framework)

    /// Extracts `'<key>': '<value>'` and returns `<value>`.
    private static func parseStringField(_ key: String, in header: String) throws -> String {
        guard let keyRange = header.range(of: "'\(key)'") else {
            throw NumpyReadError.headerMalformed("missing '\(key)'")
        }
        let after = header[keyRange.upperBound...]
        guard let colon = after.firstIndex(of: ":") else {
            throw NumpyReadError.headerMalformed("malformed '\(key)' (no colon)")
        }
        let rest = after[after.index(after: colon)...]
        guard let openQuote = rest.firstIndex(of: "'") else {
            throw NumpyReadError.headerMalformed("malformed '\(key)' (no opening quote)")
        }
        let valueStart = rest.index(after: openQuote)
        guard let closeQuote = rest[valueStart...].firstIndex(of: "'") else {
            throw NumpyReadError.headerMalformed("malformed '\(key)' (no closing quote)")
        }
        return String(rest[valueStart..<closeQuote])
    }

    /// Extracts `'<key>': True|False`.
    private static func parseBoolField(_ key: String, in header: String) throws -> Bool {
        guard let keyRange = header.range(of: "'\(key)'") else {
            throw NumpyReadError.headerMalformed("missing '\(key)'")
        }
        let after = header[keyRange.upperBound...]
        guard let colon = after.firstIndex(of: ":") else {
            throw NumpyReadError.headerMalformed("malformed '\(key)' (no colon)")
        }
        // The value is the token between the colon and the next comma, e.g.
        // "fortran_order': False, 'shape'..." → "False".
        let afterColon = after[after.index(after: colon)...]
        let valueToken = afterColon.prefix { $0 != "," }
            .trimmingCharacters(in: .whitespaces)
        switch valueToken {
        case "True": return true
        case "False": return false
        default:
            throw NumpyReadError.headerMalformed("malformed '\(key)' (expected True/False, got '\(valueToken)')")
        }
    }

    /// Extracts `'shape': (a, b, ...)` into `[a, b, ...]`. Accepts arbitrary rank,
    /// including the 1-tuple form `(N,)` and the 0-d form `()`.
    private static func parseShapeField(in header: String) throws -> [Int] {
        guard let keyRange = header.range(of: "'shape'") else {
            throw NumpyReadError.shapeMalformed("missing 'shape'")
        }
        let after = header[keyRange.upperBound...]
        guard let open = after.firstIndex(of: "(") else {
            throw NumpyReadError.shapeMalformed("no opening paren")
        }
        guard let close = after[open...].firstIndex(of: ")") else {
            throw NumpyReadError.shapeMalformed("no closing paren")
        }
        let inner = after[after.index(after: open)..<close]
        let dims = inner.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var shape: [Int] = []
        for d in dims {
            guard let n = Int(d), n >= 0 else {
                throw NumpyReadError.shapeMalformed("non-integer dimension '\(d)'")
            }
            shape.append(n)
        }
        return shape
    }
}

enum NumpyReadError: Error {
    case fileTooSmall
    case badMagic                  // not "\x93NUMPY"
    case unsupportedVersion        // we accept 1.0 and 2.0; reject others
    case headerMalformed(String)
    case unsupportedDtype(String)  // we accept only "<f4" (little-endian float32)
    case shapeMalformed(String)
    case dataLengthMismatch(expected: Int, actual: Int)
}
