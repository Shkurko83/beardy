//
//  DocxZipArchive.swift
//  BlackBeardEditor
//
//  Pure Swift ZIP writer for DOCX packages (sandbox-safe, no external zip process).
//

import Foundation

enum DocxZipArchive {
    static func createArchive(from sourceDirectory: URL, to outputURL: URL) throws {
        var entries: [(path: String, data: Data)] = []
        try collectEntries(at: sourceDirectory, relativeTo: sourceDirectory, into: &entries)
        entries.sort { lhs, rhs in
            func rank(_ path: String) -> Int {
                if path == "[Content_Types].xml" { return 0 }
                if path == "_rels/.rels" { return 1 }
                return 2
            }
            let lr = rank(lhs.path), rr = rank(rhs.path)
            if lr != rr { return lr < rr }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        let zipData = buildZipData(entries: entries)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try zipData.write(to: outputURL, options: .atomic)
    }

    private static func collectEntries(
        at directoryURL: URL,
        relativeTo rootURL: URL,
        into entries: inout [(path: String, data: Data)]
    ) throws {
        let fileManager = FileManager.default
        let children = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [] // must include `_rels/.rels` (hidden dotfile)
        )

        for child in children.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try collectEntries(at: child, relativeTo: rootURL, into: &entries)
            } else {
                let relativePath = child.path
                    .replacingOccurrences(of: rootURL.path + "/", with: "")
                    .replacingOccurrences(of: "\\", with: "/")
                entries.append((relativePath, try Data(contentsOf: child)))
            }
        }
    }

    private static func buildZipData(entries: [(path: String, data: Data)]) -> Data {
        var localParts: [Data] = []
        var centralParts: [Data] = []
        var offset: UInt32 = 0

        for entry in entries {
            let pathData = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let localHeader = makeLocalFileHeader(
                pathLength: UInt16(pathData.count),
                dataSize: UInt32(entry.data.count),
                crc: crc
            )
            var local = Data()
            local.append(localHeader)
            local.append(pathData)
            local.append(entry.data)
            localParts.append(local)

            centralParts.append(
                makeCentralDirectoryHeader(
                    pathLength: UInt16(pathData.count),
                    dataSize: UInt32(entry.data.count),
                    crc: crc,
                    localHeaderOffset: offset
                )
            )
            centralParts.append(pathData)

            offset += UInt32(local.count)
        }

        let centralDirectory = centralParts.reduce(into: Data()) { $0.append($1) }
        let centralOffset = offset
        offset += UInt32(centralDirectory.count)

        let endRecord = makeEndOfCentralDirectory(
            entryCount: UInt16(entries.count),
            centralDirectorySize: UInt32(centralDirectory.count),
            centralDirectoryOffset: centralOffset
        )

        var zip = Data()
        for part in localParts { zip.append(part) }
        zip.append(centralDirectory)
        zip.append(endRecord)
        return zip
    }

    private static func makeLocalFileHeader(pathLength: UInt16, dataSize: UInt32, crc: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(0x0403_4B50) // local file header
        data.appendUInt16(20)          // version needed
        data.appendUInt16(0)         // general purpose
        data.appendUInt16(0)         // compression: store
        data.appendUInt16(0)         // mod time
        data.appendUInt16(0)         // mod date
        data.appendUInt32(crc)
        data.appendUInt32(dataSize)  // compressed size
        data.appendUInt32(dataSize)  // uncompressed size
        data.appendUInt16(pathLength)
        data.appendUInt16(0)         // extra length
        return data
    }

    private static func makeCentralDirectoryHeader(
        pathLength: UInt16,
        dataSize: UInt32,
        crc: UInt32,
        localHeaderOffset: UInt32
    ) -> Data {
        var data = Data()
        data.appendUInt32(0x0201_4B50)
        data.appendUInt16(20) // version made by
        data.appendUInt16(20) // version needed
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt32(crc)
        data.appendUInt32(dataSize)
        data.appendUInt32(dataSize)
        data.appendUInt16(pathLength)
        data.appendUInt16(0) // extra
        data.appendUInt16(0) // comment
        data.appendUInt16(0) // disk number start
        data.appendUInt16(0) // internal attrs
        data.appendUInt32(0) // external attrs
        data.appendUInt32(localHeaderOffset)
        return data
    }

    private static func makeEndOfCentralDirectory(
        entryCount: UInt16,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32
    ) -> Data {
        var data = Data()
        data.appendUInt32(0x0605_4B50)
        data.appendUInt16(0) // disk number
        data.appendUInt16(0) // central dir disk
        data.appendUInt16(entryCount)
        data.appendUInt16(entryCount)
        data.appendUInt32(centralDirectorySize)
        data.appendUInt32(centralDirectoryOffset)
        data.appendUInt16(0) // comment length
        return data
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
