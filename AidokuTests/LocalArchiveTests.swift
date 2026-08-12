//
//  LocalArchiveTests.swift
//  AidokuTests
//

import Testing
@testable import Aidoku

@Suite struct LocalArchiveTests {
    @Test(
        "Archive page filtering",
        arguments: [
            ("001.jpg", true),
            ("chapter/002.PNG", true),
            ("chapter/003.webp", true),
            ("chapter/.004.jpg", false),
            (".hidden/005.jpg", false),
            ("ComicInfo.xml", false),
            ("001.txt", false),
            ("001.md", false),
            ("001.pdf", false)
        ]
    )
    func archivePageFiltering(path: String, expected: Bool) {
        #expect(LocalFileManager.isArchivePage(path: path) == expected)
    }

    @Test("Supported archive extensions")
    func supportedArchiveExtensions() {
        #expect(LocalFileManager.allowedFileExtensions == ["cbz", "zip"])
    }

    @Test("Binary chapter manifest round trip")
    func binaryManifestRoundTrip() throws {
        let manifest = ArchiveChapterManifest(pages: [
            .init(path: "001.jpg", width: 800, height: 2400, orientation: 1, hasAlpha: false),
            .init(path: "nested/002.webp", width: 1080, height: 4096, orientation: nil, hasAlpha: true)
        ])
        let data = try manifest.encoded()
        #expect(data.starts(with: Data("bplist".utf8)))
        #expect(try ArchiveChapterManifest.decode(data) == manifest)
    }

    @Test("EXIF orientation swaps display dimensions")
    func orientedManifestDimensions() {
        let page = ArchivePageMetadata(path: "001.jpg", width: 1200, height: 800, orientation: 6, hasAlpha: false)
        #expect(page.displayWidth == 800)
        #expect(page.displayHeight == 1200)
    }
}
