//
//  ReaderNavigationController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import UIKit

extension UINavigationController {
    /// Pushes the reader, stripping the title from the back button it returns to.
    func pushReader(_ readerViewController: ReaderViewController, animated: Bool = true) {
        topViewController?.navigationItem.backButtonDisplayMode = .minimal
        // the bar state has to be captured before the reader starts changing it
        readerViewController.captureNavigationState(from: self)
        pushViewController(readerViewController, animated: animated)
    }
}
