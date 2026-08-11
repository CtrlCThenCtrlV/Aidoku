//
//  NavigationController.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 11/02/2024.
//

import UIKit

class NavigationController: UINavigationController {
    // This is a workaround to fix an iOS bug that occurs when mixing UIKit with SwiftUI,
    // that causes the current TabBarItem title to be lost when navigating inside SwiftUI views.
    // See: https://stackoverflow.com/questions/62662313/uitabbar-containing-swiftui-view
    private var storedTabBarItem: UITabBarItem?
    override var tabBarItem: UITabBarItem! {
        get { storedTabBarItem ?? super.tabBarItem }
        set { storedTabBarItem = newValue }
    }

    // fix for incognito mode banner status bar text being the wrong color sometimes on ios 26+
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            traitCollection.userInterfaceStyle == .light ? .darkContent : .lightContent
        } else {
            .default
        }
    }

    // let the top view controller hide the bars, which the reader does
    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        topViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // uikit turns the pop gesture off while the navigation bar is hidden, which the reader
        // does for its entire lifetime
        interactivePopGestureRecognizer?.delegate = self
    }
}

// MARK: - Gesture Recognizer Delegate
extension NavigationController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        // popping the root, or interrupting a transition, leaves the navigation stack broken
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}
