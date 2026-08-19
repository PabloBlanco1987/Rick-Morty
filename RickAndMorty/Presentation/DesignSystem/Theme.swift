import SwiftUI

/// The app's style decisions, in one place.
///
/// Before this, each view chose its own, and the tally said it all: six different radii
/// for four shapes, three green opacities that look identical, and a screen margin that
/// was 16 in the list and 20 in the detail. None of that looks like a bug on its own,
/// but it's exactly what makes an app feel assembled from pieces.
///
/// The system is deliberately small: only tokens the project was already deciding by
/// hand. Whatever the platform already solves — `Form`, `ContentUnavailableView`, button
/// styles, materials, semantic colors — stays as-is; a design system that fights iOS
/// conventions costs more than it gives.
///
/// Three more rules govern it, enforced where they apply:
///   · no view writes a style literal (if a new one is needed, it's a token);
///   · text tokens are aliases over *text styles*, never point sizes, which is what
///     keeps Dynamic Type intact — see `Typography.swift`;
///   · the scale governs distances *between* elements; a component's intrinsic sizes —
///     the badge dot, the icon box side — live with it, since they scale with type size
///     and mean nothing outside it.
enum Theme {
    /// Scale of 4, with a step of 2 for what sits almost flush.
    ///
    /// Names are sized, not purposed, on purpose: a spacing value doesn't know whether
    /// it separates a title from its body or two cells, and naming it `sectionGap`
    /// forces a new name the next time the same gap is needed elsewhere. Purpose-named
    /// tokens are `Layout`'s, which do have that.
    enum Spacing {
        // Between two lines of the same block: a title and its date, a headline and
        // its message. Less than this is line spacing, not separation.
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
        // Between a screen's sections — the only gap that must read as "something new
        // starts here" without needing a divider line.
        static let xxLarge: CGFloat = 32
    }

    /// Three radii for three roles, not six for four shapes.
    ///
    /// Radius size signals how big the piece is: the larger the surface, the larger the
    /// curve. With 14 on the notice, 16 on the cell, and 18 on the info block, three
    /// same-sized pieces curved differently for no reason at all.
    enum Radius {
        // Small pieces that wrap text or an icon: chips, episode codes, symbol boxes.
        static let chip: CGFloat = 10
        // Any content surface: cells, blocks, notices.
        static let card: CGFloat = 16
        // The large detail image, the only piece of its size.
        static let hero: CGFloat = 20
    }

    /// Measurements that do have purpose names, since they only mean something in
    /// place: a max width isn't "large", it's "what the API's avatar measures".
    enum Layout {
        // Same margin on both screens. When the list used 16 and the detail used 20,
        // the difference was invisible in any single screenshot but showed when
        // navigating between them: content jumped 4 points sideways.
        static let screenMargin = Spacing.large
        static let gridSpacing = Spacing.large

        // At accessibility sizes the name needs the full width, so the grid drops to
        // one column rather than truncate text.
        static let gridMinimumColumnWidth: CGFloat = 150
        static let accessibilityGridMinimumColumnWidth: CGFloat = 280

        // API avatars are 300 px: full-width on a full-screen iPad would stretch to a
        // thousand points. On iPhone the cap never kicks in.
        static let heroImageMaxWidth: CGFloat = 360
        // A two-line notice spanning an iPad's width reads worse than centered and
        // capped; this is the classic reading-column width.
        static let noticeMaxWidth: CGFloat = 560

        // Enough cells to fill a tall screen. Fewer would leave a gap below that gives
        // away that nothing has loaded yet.
        static let skeletonCardCount = 8
        static let skeletonEpisodeCount = 4
    }

    /// The accent color and its fill.
    ///
    /// A code constant, not an asset-catalog color: `.green` already adapts to light,
    /// dark, and increased contrast, while a custom color would require hand-redefining
    /// those variants just to land on the same green. The day there's a brand color,
    /// this line changes — or becomes `Color("Accent")` — and no view needs touching.
    enum Tint {
        static let accent: Color = .green

        // One opacity for every tinted fill. There used to be 0.10, 0.12, and 0.15
        // spread across the count chip, episode code, and status badge — three values
        // that look identical and only guaranteed a fourth site would get a fourth
        // value.
        static let fillOpacity: Double = 0.12

        static func fill(_ color: Color) -> Color {
            color.opacity(fillOpacity)
        }

        static var accentFill: Color {
            fill(accent)
        }
    }

    /// The app's only two animations, and the rule that governs them.
    ///
    /// With Reduce Motion nothing moves, not even a fade: asking the screen not to
    /// move isn't asking it to move slower. The rule used to be written by hand in both
    /// places that animate; returning `Animation?` writes it once and makes it
    /// impossible to forget in a third spot, since animating means going through here.
    enum Motion {
        // The entrance of an image that had to be fetched.
        static func fade(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: 0.2)
        }

        // The appearance and dismissal of the failed-refresh notice.
        static func notice(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.25)
        }
    }
}
