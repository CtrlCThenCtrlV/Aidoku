//
//  ReaderWebtoonViewController.swift
//  Aidoku (iOS)
//

import AidokuRunner
import ImageIO
import UIKit
import ZIPFoundation

/// A cell-free Webtoon reader. Chapter manifests form one continuous canvas and
/// image views are materialized only around the viewport.
@MainActor
final class ReaderWebtoonViewController: BaseObservingViewController {
    weak var delegate: ReaderHoldingDelegate?

    private let manga: AidokuRunner.Manga
    private let scrollView = UIScrollView()
    private let canvasView = UIView()

    private struct ChapterBlock {
        let chapter: AidokuRunner.Chapter
        let archiveURL: URL
        let metadata: [ArchivePageMetadata]
        let pages: [Page]
        var range: Range<CGFloat> = 0..<0
    }

    private struct PageLayout {
        let key: String
        let chapterIndex: Int
        let pageIndex: Int
        let archiveURL: URL
        let path: String
        let pixelWidth: Int
        let pixelHeight: Int
        let frame: CGRect
    }

    private var blocks: [ChapterBlock] = []
    private var pageLayouts: [PageLayout] = []
    private var visibleViews: [String: UIImageView] = [:]
    private var imageTasks: [String: Task<Void, Never>] = [:]
    private var imageScales: [String: CGFloat] = [:]
    private var reusePool: [UIImageView] = []
    private var currentChapterIndex = 0
    private var previousPage = 0
    private var isSliding = false
    private var loadingPrevious = false
    private var loadingNext = false
    private var initialStartPage = 1
    private var lastLayoutWidth: CGFloat = 0
    private var isPinchZooming = false
    private var isDoubleTapZooming = false

    init(manga: AidokuRunner.Manga) {
        self.manga = manga
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        super.configure()
        view.backgroundColor = .black
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.scrollsToTop = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.decelerationRate = .normal
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        scrollView.addSubview(canvasView)
        view.addSubview(scrollView)
    }

    override func constrain() {
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.width != lastLayoutWidth else { return }
        let oldBlock = blocks[safe: currentChapterIndex]
        let oldProgress = chapterProgress(in: oldBlock)
        lastLayoutWidth = view.bounds.width
        rebuildLayout()
        if let oldBlock, let index = blocks.firstIndex(where: { $0.chapter == oldBlock.chapter }) {
            scrollToProgress(oldProgress, blockIndex: index)
        }
    }

    override func observe() {
        addObserver(forName: UIApplication.didReceiveMemoryWarningNotification.rawValue) { [weak self] _ in
            self?.trimImages(to: self?.scrollView.bounds ?? .zero)
        }
    }
}

// MARK: - Loading and layout
private extension ReaderWebtoonViewController {
    private func loadBlock(chapter: AidokuRunner.Chapter) async -> ChapterBlock? {
        guard
            let stored = await LocalFileManager.shared.fetchManifest(mangaId: manga.key, chapterId: chapter.key),
            !stored.manifest.pages.isEmpty
        else { return nil }
        let archiveURL = FileManager.default.documentDirectory.appendingPathComponent(stored.archivePath)
        let values = try? archiveURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard
            archiveURL.exists,
            Int64(values?.fileSize ?? -1) == stored.fileSize,
            values?.contentModificationDate == stored.modifiedAt
        else { return nil }
        let pages = await LocalFileManager.shared.fetchPages(mangaId: manga.key, chapterId: chapter.key)
            .map { $0.toOld(sourceId: LocalSourceRunner.sourceKey, chapterId: chapter.key) }
        guard pages.count == stored.manifest.pages.count else { return nil }
        return ChapterBlock(
            chapter: chapter,
            archiveURL: archiveURL,
            metadata: stored.manifest.pages,
            pages: pages
        )
    }

    func rebuildLayout() {
        guard scrollView.bounds.width > 0 else { return }
        let width = scrollView.bounds.width
        var y: CGFloat = 0
        var layouts: [PageLayout] = []
        for blockIndex in blocks.indices {
            let start = y
            for (pageIndex, page) in blocks[blockIndex].metadata.enumerated() {
                let height = width * CGFloat(page.height) / CGFloat(page.width)
                let frame = CGRect(x: 0, y: y, width: width, height: height)
                layouts.append(PageLayout(
                    key: "\(blocks[blockIndex].chapter.key)\u{1f}\(pageIndex)",
                    chapterIndex: blockIndex,
                    pageIndex: pageIndex,
                    archiveURL: blocks[blockIndex].archiveURL,
                    path: page.path,
                    pixelWidth: page.width,
                    pixelHeight: page.height,
                    frame: frame
                ))
                y += height
            }
            blocks[blockIndex].range = start..<y
        }
        pageLayouts = layouts
        canvasView.frame = CGRect(x: 0, y: 0, width: width, height: y)
        scrollView.contentSize = canvasView.bounds.size
        updateVisiblePages()
    }

    private func prepend(_ block: ChapterBlock) {
        let oldOffset = scrollView.contentOffset.y
        blocks.insert(block, at: 0)
        currentChapterIndex += 1
        rebuildLayout()
        let insertedHeight = blocks[0].range.upperBound
        scrollView.contentOffset.y = oldOffset + insertedHeight
        updateVisiblePages()
    }

    private func append(_ block: ChapterBlock) {
        blocks.append(block)
        rebuildLayout()
    }

    private func chapterProgress(in block: ChapterBlock?) -> CGFloat {
        guard let block, block.range.upperBound > block.range.lowerBound else { return 0 }
        let middle = scrollView.contentOffset.y + scrollView.bounds.height / 2
        return min(1, max(0, (middle - block.range.lowerBound) / (block.range.upperBound - block.range.lowerBound)))
    }

    func scrollToProgress(_ progress: CGFloat, blockIndex: Int) {
        guard let block = blocks[safe: blockIndex] else { return }
        let middle = block.range.lowerBound + (block.range.upperBound - block.range.lowerBound) * progress
        let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.contentOffset.y = min(maximum, max(0, middle - scrollView.bounds.height / 2))
        updateVisiblePages()
    }

    func updateVisiblePages(loadAtCurrentScale: Bool = true) {
        guard !pageLayouts.isEmpty else { return }
        let viewport = scrollView.convert(scrollView.bounds, to: canvasView)
        let preload = viewport.insetBy(dx: 0, dy: -viewport.height * 1.5)
        let wanted = pageLayouts.filter { $0.frame.intersects(preload) }
        let wantedKeys = Set(wanted.map(\.key))

        for key in visibleViews.keys where !wantedKeys.contains(key) {
            guard let imageView = visibleViews.removeValue(forKey: key) else { continue }
            imageTasks.removeValue(forKey: key)?.cancel()
            imageView.removeFromSuperview()
            imageView.image = nil
            imageScales[key] = nil
            reusePool.append(imageView)
        }
        for layout in wanted {
            if let imageView = visibleViews[layout.key] {
                imageView.frame = layout.frame
                if loadAtCurrentScale {
                    loadImage(for: layout, into: imageView, scale: scrollView.zoomScale)
                }
            } else {
                show(layout)
            }
        }
    }

    func trimImages(to rect: CGRect) {
        let rect = scrollView.convert(rect, to: canvasView)
        for (key, imageView) in visibleViews where !imageView.frame.intersects(rect) {
            imageTasks.removeValue(forKey: key)?.cancel()
            imageView.image = nil
            imageScales[key] = nil
        }
    }

    private func show(_ layout: PageLayout) {
        let imageView = reusePool.popLast() ?? UIImageView()
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        imageView.frame = layout.frame
        canvasView.addSubview(imageView)
        visibleViews[layout.key] = imageView

        loadImage(for: layout, into: imageView, scale: scrollView.zoomScale)
    }

    private func loadImage(for layout: PageLayout, into imageView: UIImageView, scale: CGFloat) {
        let scale = max(1, scale)
        guard imageScales[layout.key, default: 0] + 0.01 < scale, imageTasks[layout.key] == nil else { return }
        let targetWidth = min(
            CGFloat(layout.pixelWidth),
            max(1, layout.frame.width * UIScreen.main.scale * scale)
        )
        let targetLongestDimension = targetWidth * max(
            1,
            CGFloat(layout.pixelHeight) / CGFloat(layout.pixelWidth)
        )
        imageTasks[layout.key] = Task { [weak self, weak imageView] in
            let image = await Self.loadImage(
                archiveURL: layout.archiveURL,
                path: layout.path,
                targetLongestDimension: targetLongestDimension
            )
            guard
                !Task.isCancelled,
                let self,
                let image,
                self.visibleViews[layout.key] === imageView
            else {
                if !Task.isCancelled {
                    self?.imageTasks[layout.key] = nil
                }
                return
            }
            imageView?.image = image
            self.imageScales[layout.key] = scale
            self.imageTasks[layout.key] = nil
        }
    }

    nonisolated static func loadImage(
        archiveURL: URL,
        path: String,
        targetLongestDimension: CGFloat
    ) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                do {
                    let archive = try Archive(url: archiveURL, accessMode: .read)
                    guard let entry = archive[path] else { return nil }
                    var data = Data()
                    _ = try archive.extract(entry) { data.append($0) }
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: Int(ceil(targetLongestDimension))
                    ]
                    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                        return nil
                    }
                    return UIImage(cgImage: image)
                } catch {
                    return nil
                }
            }
        }.value
    }
}

// MARK: - Scroll view
extension ReaderWebtoonViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvasView }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisiblePages(loadAtCurrentScale: !isPinchZooming && !isDoubleTapZooming)
        guard !isSliding, scrollView.zoomScale == 1 else { return }
        updateReadingPosition()
        preloadAtEdges()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if UserDefaults.standard.bool(forKey: "Reader.hideBarsOnSwipe") {
            delegate?.hideBars()
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateVisiblePages(loadAtCurrentScale: false)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        isPinchZooming = true
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        isPinchZooming = false
        reloadVisibleImagesForCurrentScale()
    }

    private func updateReadingPosition() {
        let middle = scrollView.contentOffset.y + scrollView.bounds.height / 2
        guard let blockIndex = blocks.firstIndex(where: { $0.range.contains(middle) }) else { return }
        if blockIndex != currentChapterIndex {
            currentChapterIndex = blockIndex
            let block = blocks[blockIndex]
            delegate?.setChapter(block.chapter)
            delegate?.setPages(block.pages)
        }
        guard let layout = pageLayouts.first(where: { $0.chapterIndex == blockIndex && $0.frame.contains(CGPoint(x: 1, y: middle)) }) else {
            return
        }
        let page = layout.pageIndex + 1
        if page != previousPage {
            previousPage = page
            delegate?.setCurrentPage(page, position: nil)
        }
    }

    private func preloadAtEdges() {
        guard UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll") else { return }
        let threshold = scrollView.bounds.height * 3
        if scrollView.contentOffset.y < threshold, !loadingPrevious {
            loadingPrevious = true
            Task { [weak self] in
                guard let self else { return }
                defer { loadingPrevious = false }
                guard let chapter = delegate?.getPreviousChapter(), !blocks.contains(where: { $0.chapter == chapter }) else { return }
                if let block = await loadBlock(chapter: chapter) { prepend(block) }
            }
        }
        let remaining = scrollView.contentSize.height - scrollView.bounds.height - scrollView.contentOffset.y
        if remaining < threshold, !loadingNext {
            loadingNext = true
            Task { [weak self] in
                guard let self else { return }
                defer { loadingNext = false }
                guard let chapter = delegate?.getNextChapter(), !blocks.contains(where: { $0.chapter == chapter }) else {
                    if delegate?.getNextChapter() == nil { delegate?.setCompleted() }
                    return
                }
                if let block = await loadBlock(chapter: chapter) { append(block) }
            }
        }
    }
}

// MARK: - Reader delegate
extension ReaderWebtoonViewController: ReaderReaderDelegate {
    func moveLeft() { moveViewport(by: -scrollView.bounds.height * 2 / 3) }
    func moveRight() { moveViewport(by: scrollView.bounds.height * 2 / 3) }

    private func moveViewport(by amount: CGFloat) {
        let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let offset = CGPoint(x: 0, y: min(maximum, max(0, scrollView.contentOffset.y + amount)))
        scrollView.setContentOffset(offset, animated: UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions"))
    }

    func sliderMoved(value: CGFloat) {
        isSliding = true
        guard let block = blocks[safe: currentChapterIndex] else { return }
        let maximum = max(block.range.lowerBound, block.range.upperBound - scrollView.bounds.height)
        scrollView.contentOffset.y = block.range.lowerBound + (maximum - block.range.lowerBound) * value
        let page = pageAtViewportMiddle(in: currentChapterIndex)
        delegate?.displayPage(page)
    }

    func sliderStopped(value: CGFloat) {
        isSliding = false
        updateReadingPosition()
    }

    func handleDoubleTap(at point: CGPoint) {
        guard !isPinchZooming else { return }
        isDoubleTapZooming = true
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let targetScale: CGFloat = 2
            let point = canvasView.convert(point, from: view)
            let size = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            scrollView.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.isDoubleTapZooming = false
            self.reloadVisibleImagesForCurrentScale()
        }
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        initialStartPage = max(1, startPage)
        imageTasks.values.forEach { $0.cancel() }
        imageTasks.removeAll()
        imageScales.removeAll()
        visibleViews.values.forEach { $0.removeFromSuperview() }
        visibleViews.removeAll()
        blocks.removeAll()
        pageLayouts.removeAll()
        Task { [weak self] in
            guard let self, let block = await loadBlock(chapter: chapter) else { return }
            var loadedBlocks = [block]
            if UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll") {
                if let previous = delegate?.getPreviousChapter(), let previousBlock = await loadBlock(chapter: previous) {
                    loadedBlocks.insert(previousBlock, at: 0)
                }
                if let next = delegate?.getNextChapter(), let nextBlock = await loadBlock(chapter: next) {
                    loadedBlocks.append(nextBlock)
                }
            }
            blocks = loadedBlocks
            currentChapterIndex = blocks.firstIndex(where: { $0.chapter == chapter }) ?? 0
            rebuildLayout()
            delegate?.setPages(block.pages)
            let pageIndex = min(max(0, initialStartPage - 1), block.metadata.count - 1)
            if let layout = pageLayouts.first(where: {
                $0.chapterIndex == self.currentChapterIndex && $0.pageIndex == pageIndex
            }) {
                scrollView.contentOffset.y = layout.frame.minY
            }
            updateVisiblePages()
            previousPage = pageIndex + 1
            delegate?.setCurrentPage(pageIndex + 1, position: nil)
            preloadAtEdges()
        }
    }

    private func pageAtViewportMiddle(in chapterIndex: Int) -> Int {
        let middle = scrollView.contentOffset.y + scrollView.bounds.height / 2
        return (pageLayouts.first { $0.chapterIndex == chapterIndex && $0.frame.contains(CGPoint(x: 1, y: middle)) }?.pageIndex ?? 0) + 1
    }

    private func reloadVisibleImagesForCurrentScale() {
        for key in visibleViews.keys {
            imageTasks.removeValue(forKey: key)?.cancel()
        }
        updateVisiblePages()
    }
}
