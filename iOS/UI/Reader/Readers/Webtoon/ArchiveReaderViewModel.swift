//
//  ArchiveReaderViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation
import AidokuRunner

@MainActor
class ArchiveReaderViewModel {
    let manga: AidokuRunner.Manga
    var chapter: AidokuRunner.Chapter?
    var pages: [Page] = []

    var preloadedChapter: AidokuRunner.Chapter?
    var preloadedPages: [Page] = []

    init(manga: AidokuRunner.Manga) {
        self.manga = manga
    }

    func loadPages(chapter: AidokuRunner.Chapter) async {
        if preloadedChapter == chapter {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else {
            if !pages.isEmpty {
                preloadedChapter = chapter
                preloadedPages = pages
            }
            self.chapter = chapter
            pages = await getPages(chapter: chapter)
        }
    }

    func preload(chapter: AidokuRunner.Chapter) async {
        guard preloadedChapter != chapter else { return }
        preloadedChapter = nil
        preloadedPages = await getPages(chapter: chapter)
        preloadedChapter = chapter
    }

    private func getPages(chapter: AidokuRunner.Chapter) async -> [Page] {
        guard manga.sourceKey == LocalSourceRunner.sourceKey else { return [] }
        return await LocalFileManager.shared.fetchPages(mangaId: manga.key, chapterId: chapter.key)
            .map { $0.toOld(sourceId: LocalSourceRunner.sourceKey, chapterId: chapter.key) }
    }
}
