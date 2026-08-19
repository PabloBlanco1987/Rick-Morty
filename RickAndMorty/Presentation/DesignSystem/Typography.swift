import SwiftUI

/// The app's text tokens.
///
/// All are aliases over the system's *text styles* — `.headline`, `.subheadline`,
/// `.caption` — never a point size. That's what keeps Dynamic Type working up to AX5
/// without touching anything: a `.system(size: 17)` stays pinned at 17 even if the user
/// asked for 43, and a screen that reads fine today stops being readable. A token here
/// only picks *role*; size stays the user's choice in Settings.
///
/// These live in `extension Font`, not inside `Theme`, so call sites stay as short as
/// the system API — `.font(.cardTitle)` next to `.font(.headline)` — and because the
/// target type already disambiguates: no prefix is needed to know it's a font. Numeric
/// tokens don't have that luck — a `CGFloat` is a `CGFloat` whether it's a gap or a
/// radius — so they live with their full name in `Theme`.
extension Font {
    // The character's name on the detail screen — the screen's title.
    static let screenTitle: Font = .largeTitle.bold()
    // "Information", "Episodes": what opens a section within a screen.
    static let sectionTitle: Font = .title2.bold()
    // The name in a list cell.
    static let cardTitle: Font = .headline

    // The three weights of body text, where most of the variety used to live.
    // Distinguished by emphasis, not location: the same `.label` works for a cell's
    // species, a row's label, or an episode's name, so no new token is needed each
    // time a screen appears.
    static let label: Font = .subheadline
    // A row's value, and the symbols next to it.
    static let labelEmphasis: Font = .subheadline.weight(.medium)
    // A notice or error's headline, and the episode count.
    static let labelStrong: Font = .subheadline.weight(.semibold)

    // A notice's body: what happened and what can be done.
    static let message: Font = .footnote
    // What accompanies a value without being the value: an episode's air date.
    static let metadata: Font = .caption

    // A chip's text.
    static let chipLabel: Font = .caption.weight(.medium)
    // An episode's code. Monospaced because "S01E01" and "S03E10" are the same kind of
    // data with different content: aligned, the season reads at a glance down the
    // column.
    static let chipCode: Font = .caption.monospaced().weight(.semibold)

    // The gray silhouette for an image placeholder while it hasn't loaded.
    static let placeholderIcon: Font = .largeTitle
}
