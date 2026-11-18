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
| Board | The collage. Moving around is a native scroll view: drag with one finger anywhere (even across photos) to pan, flick to glide, pinch with two fingers to zoom and move at once, and the edges rubber-band. Double-tap paper to zoom in, again to go back. Tap a clipping to select it; drag the selected one to move it and its corner handle to resize and turn it (turns snap straight). Long-press a clipping for its menu. The dot or line grid scales with the board and fades between levels so it stays readable at any zoom. A bar at the bottom holds the selected clipping's actions, or Undo, Redo and Fit Board. |
| Feed | One clipping per page, endless, ranked like the web feed. Double-tap to like. |
| Today | Today's goal and photo, plus the week ahead. |
| Settings | Turn on sync, show the QR code and link, join a board by scanning the web app's QR code, an optional Apple account for backup, daily reminders. |

**Boards.** Tap the board's name at the top to switch, create, rename or delete
boards. Each board is its own file under `Application Support/VisionBoard/boards/`
(`Model/BoardLibrary.swift`) and syncs on its own key, so one can be shared and
another kept private. The share sheet asks which board to add to.

**Create with AI** (Pro). Board + menu > Create with AI, or the empty board.
Someone writes a few sentences about the year they want; the sync Worker
(`worker/src/ai.ts`) asks Claude for 6 to 9 short goals in the app's language
and finds an Unsplash photo for each. They tap to leave out anything that
doesn't fit, and Add to Board downloads the photos like picked ones and lays
everything out as a collage (`Views/AIBoardView.swift`). Each photo keeps its
Unsplash credit in the item's `credit` field, shown in the Style inspector.

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

**VisionBoard Pro.** A StoreKit 2 subscription (no third-party SDK) in the
"VisionBoard Pro" group: `com.kemenystudio.visionboard.pro.yearly` (with a
7-day free trial) and `com.kemenystudio.visionboard.pro.monthly`.
`Model/ProAccess.swift` loads the products, buys, restores
(`AppStore.sync()`), listens to `Transaction.updates` from launch and turns
Pro on from verified `Transaction.currentEntitlements` only. Gate features with
`ProAccess.shared.isPro`, or `ProAccess.shared.requirePro(from: "source")`,
which shows `Views/PaywallView.swift` (via `AppRouter.paywallSource`) when Pro
is off. The free plan keeps one board; people who already have more keep them.
For local testing the shared scheme runs with `ios/StoreKit/VisionBoardPro.storekit`
(outside the synced folders, so it never ships in the app). The products must
also be created in App Store Connect with the same ids before release.

**Sharing.** A clipping's Share menu has Share (the photo, or the goal as a
card) and Share as Story (a 1080 x 1920 picture of the clipping on the board
paper). Board menu > Share Board fits the whole board into the same story
frame (`Views/StoryShare.swift`). Free plans get a small "Made with
VisionBoard" mark on stories and a tiny one on wallpapers; Pro removes both
through `ProAccess`. Every share also carries
`https://visionboard.kemenystudio.com/?ref=share` for link previews.

**Account (optional).** Settings > Account signs in with Apple
(`Account/AccountService.swift`). It is only for backup and never required.
Signing in turns on sync for every board and backs up the list of boards
(name and sync key) to the Worker, encrypted there (see `worker/README.md`).
The list is uploaded again whenever a board is created, renamed or deleted or
a sync key changes. On a new iPhone, Settings shows "Restore from Your Apple
Account": signing in connects each backed-up board by its key. Signing out
keeps the boards and their sync. Delete Account removes the account and,
if asked, every board's cloud copy. If the Apple Account stops using the app
(revoked), the app signs out on the next launch. Once a board has 5 or more
things on it, a one-time banner suggests backing up.

Reminders are local notifications scheduled two weeks ahead on the device, so
they need no server and work offline.

**Progress.** Select a clipping and tap I Did It (bottom bar, long-press menu
or Feed) to mark a goal done. It keeps its place with a small seal, and the
item's `achievedAt` (ISO time, optional, same field as the web) syncs with the
board. Done goals show up in about 3 feed rounds in 10, and Today, the widget
and reminders pick a goal still to do unless every goal is done
(`DailyCard.pick`, same rotation as the Worker). The app counts the days it
was opened on this device (`Model/Progress.swift`). With Settings > Weekly
Recap and Check-ins on (the default) and notifications already allowed, it
schedules a Sunday recap at the reminder time (6 PM when daily reminders are
off) that opens `RecapView`, and, while daily reminders are off, a "Your
board misses you" check-in 7 days out that each open pushes back
(`Model/Recaps.swift`). From December 15 to January 15 the Today tab shows a
"Your Year" card with a shareable recap (`Views/YearRecapView.swift`).

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

`VB_POSTHOG_KEY` and `VB_POSTHOG_HOST` (target build settings) feed the
PostHog client in `VisionBoard/Analytics/Analytics.swift`. The key is a public
client token; leave it empty to turn analytics off. Events are anonymous (a
random id made on the device), never carry board content, and stop entirely
when Settings > Share Anonymous Usage is off.
