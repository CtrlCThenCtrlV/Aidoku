//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Combine
import UIKit

class ReaderToolbarView: UIView {
    private var isSettingProgress = false

    var currentPageValue: Int? {
        didSet {
            if oldValue != currentPageValue {
                let feedbackGenerator = UISelectionFeedbackGenerator()
                feedbackGenerator.selectionChanged()
            }
        }
    }
    var currentPage: Int? {
        didSet {
            if !isSettingProgress {
                updatePageLabels()
                updateSliderPosition()
            }
        }
    }
    var totalPages: Int? {
        didSet {
            if !isSettingProgress {
                updatePageLabels()
                updateSliderPosition()
            }
        }
    }

    let sliderView = ReaderSliderView()
    private let incognitoModeLabel = UILabel()
    private let currentPageLabel = UILabel()
    private let pagesLeftLabel = UILabel()

    private var cancellables: [AnyCancellable] = []

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
        observe()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        incognitoModeLabel.font = .systemFont(ofSize: 10)
        incognitoModeLabel.textColor = .secondaryLabel
        incognitoModeLabel.textAlignment = .left
        incognitoModeLabel.isHidden = !UserDefaults.standard.bool(forKey: "General.incognitoMode")
        addSubview(incognitoModeLabel)

        currentPageLabel.font = .systemFont(ofSize: 10)
        currentPageLabel.textAlignment = .center
        currentPageLabel.sizeToFit()
        addSubview(currentPageLabel)

        pagesLeftLabel.font = .systemFont(ofSize: 10)
        pagesLeftLabel.textColor = .secondaryLabel
        pagesLeftLabel.textAlignment = .right
        addSubview(pagesLeftLabel)

        sliderView.semanticContentAttribute = .playback // for rtl languages
        addSubview(sliderView)
    }

    func constrain() {
        incognitoModeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        pagesLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            incognitoModeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            incognitoModeLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            currentPageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            currentPageLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            pagesLeftLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            pagesLeftLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            sliderView.heightAnchor.constraint(equalToConstant: 12),
            sliderView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            // inset far enough that the knob doesn't sit in the screen edge back gesture area
            sliderView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sliderView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        ])
    }

    func observe() {
        NotificationCenter.default.publisher(for: .incognitoMode)
            .sink { [weak self] _ in
                self?.incognitoModeLabel.isHidden = !UserDefaults.standard.bool(forKey: "General.incognitoMode")
            }
            .store(in: &cancellables)
    }

    // allow slider thumb to be touched outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews where subview is ReaderSliderView {
            if subview.subviews.contains(where: { $0.bounds.contains(convert(point, to: $0)) }) {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }

    func displayPage(_ page: Int) {
        guard let totalPages = totalPages else {
            return
        }
        var page = page
        if page > totalPages {
            page = totalPages
        } else if page < 1 {
            page = 1
        }
        currentPageLabel.text = String(format: NSLocalizedString("%i_OF_%i", comment: ""), page, totalPages)
        currentPageValue = page
    }

    func updatePageLabels() {
        guard var currentPage = currentPage, let totalPages = totalPages else {
            currentPageLabel.text = nil
            pagesLeftLabel.text = nil
            return
        }

        if currentPage > totalPages {
            currentPage = totalPages
        } else if currentPage < 1 {
            currentPage = 1
        }
        let pagesLeft = totalPages - currentPage
        currentPageLabel.text = String(format: NSLocalizedString("%i_OF_%i", comment: ""), currentPage, totalPages)
        if pagesLeft < 1 {
            pagesLeftLabel.text = nil
        } else {
            pagesLeftLabel.text = pagesLeft == 1
                ? NSLocalizedString("ONE_PAGE_LEFT", comment: "")
                : String(format: NSLocalizedString("%i_PAGES_LEFT", comment: ""), pagesLeft)
        }
        incognitoModeLabel.text = NSLocalizedString("INCOGNITO_MODE")
    }

    func setProgress(currentPage: Int?, totalPages: Int?) {
        isSettingProgress = true
        self.currentPage = currentPage
        self.totalPages = totalPages
        isSettingProgress = false
        updatePageLabels()
        updateSliderPosition()
    }

    func updateSliderPosition() {
        guard let currentPage, let totalPages, totalPages > 0, (1...totalPages).contains(currentPage) else {
            sliderView.move(toValue: 0)
            return
        }
        sliderView.move(toValue: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }
}
