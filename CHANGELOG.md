# Changelog

All notable changes to Pesty are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Chinese (Simplified) localization, alongside English. Every user-facing
  string in the app - the strip, card menus, the editor, every Settings pane,
  the About window, alerts, and the sync status line - now goes through a
  single lookup, and the bundled `zh-Hans.lproj/Localizable.strings` holds the
  translations.
- "Interface language" in Settings → General, with Follow System, English, and
  简体中文. Switching takes effect immediately: the main menu, the menu-bar
  menu, open windows, and the strip all relabel in place, with no relaunch.
  Clips keep their original text either way.
- Relative timestamps and card dates follow the interface language instead of
  the system locale, so a card reads "12 seconds ago" or "12 秒钟前" to match
  the rest of the UI.
- Pinboards carry a color, and every card in a board paints its header band in
  that color instead of in the color of the app it was copied from - the band is
  what tells you which board you are looking at. The palette is eight colors
  written into the source (`Pinboard.palette`), and a new board picks one at
  random so the tab row does not read as one blue control.
- Right-clicking a board opens a menu with the eight swatches along its foot,
  the way Paste does it, and the board's current color is drawn ringed. Picking
  one recolors the board, its tab dot, and every card in it.
- Dragging a card onto a board's tab pins it there. The tab highlights while the
  card hovers over it, and dropping moves the clip the same way the card menu's
  "Pin" does: no copy, and the clip stays in history.

### Changed
- The strip now follows Paste's banded card design: each card is a square whose
  top carries a solid band colored from the source app icon's dominant color,
  with the card type and age on the left and the app icon filling the band's
  right end, the content below, and a single centered metadata line along the
  bottom. Cards measure 262 pt square with 21 pt gaps at the default bar height,
  14 pt corners, and a 4 pt selection ring in the system accent blue.
- The bar floats the way Paste's panel does instead of sitting flush against the
  screen: 8 pt of desktop shows along the left, right, and bottom edges, all four
  corners round at 24 pt, and the glass fills the window so those corners are
  drawn in view rather than parked below the window edge. Search and the pinboard
  pills sit centered between the edge actions.
- Light-mode glass carries no tint, which lands the panel on the same color Paste
  renders over both a colored wallpaper and a light backdrop.
- Pasting an image writes the stored PNG straight to the pasteboard instead of
  decoding and re-encoding it, and the target app is activated before the write
  so the app switch overlaps it rather than stacking after it. Apps that only
  read `public.tiff` still get a TIFF, but it is encoded lazily on request, so a
  large screenshot no longer stalls the bar while it hides.
- A plain mouse wheel now scrolls the strip. A horizontal `ScrollView` only
  consumes horizontal deltas, so a wheel — which is vertical by nature — did
  nothing over the cards; its delta is bent onto the strip's axis while the
  pointer is over it, and left alone everywhere else in the bar.
- The bar resizes the way Paste's does: its whole top edge is draggable (the
  pointer becomes a resize cursor, Escape cancels mid-drag), and the card size
  follows the bar height between 150 and 320 pt. The Settings toggle now only
  controls whether the visible grip pill is drawn.
- Cards are no longer tinted per source app, so the "Clip Colors" section is
  gone from Settings along with the per-app color assignment it drove. Clips
  read the same regardless of where they came from, which is what makes the
  title, date, and icon legible over every card.
- The iCloud sync status is now derived from a state enum instead of a stored
  string, so it re-renders in the current language rather than freezing at
  whatever language was active when the state last changed.
- `scripts/build_app.sh` and `scripts/build_mas.sh` copy the SwiftPM resource
  bundle into the app, and `Info.plist` declares `en` and `zh-Hans`.
- The search field expands in place, the way Paste's does: a single width drives
  the capsule and the field together, so the magnifier stays put while the pill
  grows out to its right instead of the two swapping places. The expanded state
  is a blue-ringed capsule with the same fill the tab pills use.
- A pinned clip's band carries only its title. The age and the source app icon
  belong to history - a log is read by when and where - so a pinboard card drops
  both, and the title sits vertically centred in the band instead of hanging
  from a fixed top inset. Centring also keeps it in the middle of the band at
  every bar height, rather than leaving more empty band below it as the user
  drags the bar taller.
- A pinned clip keeps its board's band in history too. The band is the board's
  color wherever the clip is shown, so the same clip looks the same in both
  places and history only adds the age on top; the source app icon goes with
  the log, so a pinned card in history drops it just as the board does.
- Pinboard pills now show a hover fill between the selected and idle states,
  their dots grew from 7 to 12 pt to match Paste's, and the gap between pills
  went from 2 to 6 pt.

### Fixed
- Renaming a clip now shows on the card. The band's first line reads the clip's
  own name when it has one and its type when it does not, so a rename is visible
  in the strip instead of only in the menu that set it.
- The search field collapses when a click lands anywhere that is not a card or
  the search and tab chrome - empty strip space included - and when a pinboard
  pill or a tab is chosen. Clicks on the tabs still collapse on mouse-up rather
  than mouse-down, so the row does not widen out from under the pointer before
  the click lands.
- Dropping a card on a board pins it on the frame the mouse comes up. A SwiftUI
  drop target can only answer through `NSItemProvider`, and the drag session
  that owns the drag image lives until that round trip finishes - measured at
  334-411 ms here, with the main thread idle and the pin itself taking 0.1 ms,
  so the card sat frozen for a third of a second after the release. The board
  tab now receives through AppKit's `NSDraggingDestination`, whose
  `performDragOperation` returns synchronously inside the mouse-up and ends the
  session there, and the drag carries the clip's id so the drop moves the clip
  already in the store.
- A cancelled drag no longer leaves the board row deaf. The drop target sits
  invisibly over every tab and only claims mouse events while one of our cards
  is in flight; a drag cancelled inside the strip, or released over another app,
  never told it the drag was over, so it kept holding the whole tab and the next
  click on any tab did nothing until the bar was hidden and reopened. The hit
  test now also checks what kind of event it is being asked about, and clears
  the stale marker when it declines.
- The global hotkey no longer goes permanently deaf. A failed registration used
  to be retried five times and then abandoned, which is indistinguishable from
  the shortcut having stopped working until the app was relaunched; it now falls
  back to a ten-second poll and picks the combination up whenever whatever held
  it lets go. Changing the shortcut while a retry was in flight also used to
  lose the new one - the older chain re-registered the previous combination, or
  cancelled the new one every second - and a reload now retires every chain
  started before it.
- The drag image matches the card it came from. Snapshotting the view dragged
  along the selection ring, whose corner radius is larger than the card's and
  therefore not concentric with it, so a selected card left a blue crescent at
  each corner; the ring, the hover stroke and the shadow now stay behind.

## [1.3.0] - 2026-10-08

The v2 wave of features from @alvst (#80), each reviewed and landed with the
author's commits, plus everything merged since 1.2.0: undo for deletions, image
previews on cards, a real search field, a full clip context menu with an
editor, multi-select, retention limits and dragging clips out of Pesty.

### Added
- Image clips, and file clips that point at one image, show the picture edge
  to edge over a checkerboard; other file clips show the file's Finder icon,
  with a "File not found" caption when the file is gone. Decoding happens off
  the main thread behind a bounded cache. (#96, #102)
- Command-Z puts a deleted clip, or a whole bulk delete, back where it was for five
  minutes, and an Undo button sits in the bar while something is restorable.
  Hold Option while deleting to skip it for that deletion, or turn on "Delete
  permanently" in Settings. The undo stack is in memory only: nothing deleted
  is written back to disk or synced. (#88)
- The search indicator is a real, editable field. Return pastes the selected
  clip, Command-1 to Command-9 still quick-paste, and the arrow keys move the selection
  while typing. (#85, #101)
- Command-C copies the selected clip and moves it to the front of history. (#82)
- Paste as Clean Formatting or as Markdown from the card menu. (#93)
- Command-Left and Command-Right switch between History and Pinboards. (#83)
- Clip color themes (Default, Vibrant, Accent Shades) and a choice of where the
  selected clip sits in the strip. (#94)
- History can be limited by clip count or by age. The age limit is a slider
  with named presets from 1 Day to Forever, applied when the drag ends and
  confirmed when it would remove clips. Pruning is local and never removes
  clips from other devices. (#76, #89)
- An optional live-resize handle on the Paste Bar, off by default. (#87)
- "Play sound when copying from Pesty", separate from the paste sound. (#90)
- History's size on disk in Settings, covering history and pinboards. (#91)
- Real pixel dimensions for image clips and real paths for file clips in the
  card footer. (#95)
- "Promote pasted clips to the top of history", off by default. (#92)
- Icons on the bar's overflow menu. (#84)
- Double-click a Pinboard tab to rename it. (#103, #100)
- A full clip context menu: Paste to the target app, Paste as Plain Text, Copy,
  Edit in a rich-text editor with Writing Tools, Rename, Pin, Preview, Share
  and Delete. (#78)
- Multi-select: Command-click toggles a card, Shift-click extends the range, and
  deleting more than one clip asks first with the exact count. (#77)
- Drag clips out of Pesty into other apps or Finder: links as URLs, images as
  PNG, files as file URLs, rich text as RTF. (#73)
- The quick-paste and plain-text modifiers are configurable. (#71)
- A bare Backspace deletes the selected clip when no search is active, ignoring
  key repeat and a query that was just cleared. (#70)
- A preference to keep the bar open when clicking outside; a pinned bar no
  longer covers full-screen apps. (#74)
- Copies made through other clipboard tools attribute to the real origin app
  through the org.nspasteboard.source marker. (#72)
- The bar adopts Liquid Glass and the clip cards get a clearer visual
  hierarchy. (#14, #15)
- A standalone SwiftPM smoke test. (#79)

### Fixed
- A direct paste blocked by a missing Accessibility grant says so once in the
  toast instead of silently copying. (#92)
- The bulk-delete button no longer collapses to icon-only in narrow layouts.
  (#86)
- Copying a Pinboard clip back to history gives it its own identity, so sync
  cannot evict it. (#82)
- Editing a clip can no longer make CloudKit delete the clip that was just
  edited. (#78)
- The clip strip returns to its start each time the bar opens. (#69)
- Pesty shows the Paste Bar when it is reopened. (#68)
- Deleting is scoped to the collection on screen. (#67)
- The bar's key monitor is scoped to its own panel and the paste target is
  resolved from the app that was frontmost before the bar. (#66)
- Long search queries keep the newest typed text visible. (#75)
- The sync control is hidden in builds where sync is off. (#7)

[1.3.0]: https://github.com/momenbasel/pesty/releases/tag/v1.3.0

## [1.2.0] - 2026-08-11

Bug fixes for multi-monitor setups and a bar that could stop opening, plus a
per-app privacy filter. The Mac App Store build also gains iCloud sync.

### Added
- Privacy: exclude chosen apps from clipboard history. Nothing copied while an
  excluded app is frontmost is recorded. The list starts empty.
- Pause clipboard capture from the menu bar or with `⌘⇧P` while the bar is open,
  and open Settings with `⌘⇧S`.
- Preference to hide the menu bar icon. Opening Pesty again from Finder or
  Spotlight brings it back.
- Quit button in Settings, since the app has no application menu and `⌘Q` does
  not reach it.
- Mac App Store build only: history and pinboards sync across devices through
  CloudKit, including the iPhone app. The Homebrew and direct-download builds are
  unchanged - CloudKit needs an App Store provisioning profile.

### Fixed
- The Paste Bar could stop opening entirely until Pesty was relaunched. The bar's
  visibility was read from a window flag that only cleared inside an animation
  completion handler, and a dropped handler left the app convinced the bar was
  already up, so every hotkey press tried to hide it. Presentation state is now
  explicit and no longer depends on the animation. (#64)
- On multi-monitor setups the bar could appear on the wrong display and fly
  across the bezel. Screen selection now hit-tests the pointer properly, and the
  bar slides its content inside a parked panel rather than moving the window
  through the space between displays. (#63)
- The global hotkey could be lost for good if another app held the combination
  during login or a display change. Registration now retries and keeps the
  previous binding if the new one will not take.
- Sleep, wake, docking, and resolution changes no longer leave the bar stranded
  on a display that is gone.
- Building from source no longer resets the Accessibility permission on every
  build.

[1.2.0]: https://github.com/momenbasel/pesty/releases/tag/v1.2.0

## [1.1.0] - 2026-06-26

Visual overhaul to match Paste, plus iCloud sync.

### Added
- iCloud Drive sync (opt-in) for history and pinboards across your Macs.
- Live Accessibility permission status in Settings, with a Restart button.

### Changed
- Redesigned cards: per-source-app colored header band, app-icon tile, type
  label, verbose relative time, and a footer with character count + quick-paste
  number — a faithful match to Paste.
- Spring animations for selection, hover, and scrolling; taller default strip.
- Top bar now has a sync toggle, search indicator, a "Clipboard" tab, and a
  "…" overflow menu.

### Fixed
- Search input and keyboard navigation reliability.
- Removed the unnecessary Apple Events entitlement.

[1.1.0]: https://github.com/momenbasel/pesty/releases/tag/v1.1.0

## [1.0.0] - 2026-06-26

Initial public release.

### Added
- Slide-up clipboard strip with a global hotkey (default `⌘⇧V`).
- Color-coded cards for text, rich text, links, images, files, and colors, each
  showing source app, editable title, copy time, preview, and character count.
- Pinboards: named, color-tagged collections of saved clips.
- Instant search across the full history.
- Keyboard navigation: arrows to move, `return` to paste, `⌘1`–`⌘9` quick-paste,
  `⌘⌫` to delete, `esc` to close.
- Direct paste into the previously active app via synthesized `⌘V`.
- Privacy: ignores concealed (password-manager) clips.
- Menu-bar item, preferences window, configurable hotkey, launch at login.
- Universal binary (Apple Silicon + Intel), signed with Developer ID and
  notarized by Apple.

[1.0.0]: https://github.com/momenbasel/pesty/releases/tag/v1.0.0
