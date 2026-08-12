//
//  LocalModels.swift
//  Aidoku
//
//  Created by Skitty on 6/10/25.
//

import CoreData
import Foundation

enum LocalFileManagerError: Error {
    case invalidFileType
    case tempDirectoryUnavailable
    case cannotReadArchive
    case noImagesFound
    case invalidImage
    case fileCopyFailed
}

struct ArchivePageMetadata: Codable, Hashable, Sendable {
    let path: String
    let width: Int
    let height: Int
    let orientation: Int?
    let hasAlpha: Bool?

    var displayWidth: Int {
        swapsDimensions ? height : width
    }

    var displayHeight: Int {
        swapsDimensions ? width : height
    }

    private var swapsDimensions: Bool {
        guard let orientation else { return false }
        return (5...8).contains(orientation)
    }
}

struct ArchiveChapterManifest: Codable, Hashable, Sendable {
    static let version: Int16 = 2

    let pages: [ArchivePageMetadata]

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        try PropertyListDecoder().decode(Self.self, from: data)
    }
}

@objc(ArchiveManifestObject)
final class ArchiveManifestObject: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var mangaId: String
    @NSManaged var chapterId: String
    @NSManaged var archivePath: String
    @NSManaged var archiveModifiedAt: Date
    @NSManaged var archiveFileSize: Int64
    @NSManaged var manifestVersion: Int16
    @NSManaged var pagesData: Data
}

extension ArchiveManifestObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ArchiveManifestObject> {
        NSFetchRequest<ArchiveManifestObject>(entityName: "ArchiveManifest")
    }
}

struct StoredArchiveManifest: Sendable {
    let archivePath: String
    let modifiedAt: Date
    let fileSize: Int64
    let manifest: ArchiveChapterManifest
}

struct LocalSeriesInfo: Hashable {
    let coverUrl: String
    let name: String
    let chapterCount: Int
}

enum LocalFileType {
    case cbz
    case zip

    var localizedName: String {
        switch self {
            case .cbz: NSLocalizedString("CBZ_NAME")
            case .zip: NSLocalizedString("ZIP_NAME")
        }
    }
}

struct ImportFileInfo: Hashable {
    let url: URL
    let previewImages: [PlatformImage]
    let name: String
    let pageCount: Int
    let fileType: LocalFileType
    let comicInfo: ComicInfo?
}
