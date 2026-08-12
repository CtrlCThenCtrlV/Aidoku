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
}
