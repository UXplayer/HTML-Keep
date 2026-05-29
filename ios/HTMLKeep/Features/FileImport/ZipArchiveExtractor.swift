import Foundation
import zlib

enum ZipArchiveExtractorError: Error {
    case invalidArchive
    case encryptedArchive
    case unsupportedCompressionMethod
    case unsafePath
    case archiveTooLarge
    case decompressionFailed
    case checksumMismatch
}

enum ZipArchiveWriterError: Error {
    case emptyFolder
    case unsafePath
    case tooManyFiles
    case fileTooLarge
    case archiveTooLarge
}

struct ZipArchiveExtractor {
    private let fileManager: FileManager
    private let maximumExpandedByteCount: Int64?

    init(fileManager: FileManager = .default, maximumExpandedByteCount: Int64? = nil) {
        self.fileManager = fileManager
        self.maximumExpandedByteCount = maximumExpandedByteCount
    }

    func extractArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let archiveData = try Data(contentsOf: archiveURL)
        let entries = try Self.centralDirectoryEntries(in: archiveData)
        try Self.validateExpandedSize(of: entries, maximumByteCount: maximumExpandedByteCount)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        for entry in entries {
            let relativePath = try Self.safeRelativePath(from: entry.fileName)
            guard !Self.shouldSkip(relativePath) else { continue }

            let outputURL = destinationURL.appendingPathComponent(relativePath, isDirectory: entry.isDirectory)
            guard Self.isDescendant(outputURL, of: destinationURL) else {
                throw ZipArchiveExtractorError.unsafePath
            }

            if entry.isDirectory {
                try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
                continue
            }

            let fileData = try Self.fileData(for: entry, in: archiveData)
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileData.write(to: outputURL, options: [.atomic])
        }
    }

    private static func validateExpandedSize(
        of entries: [CentralDirectoryEntry],
        maximumByteCount: Int64?
    ) throws {
        guard let maximumByteCount else { return }

        var totalByteCount: Int64 = 0
        for entry in entries where !entry.isDirectory {
            totalByteCount += Int64(entry.uncompressedSize)
            guard totalByteCount <= maximumByteCount else {
                throw ZipArchiveExtractorError.archiveTooLarge
            }
        }
    }

    private static func centralDirectoryEntries(in data: Data) throws -> [CentralDirectoryEntry] {
        let eocdOffset = try endOfCentralDirectoryOffset(in: data)
        let totalEntries = Int(try data.uint16LE(at: eocdOffset + 10))
        let centralDirectorySize = Int(try data.uint32LE(at: eocdOffset + 12))
        let centralDirectoryOffset = Int(try data.uint32LE(at: eocdOffset + 16))

        guard centralDirectoryOffset >= 0,
              centralDirectorySize >= 0,
              centralDirectoryOffset + centralDirectorySize <= data.count else {
            throw ZipArchiveExtractorError.invalidArchive
        }

        var entries: [CentralDirectoryEntry] = []
        var offset = centralDirectoryOffset

        for _ in 0..<totalEntries {
            guard try data.uint32LE(at: offset) == 0x0201_4B50 else {
                throw ZipArchiveExtractorError.invalidArchive
            }

            let flags = try data.uint16LE(at: offset + 8)
            guard flags & 0x0001 == 0 else {
                throw ZipArchiveExtractorError.encryptedArchive
            }

            let compressionMethod = try data.uint16LE(at: offset + 10)
            let crc32 = try data.uint32LE(at: offset + 16)
            let compressedSize = try data.uint32LE(at: offset + 20)
            let uncompressedSize = try data.uint32LE(at: offset + 24)
            let fileNameLength = Int(try data.uint16LE(at: offset + 28))
            let extraFieldLength = Int(try data.uint16LE(at: offset + 30))
            let commentLength = Int(try data.uint16LE(at: offset + 32))
            let localHeaderOffset = try data.uint32LE(at: offset + 42)
            let fileNameOffset = offset + 46
            let nextOffset = fileNameOffset + fileNameLength + extraFieldLength + commentLength

            guard nextOffset <= data.count else {
                throw ZipArchiveExtractorError.invalidArchive
            }

            let fileNameData = data.subdata(in: fileNameOffset..<(fileNameOffset + fileNameLength))
            let fileName = String(data: fileNameData, encoding: .utf8)
                ?? String(data: fileNameData, encoding: .isoLatin1)
                ?? ""

            entries.append(CentralDirectoryEntry(
                fileName: fileName,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                crc32: crc32,
                localHeaderOffset: localHeaderOffset
            ))
            offset = nextOffset
        }

        return entries
    }

    private static func endOfCentralDirectoryOffset(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw ZipArchiveExtractorError.invalidArchive
        }

        let minimumOffset = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
            if (try? data.uint32LE(at: offset)) == 0x0605_4B50 {
                return offset
            }
        }

        throw ZipArchiveExtractorError.invalidArchive
    }

    private static func fileData(for entry: CentralDirectoryEntry, in archiveData: Data) throws -> Data {
        let localHeaderOffset = Int(entry.localHeaderOffset)
        guard try archiveData.uint32LE(at: localHeaderOffset) == 0x0403_4B50 else {
            throw ZipArchiveExtractorError.invalidArchive
        }

        let fileNameLength = Int(try archiveData.uint16LE(at: localHeaderOffset + 26))
        let extraFieldLength = Int(try archiveData.uint16LE(at: localHeaderOffset + 28))
        let compressedDataOffset = localHeaderOffset + 30 + fileNameLength + extraFieldLength
        let compressedSize = Int(entry.compressedSize)
        guard compressedDataOffset + compressedSize <= archiveData.count else {
            throw ZipArchiveExtractorError.invalidArchive
        }

        let compressedData = archiveData.subdata(in: compressedDataOffset..<(compressedDataOffset + compressedSize))
        let outputData: Data

        switch entry.compressionMethod {
        case 0:
            outputData = compressedData
        case 8:
            outputData = try inflateRawDeflate(compressedData, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipArchiveExtractorError.unsupportedCompressionMethod
        }

        guard outputData.count == Int(entry.uncompressedSize) else {
            throw ZipArchiveExtractorError.decompressionFailed
        }

        let checksum = outputData.withUnsafeBytes { buffer in
            crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(outputData.count))
        }
        guard checksum == entry.crc32 else {
            throw ZipArchiveExtractorError.checksumMismatch
        }

        return outputData
    }

    private static func inflateRawDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw ZipArchiveExtractorError.decompressionFailed
        }
        defer { inflateEnd(&stream) }

        return try data.withUnsafeBytes { inputBuffer in
            var outputData = Data(count: max(expectedSize, 1))
            let outputCapacity = outputData.count
            let status: Int32 = outputData.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(data.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCapacity)
                return inflate(&stream, Z_FINISH)
            }

            guard status == Z_STREAM_END else {
                throw ZipArchiveExtractorError.decompressionFailed
            }

            outputData.count = Int(stream.total_out)
            return outputData
        }
    }

    private static func safeRelativePath(from fileName: String) throws -> String {
        let normalized = fileName.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0") else {
            throw ZipArchiveExtractorError.unsafePath
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw ZipArchiveExtractorError.unsafePath
        }

        return components.joined(separator: "/")
    }

    private static func shouldSkip(_ relativePath: String) -> Bool {
        relativePath == ".DS_Store" ||
            relativePath.hasPrefix("__MACOSX/") ||
            relativePath.hasSuffix("/.DS_Store")
    }

    private static func isDescendant(_ url: URL, of rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private struct CentralDirectoryEntry {
        let fileName: String
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let crc32: UInt32
        let localHeaderOffset: UInt32

        var isDirectory: Bool {
            fileName.hasSuffix("/")
        }
    }
}

struct ZipArchiveWriter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func archiveFolder(
        at folderURL: URL,
        to archiveURL: URL,
        excluding shouldExclude: ((String) -> Bool)? = nil
    ) throws {
        let relativePaths = try regularFileRelativePaths(in: folderURL, excluding: shouldExclude)
        guard !relativePaths.isEmpty else {
            throw ZipArchiveWriterError.emptyFolder
        }
        guard relativePaths.count <= Int(UInt16.max) else {
            throw ZipArchiveWriterError.tooManyFiles
        }

        try? fileManager.removeItem(at: archiveURL)
        try fileManager.createDirectory(
            at: archiveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: archiveURL.path, contents: nil)

        let handle = try FileHandle(forWritingTo: archiveURL)
        defer {
            try? handle.close()
        }

        var centralDirectoryEntries: [CentralDirectoryEntry] = []
        var offset: UInt64 = 0

        for relativePath in relativePaths {
            let fileURL = folderURL.appendingPathComponent(relativePath, isDirectory: false)
            let fileData = try Data(contentsOf: fileURL)
            guard fileData.count <= Int(UInt32.max) else {
                throw ZipArchiveWriterError.fileTooLarge
            }
            guard offset <= UInt64(UInt32.max) else {
                throw ZipArchiveWriterError.archiveTooLarge
            }

            let nameData = try Self.fileNameData(from: relativePath)
            let checksum = fileData.withUnsafeBytes { buffer in
                UInt32(crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(fileData.count)))
            }
            let fileSize = UInt32(fileData.count)
            let localHeaderOffset = UInt32(offset)
            var localHeader = Data()
            localHeader.appendUInt32LE(0x0403_4B50)
            localHeader.appendUInt16LE(20)
            localHeader.appendUInt16LE(Self.utf8Flag)
            localHeader.appendUInt16LE(0)
            localHeader.appendUInt16LE(Self.dosTime)
            localHeader.appendUInt16LE(Self.dosDate)
            localHeader.appendUInt32LE(checksum)
            localHeader.appendUInt32LE(fileSize)
            localHeader.appendUInt32LE(fileSize)
            localHeader.appendUInt16LE(UInt16(nameData.count))
            localHeader.appendUInt16LE(0)
            localHeader.append(nameData)

            try handle.write(contentsOf: localHeader)
            try handle.write(contentsOf: fileData)
            offset += UInt64(localHeader.count + fileData.count)

            centralDirectoryEntries.append(CentralDirectoryEntry(
                nameData: nameData,
                checksum: checksum,
                size: fileSize,
                localHeaderOffset: localHeaderOffset
            ))
        }

        guard offset <= UInt64(UInt32.max) else {
            throw ZipArchiveWriterError.archiveTooLarge
        }
        let centralDirectoryOffset = UInt32(offset)

        var centralDirectory = Data()
        for entry in centralDirectoryEntries {
            centralDirectory.appendUInt32LE(0x0201_4B50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(Self.utf8Flag)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(Self.dosTime)
            centralDirectory.appendUInt16LE(Self.dosDate)
            centralDirectory.appendUInt32LE(entry.checksum)
            centralDirectory.appendUInt32LE(entry.size)
            centralDirectory.appendUInt32LE(entry.size)
            centralDirectory.appendUInt16LE(UInt16(entry.nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(entry.localHeaderOffset)
            centralDirectory.append(entry.nameData)
        }

        guard centralDirectory.count <= Int(UInt32.max) else {
            throw ZipArchiveWriterError.archiveTooLarge
        }
        try handle.write(contentsOf: centralDirectory)

        var endRecord = Data()
        let entryCount = UInt16(centralDirectoryEntries.count)
        endRecord.appendUInt32LE(0x0605_4B50)
        endRecord.appendUInt16LE(0)
        endRecord.appendUInt16LE(0)
        endRecord.appendUInt16LE(entryCount)
        endRecord.appendUInt16LE(entryCount)
        endRecord.appendUInt32LE(UInt32(centralDirectory.count))
        endRecord.appendUInt32LE(centralDirectoryOffset)
        endRecord.appendUInt16LE(0)
        try handle.write(contentsOf: endRecord)
    }

    func regularFileRelativePaths(
        in folderURL: URL,
        excluding shouldExclude: ((String) -> Bool)? = nil
    ) throws -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            throw ZipArchiveWriterError.emptyFolder
        }

        var relativePaths: [String] = []
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let relativePath = Self.relativePath(of: fileURL, in: folderURL) else {
                continue
            }
            guard !Self.shouldSkip(relativePath) else { continue }
            guard shouldExclude?(relativePath) != true else { continue }
            relativePaths.append(relativePath)
        }

        return relativePaths.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func fileNameData(from relativePath: String) throws -> Data {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0") else {
            throw ZipArchiveWriterError.unsafePath
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw ZipArchiveWriterError.unsafePath
        }

        let safePath = components.joined(separator: "/")
        guard let data = safePath.data(using: .utf8),
              data.count <= Int(UInt16.max) else {
            throw ZipArchiveWriterError.unsafePath
        }
        return data
    }

    private static func relativePath(of fileURL: URL, in folderURL: URL) -> String? {
        let rootPath = folderURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func shouldSkip(_ relativePath: String) -> Bool {
        relativePath == ".DS_Store" ||
            relativePath.hasPrefix("__MACOSX/") ||
            relativePath.hasSuffix("/.DS_Store")
    }

    private static let utf8Flag: UInt16 = 0x0800
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x0021

    private struct CentralDirectoryEntry {
        let nameData: Data
        let checksum: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
    }
}

private extension Data {
    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw ZipArchiveExtractorError.invalidArchive
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw ZipArchiveExtractorError.invalidArchive
        }
        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x0000_00FF))
        append(UInt8((value >> 8) & 0x0000_00FF))
        append(UInt8((value >> 16) & 0x0000_00FF))
        append(UInt8((value >> 24) & 0x0000_00FF))
    }
}
