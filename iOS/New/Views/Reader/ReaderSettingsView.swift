//
//  ReaderSettingsView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/30/25.
//

import SwiftUI

struct ReaderSettingsView: View {
    @State private var tapZones: DefaultTapZones
    @StateObject private var downsampleImages = UserDefaultsBool(key: "Reader.downsampleImages")
    @StateObject private var upscaleImages = UserDefaultsBool(key: "Reader.upscaleImages")

    @Environment(\.dismiss) private var dismiss

    init() {
        self._tapZones = State(
            initialValue: UserDefaults.standard.string(forKey: "Reader.tapZones")
                .flatMap(DefaultTapZones.init) ?? .disabled
        )
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                generalSection
                tapZonesSection
                upscalingSection
                webtoonSection
            }
            .animation(.default, value: downsampleImages.value)
            .animation(.default, value: upscaleImages.value)
            .navigationTitle(NSLocalizedString("READER_SETTINGS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerTapZones)) { _ in
                tapZones = UserDefaults.standard.string(forKey: "Reader.tapZones")
                    .flatMap(DefaultTapZones.init) ?? .disabled
            }
        }
    }

    private var generalSection: some View {
        Section(NSLocalizedString("GENERAL")) {
            SettingView(setting: .init(
                key: "Reader.skipDuplicateChapters",
                title: NSLocalizedString("SKIP_DUPLICATE_CHAPTERS"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.markDuplicateChapters",
                title: NSLocalizedString("MARK_DUPLICATE_CHAPTERS"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.downsampleImages",
                title: NSLocalizedString("DOWNSAMPLE_IMAGES"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.cropBorders",
                title: NSLocalizedString("CROP_BORDERS"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.disableQuickActions",
                title: NSLocalizedString("DISABLE_QUICK_ACTIONS"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.disableDoubleTap",
                title: NSLocalizedString("DISABLE_DOUBLE_TAP_ZOOM"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.liveText",
                title: NSLocalizedString("LIVE_TEXT"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.hideBarsOnSwipe",
                title: NSLocalizedString("HIDE_BARS_ON_SWIPE"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.backgroundColor",
                title: NSLocalizedString("READER_BG_COLOR"),
                value: .select(.init(
                    values: ["system", "auto", "white", "black"],
                    titles: [
                        NSLocalizedString("READER_BG_COLOR_SYSTEM"),
                        NSLocalizedString("READER_BG_COLOR_AUTO"),
                        NSLocalizedString("READER_BG_COLOR_WHITE"),
                        NSLocalizedString("READER_BG_COLOR_BLACK")
                    ]
                ))
            ))
            if UIDevice.current.userInterfaceIdiom != .pad {
                SettingView(setting: .init(
                    key: "Reader.orientation",
                    title: NSLocalizedString("READER_ORIENTATION"),
                    notification: "Reader.orientation",
                    value: .select(.init(
                        values: ["device", "portrait", "landscape"],
                        titles: [
                            NSLocalizedString("FOLLOW_DEVICE"),
                            NSLocalizedString("PORTRAIT"),
                            NSLocalizedString("LANDSCAPE")
                        ]
                    ))
                ))
            }
        }
    }

    private var tapZonesSection: some View {
        Section(NSLocalizedString("TAP_ZONES")) {
            NavigationLink(destination: TapZonesSelectView()) {
                HStack {
                    Text(NSLocalizedString("TAP_ZONES"))
                    Spacer()
                    Text(tapZones.title).foregroundStyle(.secondary)
                }
            }
            SettingView(setting: .init(
                key: "Reader.invertTapZones",
                title: NSLocalizedString("INVERT_TAP_ZONES"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.animatePageTransitions",
                title: NSLocalizedString("ANIMATE_PAGE_TRANSITIONS"),
                value: .toggle(.init())
            ))
        }
    }

    @ViewBuilder
    private var upscalingSection: some View {
        if !downsampleImages.value {
            Section {
                SettingView(setting: .init(
                    key: "Reader.upscaleImages",
                    title: String(format: NSLocalizedString("%@_EXPERIMENTAL"), NSLocalizedString("UPSCALE_IMAGES")),
                    value: .toggle(.init())
                ))
                if upscaleImages.value {
                    NavigationLink(destination: UpscaleModelListView()) {
                        Text(NSLocalizedString("UPSCALING_MODELS"))
                    }
                    SettingView(setting: .init(
                        key: "Reader.upscaleMaxHeight",
                        title: NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT"),
                        value: .stepper(.init(minimumValue: 200, maximumValue: 4000, stepValue: 100))
                    ))
                }
            } header: {
                Text(NSLocalizedString("UPSCALING"))
            } footer: {
                if upscaleImages.value {
                    Text(NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT_TEXT"))
                }
            }
        }
    }

    private var webtoonSection: some View {
        Section {
            SettingView(setting: .init(
                key: "Reader.verticalInfiniteScroll",
                title: NSLocalizedString("INFINITE_VERTICAL_SCROLL"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.pillarbox",
                title: NSLocalizedString("PILLARBOX"),
                value: .toggle(.init())
            ))
            SettingView(setting: .init(
                key: "Reader.pillarboxAmount",
                title: NSLocalizedString("PILLARBOX_AMOUNT"),
                requires: "Reader.pillarbox",
                value: .stepper(.init(minimumValue: 5, maximumValue: 95, stepValue: 5))
            ))
            SettingView(setting: .init(
                key: "Reader.pillarboxOrientation",
                title: NSLocalizedString("PILLARBOX_ORIENTATION"),
                requires: "Reader.pillarbox",
                value: .select(.init(
                    values: ["both", "portrait", "landscape"],
                    titles: [NSLocalizedString("BOTH"), NSLocalizedString("PORTRAIT"), NSLocalizedString("LANDSCAPE")]
                ))
            ))
        } header: {
            Text(NSLocalizedString("WEBTOON"))
        } footer: {
            Text(NSLocalizedString("PILLARBOX_ORIENTATION_INFO"))
        }
    }
}
