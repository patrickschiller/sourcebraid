# SourceBraid: app brand colors

October 12, 2026 · [Deutsch](IOS_BRAND_APPEARANCE.de.md)

This local appearance update gives the iOS/iPadOS app a restrained identity
inspired by [sourcebraid.com](https://sourcebraid.com/). Warm paper, deep green
text and a single teal accent carry the website's visual character into native
Apple controls. The seven-entry **Recent** destination, navigation, reader and
background-refresh behavior remain as described in the
[reader concept](IOS_READER_REFRESH_UX.md).

## Palette and application

| Semantic role | Light | Dark | Use |
| --- | --- | --- | --- |
| Canvas | `#F4F1E9` | `#122C2A` | Main content background |
| Surface | `#FBFAF6` | `#1C403C` | List rows, settings sections, reader/chat cards and chat input |
| Ink | `#143431` | `#F4F1E9` | Titles and body text |
| Secondary | `#49615E` | `#AEC2BC` | Dates, metadata and explanatory text |
| Tint | `#166B68` | `#8FD1BF` | Links, selected destinations and primary actions |
| Muted surface | `#E6EFE8` | `#214B43` | Selected rows, user messages and code blocks |
| Separator | `#CCCFC8` | `#35534D` | Decorative content separators |
| Filled-action label | `#FFFFFF` | `#143431` | Text/icons on a solid tint action |

The five principal light colors come from the website's
[public stylesheet](https://sourcebraid.com/assets/index-C6HlaNR4.css).
Muted surfaces, separators and the dark palette are app adaptations. Named
color assets provide light, dark and increased-contrast variants; SwiftUI and
the Markdown reader use the same semantic colors. Reader links, quotations,
code and tables receive consistent treatment while preserving document content.

The chat input uses `BrandSurface`. Its border uses secondary ink without
focus and the accent when focused. The filled-action label color (`onAccent`)
also applies to the Settings button shown before an archive is configured.

Send/Stop appears on the right inside the same rounded input surface, with
a separate reserved area for text so the two cannot overlap. Keyboard dismissal
remains a separate action beside the field while focused. Regular padding inside
the safe-area inset gives the composer more clearance above the lower system bar.

Native fonts, Dynamic Type, SF Symbols, tab bars, toolbars, search controls,
safe areas and keyboard behavior remain in place. The tint supplies emphasis;
paper surfaces keep the reading area quiet. No website fonts, logo files,
source code or decorative card patterns are imported. No additional bright
accent palette, playful illustrations or rotated cards are introduced.

## Contrast and accessibility

Calculated default-palette text contrast ratios are:

| Text pairing | Light | Dark |
| --- | --- | --- |
| Ink on canvas | 11.89:1 | 13.11:1 |
| Secondary on canvas (light) / surface (dark) | 5.90:1 | 6.08:1 |
| Tint on surface | 6.03:1 | 6.52:1 |
| Filled-action label on tint | 6.29:1 | 7.69:1 |

These exceed 4.5:1 for normal text. Decorative thin separators do not carry
information alone. Action labels, SF Symbols, selection markers and sender
labels retain meaning independently of color. Increased-contrast variants and
system materials need separate rendered inspection; a palette calculation
does not verify every composited screen.

## Verification boundary

Inspect Recent, Search, Chat, Settings and rendered Markdown in light/dark mode,
increased contrast and enlarged text. Check legible dates and placeholder text,
selected tabs, links, composer/send controls, sources, code blocks and tables.
Check the input border with and without focus, reserved text/action space,
the separate keyboard-dismiss action and clearance above the lower system bar.
Also check the Settings button in the unconfigured archive view.
Repeat keyboard and compact/wide transitions with synthetic content. Record
build, UI-test and screenshot results in the
[test record](IOS_IMPLEMENTATION_TESTING.md); this concept does not claim those
checks have passed.

This change adds no cache requests, background work, AI operation, GitHub
permission, network endpoint or credential handling. Work stays local until
the maintainer approves publication; no commit or push is authorized.
