//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import UIKit
import SwiftUI
import AidokuRunner

class ReaderViewController: BaseObservingViewController {
    let manga: AidokuRunner.Manga
    var chapter: AidokuRunner.Chapter
    var pages: [Page] = []
    private var tapZone: TapZone?

    private var chapterList: [AidokuRunner.Chapter]
    private var chaptersToMark: [AidokuRunner.Chapter] = []
    private var chaptersToRemoveDownload: [AidokuRunner.Chapter] = [] {
        didSet {
            // ensure chapters queued for deletion are persistent, in case of app termination
            if chaptersToRemoveDownload.isEmpty {
                UserDefaults.standard.removeObject(forKey: "Data.chaptersToBeDeleted")
            } else {
                let data = try? JSONEncoder().encode(chaptersToRemoveDownload.map {
                    ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                })
                UserDefaults.standard.set(data, forKey: "Data.chaptersToBeDeleted")
            }
        }
    }
    private var currentPage = 1
    private var currentPosition: Double?
    private var sessionReadPages: Set<Int> = []
    private var sessionStartDate: Date?
    private var sessionLastInteraction: Date?

    private var hasAppeared = false
    /// The view controller the reader's back button returns to, whose back button title the
    /// reader hides while it's on screen.
    private weak var backButtonHost: UIViewController?

    weak var reader: ReaderReaderDelegate?

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var toolbarView = ReaderToolbarView()
    private var toolbarViewWidthConstraint: NSLayoutConstraint?

    private var squeezeTimer: Timer?
    private var longSqueezeTimer: Timer?
    private var squeezeStartTime: Date?
    private let doubleSqueezeInterval: TimeInterval = 0.3
    private let longSqueezeThreshold: TimeInterval = 0.5

    private lazy var descriptionButtonController: UIHostingController<ReaderPageDescriptionButtonView> = {
        let buttonView = ReaderPageDescriptionButtonView(source: nil, pages: [])
        let hostingController = UIHostingController(rootView: buttonView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.alpha = 0
        hostingController.view.isHidden = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController
    }()
    private lazy var pageDescriptionButtonBottomConstraint: NSLayoutConstraint =
        descriptionButtonController.view.bottomAnchor.constraint(
            equalTo: {
                if #available(iOS 16.0, *) {
                    view.bottomAnchor
                } else {
                    view.safeAreaLayoutGuide.bottomAnchor
                }
            }()
        )

    // fake zoom gesture so that the bar toggle gesture doesn't conflict with zooming
    private lazy var fakeZoomTapGesture: UITapGestureRecognizer = {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        return doubleTap
    }()

    private lazy var barToggleTapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.require(toFail: fakeZoomTapGesture)
        return tap
    }()

    var statusBarHidden = true

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        UIStatusBarAnimation.fade
    }
    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    init(
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter
    ) {
        precondition(manga.sourceKey == LocalSourceRunner.sourceKey, "Archive reader only accepts local manga")
        self.manga = manga
        self.chapter = chapter
        self.chapterList = manga.chapters ?? []
        self.chaptersToMark = [chapter]
        super.init()
        hidesBottomBarWhenPushed = true
    }

    override func configure() {
        node.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        // navbar buttons (the left side is left to the system back button)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "list.bullet"),
                style: .plain,
                target: self,
                action: #selector(openChapterList)
            )
        ]

        // fix navbar being clear
        let navigationBarAppearance = UINavigationBarAppearance()
        let toolbarAppearance = UIToolbarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        toolbarAppearance.configureWithDefaultBackground()
        // set on the navigation item rather than the bar, so the screen underneath keeps its own
        navigationItem.standardAppearance = navigationBarAppearance
        navigationItem.compactAppearance = navigationBarAppearance
        navigationItem.scrollEdgeAppearance = navigationBarAppearance
        navigationController?.toolbar.standardAppearance = toolbarAppearance
        navigationController?.toolbar.compactAppearance = toolbarAppearance
        if #available(iOS 15.0, *) {
            navigationController?.toolbar.scrollEdgeAppearance = toolbarAppearance
        }

        loadNavbarTitle()

        // toolbar view
        toolbarView.sliderView.addTarget(self, action: #selector(sliderMoved(_:)), for: .valueChanged)
        toolbarView.sliderView.addTarget(self, action: #selector(sliderStopped(_:)), for: .editingDidEnd)
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        let toolbarButtonItemView = UIBarButtonItem(customView: toolbarView)
        toolbarButtonItemView.customView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
        if #available(iOS 26.0, *) {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(
                equalToConstant: node.bounds.width - 32 - 10
            )
            // shift down farther to account for different toolbar and slider knob size
            toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -5)
        } else {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)
            toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -10)
        }

        add(child: descriptionButtonController)

        toolbarItems = [toolbarButtonItemView]
        navigationController?.toolbar.fitContentViewToToolbar()

        // loading indicator
        activityIndicator.startAnimating()
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        // bar toggle tap gesture
        fakeZoomTapGesture.isEnabled = !UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap")
        view.addGestureRecognizer(fakeZoomTapGesture)
        view.addGestureRecognizer(barToggleTapGesture)

        // The archive reader has a single rendering path: continuous Webtoon.
        toolbarView.sliderView.direction = .forward
        let pageController = ReaderWebtoonViewController(manga: manga)
        pageController.delegate = self
        reader = pageController
        add(child: pageController, below: descriptionButtonController.view)

        // set up apple pencil squeeze handler
        if #available(iOS 17.5, *) {
            let pencilInteraction = UIPencilInteraction(delegate: self)
            view.addInteraction(pencilInteraction)
        }

        // load current tap zone
        updateTapZone()

        // load chapter list
        loadCurrentChapter()
    }

    override func constrain() {
        toolbarViewWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            descriptionButtonController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            pageDescriptionButtonBottomConstraint
        ])
    }

    override func observe() {
        addObserver(forName: "Reader.disableDoubleTap") { [weak self] notification in
            self?.fakeZoomTapGesture.isEnabled = !(notification.object as? Bool ?? UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap"))
        }
        let reloadBlock: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        // reload pages when processors change
        addObserver(forName: "Reader.downsampleImages", using: reloadBlock)
        addObserver(forName: "Reader.upscaleImages", using: reloadBlock)
        addObserver(forName: "Reader.cropBorders", using: reloadBlock)
        addObserver(forName: "Reader.liveText", using: reloadBlock)
        addObserver(forName: "Reader.tapZones", using: reloadBlock)
        addObserver(forName: UIScene.willDeactivateNotification) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.updateReadPosition()
            }

            if #available(iOS 26.0, *) {
                statusBarHidden = false
            }
        }
        addObserver(forName: UIScene.didActivateNotification) { [weak self] _ in
            guard let self else { return }
            if self.sessionStartDate == nil {
                self.sessionReadPages = [self.currentPage]
                self.sessionStartDate = Date.now
                self.sessionLastInteraction = nil
            }
        }
        if #available(iOS 26.0, *) {
            addObserver(forName: UIScene.willEnterForegroundNotification) { [weak self] _ in
                if self?.navigationController?.isToolbarHidden == true {
                    self?.setBarsHidden(true, animated: false)
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if backButtonHost == nil, let viewControllers = navigationController?.viewControllers {
            let index = viewControllers.firstIndex { $0 === self }
            backButtonHost = index.flatMap { $0 > 0 ? viewControllers[$0 - 1] : nil }
        }
        backButtonHost?.navigationItem.backButtonDisplayMode = .minimal

        // open with the bars hidden, without animating: an animated hide would still be running
        // after a quick pop, and would then be changing bars that belong to the previous screen
        if !hasAppeared {
            hasAppeared = true
            setBarsHidden(true, animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        sessionReadPages = [self.currentPage]
        sessionStartDate = Date.now
        sessionLastInteraction = nil

        // an interactive pop that gets cancelled leaves the previous screen's bars behind
        if statusBarHidden {
            setBarsHidden(true, animated: false)
        }

        disableSwipeGestures()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        restoreSharedBars(animated: animated)

        // an interactive pop can still be cancelled, so don't touch stored data until it commits
        if let coordinator = transitionCoordinator, coordinator.isInteractive {
            coordinator.notifyWhenInteractionChanges { [weak self] context in
                guard !context.isCancelled else { return }
                self?.saveStateOnClose()
            }
        } else {
            saveStateOnClose()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // the width isn't known when the constraint is made, since the reader hasn't been laid
        // out into the navigation stack yet
        if #available(iOS 26.0, *) {
            toolbarViewWidthConstraint?.constant = view.bounds.width - 32 - 10
        } else {
            toolbarViewWidthConstraint?.constant = view.bounds.width
        }
    }

    /// The navigation bar and toolbar belong to the whole app, so the reader puts them back the
    /// way every other screen expects them: bar shown, toolbar hidden.
    private func restoreSharedBars(animated: Bool) {
        guard let navigationController else { return }
        navigationController.setNavigationBarHidden(false, animated: animated)
        navigationController.setToolbarHidden(true, animated: animated)
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        // the back button title belongs to the screen underneath, not to the reader
        backButtonHost?.navigationItem.backButtonDisplayMode = .default
    }

    private func saveStateOnClose() {
        if !chaptersToRemoveDownload.isEmpty {
            Task {
                await DownloadManager.shared.delete(chapters: chaptersToRemoveDownload.map {
                    .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                })
                chaptersToRemoveDownload = []
            }
        }

        guard currentPage >= 1 else { return }
        Task {
            await updateReadPosition()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            if #available(iOS 26.0, *) {
                self.toolbarViewWidthConstraint?.constant = size.width - 32 - 10
            } else {
                self.toolbarViewWidthConstraint?.constant = size.width
            }
        }
    }

    func disableSwipeGestures() {
        // the interactive pop gesture starts at the left screen edge, which the paged reader
        // needs for page turns
        let isWebtoonReader = reader is ReaderWebtoonViewController
        navigationController?.interactivePopGestureRecognizer?.isEnabled = isWebtoonReader
    }

    func updateReadPosition(
        currentPage: Int? = nil,
        totalPages: Int? = nil,
        chapter: AidokuRunner.Chapter? = nil
    ) async {
        let effectiveTotalPages = totalPages ?? toolbarView.totalPages ?? 0
        let effectiveCurrentPage = currentPage ?? self.currentPage

        guard
            !UserDefaults.standard.bool(forKey: "General.incognitoMode"),
            effectiveTotalPages > 0 // ensure chapter pages are loaded
        else {
            return
        }

        let currentPage = effectiveCurrentPage
        let chapter = chapter ?? self.chapter

        let sourceId = manga.sourceKey
        let mangaId = manga.key
        let chapterId = chapter.key
        let (completed, progress) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.getProgress(
                sourceId: sourceId,
                mangaId: mangaId,
                chapterId: chapterId,
                context: context
            )
        }
        let hasHistory = completed || progress != nil

        // don't add history if there is none and we're at the first page
        if currentPage == 1 && !hasHistory {
            return
        }

        await HistoryManager.shared.setProgress(
            chapter: chapter.toOld(sourceId: sourceId, mangaId: mangaId),
            progress: currentPage,
            totalPages: totalPages,
            scrollPosition: currentPosition,
            completed: completed
        )
        await saveReadingSession(chapter: chapter)
    }

    private func saveReadingSession(chapter: AidokuRunner.Chapter? = nil) async {
        guard let sessionStartDate else { return }
        let pagesRead = sessionReadPages.count
        if pagesRead > 0 && sessionLastInteraction != nil {
            let chapter = chapter ?? self.chapter
            await HistoryManager.shared.addSession(
                chapterIdentifier: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key),
                data: .init(startDate: sessionStartDate, endDate: .now, pagesRead: pagesRead)
            )
        }
        self.sessionStartDate = nil
    }

    func loadChapterList() async {
        chapterList = await LocalFileDataManager.shared.fetchChapters(mangaId: manga.key)
    }

    func loadCurrentChapter() {
        if chapterList.isEmpty {
            Task {
                await loadChapterList()
            }
        }

        let (completed, startPage) = CoreDataManager.shared.getProgress(
            sourceId: LocalSourceRunner.sourceKey,
            mangaId: manga.key,
            chapterId: chapter.key
        )
        if !completed, let startPage {
            currentPage = startPage
        } else {
            currentPage = -1
        }
        reader?.setChapter(chapter, startPage: currentPage)
    }

    func loadNavbarTitle() {
        let volume: String? =
            if chapter.chapterNumber != nil, let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
            } else {
                nil
            }

        let title =
            if let chapterNum = chapter.chapterNumber {
                String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
            } else if let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
            } else {
                chapter.title ?? ""
            }

        navigationItem.setTitle(upper: volume, lower: title)
    }

    func showLoadFailAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("FAILED_CHAPTER_LOAD", comment: ""),
            message: NSLocalizedString("FAILED_CHAPTER_LOAD_INFO", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    @objc func openReaderSettings() {
        let vc = UIHostingController(
            rootView: ReaderSettingsView()
        )
        present(vc, animated: true)
    }

    @objc func openChapterList() {
        var view = ReaderChapterListView(
            chapterList: chapterList,
            chapter: chapter
        )
        view.chapterSet = { [weak self] chapter in
            guard let self else { return }
            if chapter != self.chapter {
                self.setChapter(chapter)
                self.loadCurrentChapter()
            }
        }
        let vc = UIHostingController(rootView: view)
        present(vc, animated: true)
    }

    @objc func close() {
        navigationController?.popViewController(animated: true)
    }

    @objc func sliderMoved(_ sender: ReaderSliderView) {
        reader?.sliderMoved(value: sender.currentValue)
    }
    @objc func sliderStopped(_ sender: ReaderSliderView) {
        reader?.sliderStopped(value: sender.currentValue)
    }
}

// MARK: - Reader Holding Delegate
extension ReaderViewController: ReaderHoldingDelegate {
    var barsHidden: Bool { statusBarHidden }

    private func areDuplicates(_ a: AidokuRunner.Chapter, _ b: AidokuRunner.Chapter) -> Bool {
        a.chapterNumber == b.chapterNumber
            && a.volumeNumber == b.volumeNumber
            && (!(a.chapterNumber == nil && a.volumeNumber == nil) || a.title == b.title)
    }

    private func isValidScanlatorMatch(for next: AidokuRunner.Chapter, current: Set<String>) -> Bool {
        let nextScanlators = Set(next.scanlators ?? [])
        return current.isEmpty ? nextScanlators.isEmpty : !current.isDisjoint(with: nextScanlators)
    }

    private func findBestChapterMatch(from index: Int, step: Int) -> AidokuRunner.Chapter {
        let firstCandidate = chapterList[index]
        let currentScanlators = Set(chapter.scanlators ?? [])

        var i = index
        while i >= 0 && i < chapterList.count {
            let next = chapterList[i]
            guard areDuplicates(next, firstCandidate) else { break }

            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: next.key)
            let isReadable = !next.locked || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if isReadable && isValidScanlatorMatch(for: next, current: currentScanlators) {
                return next
            }
            i += step
        }

        return firstCandidate
    }

    func getNextChapter() -> AidokuRunner.Chapter? {
        guard
            var index = chapterList.firstIndex(of: chapter)
        else {
            return nil
        }

        let skipDuplicates = UserDefaults.standard.bool(forKey: "Reader.skipDuplicateChapters")
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index -= 1
        var nextChapterInList: AidokuRunner.Chapter?

        while index >= 0 {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)

                if nextChapterInList == nil {
                    nextChapterInList = new
                }
                if markDuplicates && isDuplicate {
                    chaptersToMark.append(new)
                }
                if !isDuplicate {
                    return skipDuplicates ? findBestChapterMatch(from: index, step: -1) : nextChapterInList
                } else if !skipDuplicates && !markDuplicates {
                    return new
                }
            }
            index -= 1
        }
        return nil
    }

    func getPreviousChapter() -> AidokuRunner.Chapter? {
        guard
            var index = chapterList.firstIndex(of: chapter)
        else {
            return nil
        }
        // find previous non-duplicate chapter
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index += 1
        while index < chapterList.count {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)
                if !isDuplicate {
                    return findBestChapterMatch(from: index, step: 1)
                }
                if markDuplicates {
                    chaptersToMark.append(new)
                }
            }
            index += 1
        }
        return nil
    }

    func setChapter(_ chapter: AidokuRunner.Chapter) {
        guard chapter != self.chapter else { return }

        // store current history data since it will change when new chapter loads
        let currentPage = currentPage
        let totalPages = toolbarView.totalPages
        let oldChapter = self.chapter
        Task {
            await updateReadPosition(currentPage: currentPage, totalPages: totalPages, chapter: oldChapter)
            sessionReadPages = [self.currentPage]
            sessionStartDate = Date.now
            sessionLastInteraction = nil
        }

        self.chapter = chapter
        self.chaptersToMark = [chapter]
        loadNavbarTitle()
    }

    func setCurrentPage(_ page: Int, position: Double? = nil) {
        setCurrentPages(page...page, position: position)
    }

    func setCurrentPages(_ pages: ClosedRange<Int>) {
        setCurrentPages(pages, position: nil)
    }

    private func setCurrentPages(_ pages: ClosedRange<Int>, position: Double? = nil) {
        guard let totalPages = toolbarView.totalPages else { return }

        updateDescriptionButton(pages: pages)

        sessionLastInteraction = Date.now
        for page in pages {
            guard page >= 1 && page <= totalPages else { continue }
            sessionReadPages.insert(page)
        }

        let page = max(1, min(pages.lowerBound, totalPages))
        currentPage = page
        currentPosition = position
        toolbarView.setProgress(currentPage: page, totalPages: totalPages)
        if pages.upperBound >= totalPages {
            setCompleted()
        }
    }

    private func updateDescriptionButton(pages: ClosedRange<Int>) {
        let pageItems = pages.compactMap { self.pages[safe: $0 - 1]?.toNew() }
        if pageItems.contains(where: { $0.hasDescription }) {
            descriptionButtonController.rootView = ReaderPageDescriptionButtonView(
                source: nil,
                pages: pageItems
            )
            descriptionButtonController.view.isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 1
            }
        } else {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 0
            } completion: { _ in
                self.descriptionButtonController.view.isHidden = true
            }
        }
    }

    func setPages(_ pages: [Page], currentPage: Int?) {
        self.pages = pages
        toolbarView.setProgress(
            currentPage: pages.isEmpty ? nil : currentPage,
            totalPages: pages.count
        )
        activityIndicator.stopAnimating()
        if pages.isEmpty {
            showLoadFailAlert()
        }
    }

    func displayPage(_ page: Int) {
        toolbarView.displayPage(page)
    }

    func setSliderOffset(_ offset: CGFloat) {
        toolbarView.sliderView.currentValue = offset
    }

    func setCompleted() {
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task {
                await HistoryManager.shared.addHistory(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
                    chapters: chaptersToMark
                )
            }
        }
        if UserDefaults.standard.bool(forKey: "Library.deleteDownloadAfterReading") {
            chaptersToRemoveDownload.append(chapter)
        }
    }
}

// MARK: - Tap Zones
extension ReaderViewController {
    func updateTapZone() {
        let enabledTapZone = UserDefaults.standard.string(forKey: "Reader.tapZones")
        let tapZone: TapZone? = switch enabledTapZone {
            case "auto": .lShaped
            case "left-right": .leftRight
            case "l-shaped": .lShaped
            case "kindle": .kindle
            case "edge": .edge
            default: nil
        }
        self.tapZone = tapZone
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let reader, let tapZone else {
            toggleBarVisibility()
            return
        }

        let point = gestureRecognizer.location(in: view)
        let relativePoint = CGPoint(
            x: point.x / view.bounds.width,
            y: point.y / view.bounds.height
        )

        let type = tapZone.regions
            .first { $0.bounds.contains(relativePoint) }
            .map(\.type)

        if let type {
            // hide the bars when tapping regardless
            if !statusBarHidden {
                hideBars()
            }
            // handle page moving
            if UserDefaults.standard.bool(forKey: "Reader.invertTapZones") {
                switch type {
                    case .left: reader.moveRight()
                    case .right: reader.moveLeft()
                }
            } else {
                switch type {
                    case .left: reader.moveLeft()
                    case .right: reader.moveRight()
                }
            }
        } else {
            toggleBarVisibility()
        }
    }

    @objc private func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        reader?.handleDoubleTap(at: gestureRecognizer.location(in: view))
    }
}

// MARK: - Apple Pencil Squeeze
extension ReaderViewController: UIPencilInteractionDelegate {
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // if pencil squeezing is disabled globally, ignore interaction (hig)
        guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }

        switch squeeze.phase {
            case .began:
                squeezeStartTime = Date()
                longSqueezeTimer = Timer.scheduledTimer(
                    withTimeInterval: longSqueezeThreshold,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.longSqueezeTimer = nil
                        self?.openChapterList()
                    }
                }
            case .ended:
                guard let startTime = squeezeStartTime else { return }
                let duration = Date().timeIntervalSince(startTime)
                squeezeStartTime = nil
                longSqueezeTimer?.invalidate()
                longSqueezeTimer = nil

                if duration >= longSqueezeThreshold {
                    // long squeeze: chapter selector
                    squeezeTimer?.invalidate()
                    squeezeTimer = nil
                    return
                } else {
                    if let timer = squeezeTimer {
                        // double squeeze: previous page
                        timer.invalidate()
                        squeezeTimer = nil
                        previousPage()
                    } else {
                        // single squeeze: next page
                        squeezeTimer = Timer.scheduledTimer(
                            withTimeInterval: doubleSqueezeInterval,
                            repeats: false
                        ) { [weak self] _ in
                            Task { @MainActor in
                                self?.squeezeTimer = nil
                                self?.nextPage()
                            }
                        }
                    }
                }
            default:
                break
        }

    }

    private func nextPage() {
        reader?.moveRight()
    }

    private func previousPage() {
        reader?.moveLeft()
    }
}

// MARK: - Bar Visibility
extension ReaderViewController {
    @objc func toggleBarVisibility() {
        if statusBarHidden {
            showBars()
        } else {
            hideBars()
        }
    }

    func showBars() {
        setBarsHidden(false, animated: true)
    }

    func hideBars() {
        setBarsHidden(true, animated: true)
    }

    /// Shows or hides every bar at once, letting the navigation controller animate its own.
    func setBarsHidden(_ hidden: Bool, animated: Bool) {
        guard let navigationController else { return }

        statusBarHidden = hidden
        NotificationCenter.default.post(name: hidden ? .readerHidingBars : .readerShowingBars, object: nil)

        navigationController.setNavigationBarHidden(hidden, animated: animated)
        navigationController.setToolbarHidden(hidden, animated: animated)

        pageDescriptionButtonBottomConstraint.constant = hidden ? 30 : 0

        let backgroundColor = readerBackgroundColor(barsHidden: hidden)
        let animations = {
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            self.node.backgroundColor = backgroundColor
            self.node.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration(), animations: animations)
        } else {
            animations()
        }
    }

    private func readerBackgroundColor(barsHidden: Bool) -> UIColor {
        if barsHidden {
            switch UserDefaults.standard.string(forKey: "Reader.backgroundColor") {
                case "system": return .systemBackground
                case "white": return .white
                default: return .black
            }
        }
        if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
            return .systemBackground
        }
        return UserDefaults.standard.integer(forKey: "General.appearance") == 0 ? .white : .black
    }
}

// MARK: - Keyboard Shortcuts
extension ReaderViewController {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_LEFT"),
                action: #selector(moveLeft),
                input: UIKeyCommand.inputLeftArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_RIGHT"),
                action: #selector(moveRight),
                input: UIKeyCommand.inputRightArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_FORWARD"),
                action: #selector(nextChapter),
                input: ","
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_BACKWARD"),
                action: #selector(previousChapter),
                input: "."
            ),
            UIKeyCommand(
                title: NSLocalizedString("OPEN_CHAPTER_LIST"),
                action: #selector(openChapterList),
                input: "\t"
            ),
            UIKeyCommand(
                title: NSLocalizedString("TOGGLE_BARS"),
                action: #selector(toggleBarVisibility),
                input: " "
            ),
            UIKeyCommand(
                title: NSLocalizedString("CLOSE_READER"),
                action: #selector(close),
                input: UIKeyCommand.inputEscape
            )
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc func moveLeft() {
        reader?.moveLeft()
    }

    @objc func moveRight() {
        reader?.moveRight()
    }

    @objc func nextChapter() {
        if let nextChapter = getNextChapter() {
            reader?.setChapter(nextChapter, startPage: 1)
            setChapter(nextChapter)
        }
    }

    @objc func previousChapter() {
        if let previousChaoter = getPreviousChapter() {
            reader?.setChapter(previousChaoter, startPage: 1)
            setChapter(previousChaoter)
        }
    }
}
