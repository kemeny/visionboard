import SwiftUI

// iPhone Duo adaptations (see Apple's "Designing for iPhone Duo" HIG page).
//
// Most of the work is done by the system: standard tab bars, toolbars, sheets
// and inspectors move to the side and around the fold on their own, as long
// as nothing uses fixed widths. The few Duo-only APIs below need the iOS 27.1
// SDK, so they compile only when IPHONE_DUO_SDK is set (it is by default; the
// CI workflow clears it on older Xcodes) and run only on iOS 27.1 or later.

extension View {
    // The board is task-oriented: when side bars run short of room, keep the
    // board's actions and minimize the tab bar
    @ViewBuilder
    func prefersToolbarItemsWhenCompressed() -> some View {
        #if IPHONE_DUO_SDK
        if #available(iOS 27.1, *) {
            toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        } else {
            self
        }
        #else
        self
        #endif
    }

    // Board-wide options that always live in the system overflow menu. Before
    // iOS 27 there is no system overflow, so they get their own "More" menu.
    @ViewBuilder
    func boardOverflowMenu<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        #if IPHONE_DUO_SDK
        if #available(iOS 27.0, *) {
            toolbarOverflowMenu { content() }
        } else {
            legacyOverflowMenu(content)
        }
        #else
        legacyOverflowMenu(content)
        #endif
    }

    private func legacyOverflowMenu<Content: View>(_ content: @escaping () -> Content) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    content()
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

// A primary and secondary view side by side on a wide display, and stacked on
// a narrow one. On iOS 27.1 this is the system ArrangementView, which also
// keeps both panes clear of the fold when iPhone Duo is half open.
struct AdaptiveArrangement<Primary: View, Secondary: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        if sizeClass == .regular {
            #if IPHONE_DUO_SDK
            if #available(iOS 27.1, *) {
                ArrangementView(primary: primary, secondary: secondary)
                    .arrangementViewStyle(.split)
            } else {
                fallbackSplit
            }
            #else
            fallbackSplit
            #endif
        } else {
            // Compact width (the outer display, or any other iPhone): one
            // scrolling column, primary first
            ScrollView {
                VStack(spacing: 24) {
                    primary()
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.72 }
                    secondary()
                }
            }
        }
    }

    private var fallbackSplit: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                HStack(spacing: 0) {
                    primary().frame(maxWidth: .infinity)
                    Divider()
                    secondary().frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    primary().frame(maxHeight: .infinity)
                    Divider()
                    secondary().frame(maxHeight: .infinity)
                }
            }
        }
    }
}

// Keeps a view's content in one half when a half-open iPhone Duo folds the
// display, instead of letting text run across the crease.
struct FoldAware<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if IPHONE_DUO_SDK
        if #available(iOS 27.1, *) {
            GeometryReader { proxy in
                let division = proxy.reservedRegions(kind: .division).first
                content()
                    .padding(.leading, division.map { $0.frame.height > $0.frame.width ? $0.frame.maxX : 0 } ?? 0)
                    .padding(.top, division.map { $0.frame.width > $0.frame.height ? $0.frame.maxY : 0 } ?? 0)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
