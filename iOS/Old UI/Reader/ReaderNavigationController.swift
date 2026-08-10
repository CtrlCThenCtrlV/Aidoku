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
        pushViewController(readerViewController, animated: animated)
    }
}
