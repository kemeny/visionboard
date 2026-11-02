# VisionBoard for iPhone and iPhone Duo

A native SwiftUI version of the web board. It reads and writes the same board
through the sync Worker in `worker/`, so a board started on the web opens here
and changes flow both ways.

## Open and run

1. Open `ios/VisionBoard.xcodeproj` in Xcode 27.1 or later (needed for the iPhone Duo APIs).
2. Pick your team under Signing & Capabilities.
3. Run on an iPhone, the iPhone Duo simulator, or Xcode's Device Hub to preview Duo poses.

On an older Xcode, remove `IPHONE_DUO_SDK` from the target's
`SWIFT_ACTIVE_COMPILATION_CONDITIONS`. The app still builds and runs; it just
skips the Duo-only APIs. CI does this automatically (`.github/workflows/ios.yml`).

## What's in it

| Tab | What it does |
| --- | --- |
| Board | The collage. Drag paper to pan, pinch to zoom. Drag, pinch or twist a clipping to move, resize or rotate it. Long-press for actions, Style for fonts and colors. |
| Feed | One clipping per page, endless, ranked like the web feed. Double-tap to like. |
| Today | Today's goal and photo, plus the week ahead. |
| Settings | Turn on sync, show the QR code and link, join a board by scanning the web app's QR code, daily reminders. |

**Share sheet.** VisionBoard shows up in every app's share sheet (WhatsApp,
Photos, Safari, Instagram). Photos come in as photos, a video as a still from
the clip, a link as its preview image, and text as a goal with a random style.
The extension (`VisionBoardShare/`) can't open the app, so it writes into the
App Group `group.com.kemenystudio.visionboard` (see `Shared/ShareInbox.swift`)
and the app puts everything on the board the next time it comes to the front.

**Widget.** "Today's Goal" for the Home Screen (small, medium, large) and the
Lock Screen (rectangular, inline). The app writes two weeks of goals and
photos into the App Group (`Shared/WidgetSnapshot.swift`) whenever the board
changes, so the widget turns the page each day on its own.

**Wallpaper.** Board menu > Make Wallpaper renders the whole board below the
Lock Screen clock, or today's photo and goal, at this iPhone's screen size.

Reminders are local notifications scheduled two weeks ahead on the device, so
they need no server and work offline.

## iPhone Duo

Following Apple's [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo):

- Size classes only, no fixed widths: compact layout on the outer display, regular on the inner one.
- Standard tab bar and toolbars, so the system puts them down the side. Every toolbar item has a title and a symbol, primary actions come first.
- Board options live in the system overflow menu (`toolbarOverflowMenu`, iOS 27).
- The board is task-oriented, so when side bars run out of room it keeps its actions and minimizes the tab bar (`toolbarVerticalCompressionBehavior(.prefersToolbarItems)`, iOS 27.1).
- On the inner display the style inspector becomes a trailing column instead of a sheet, and Today puts the card and the week side by side in an `ArrangementView`.
- Folding or unfolding keeps the same spot of the board in the middle instead of jumping.
- The full-screen Today card reads the fold (`reservedRegions(kind: .division)`) so the goal never runs across the crease.

The Duo-only calls are in `VisionBoard/Views/DuoSupport.swift`.

## Configuration

`VB_WEB_ORIGIN` (target build setting) is the web app's address. The app calls
`$VB_WEB_ORIGIN/api/sync/*` and builds share links from it. It is set to
`https://visionboard.kemenystudio.com`.
