# tvos-nav-rail Delta Spec

## MODIFIED Requirements

### Requirement: Libraries slide-out submenu
Selecting the rail's Libraries icon SHALL open a 392px submenu panel listing every library fetched from the Jellyfin server via `AppState` (not `SampleCatalog`), with each library showing its icon, name, item count, and an accent-tinted "18+" badge for libraries classified with `MetaCategory.isNSFW == true`. The submenu SHALL NOT navigate away from Home; the Home content behind it SHALL dim rather than being fully hidden, and Back/Menu (or reselecting another rail icon) SHALL close it. Music and books libraries SHALL be filtered out and not shown.

#### Scenario: Libraries submenu shows real Jellyfin libraries
- **WHEN** the rail's Libraries icon is selected and the server has 3 libraries (Movies, TV Shows, Anime)
- **THEN** the submenu panel shows 3 library rows with their actual names and item counts from the Jellyfin server

#### Scenario: Adult libraries are marked in the submenu
- **WHEN** the submenu renders a library classified by `LibraryClassifier` as `MetaCategory.moviesxxx` or `MetaCategory.hentai` or `MetaCategory.porn`
- **THEN** that row shows the accent-tinted background/border, the pinkish name color, and the "18+" badge

#### Scenario: Music and books libraries are not shown
- **WHEN** the server has a library with `collectionType = "music"` or `collectionType = "books"`
- **THEN** that library does not appear in the Libraries submenu

### Requirement: Secondary rail destinations are non-blocking
Selecting the rail's Movies or TV Shows icon SHALL open a meta-library screen that displays items from all libraries of the corresponding Jellyfin `CollectionType` across all meta-categories (including NSFW and anime). Selecting the Search icon SHALL continue to render a "coming soon" placeholder. All destinations SHALL remain navigable back to Home via Menu/Back.

#### Scenario: Movies rail icon opens meta-library
- **WHEN** the Movies rail icon is selected
- **THEN** the app shows a grid of all items from libraries with `MetaCategory.collectionType == "movies"` (i.e. `movies`, `moviesxxx`, and `animefilm` libraries)

#### Scenario: TV Shows rail icon opens meta-library
- **WHEN** the TV Shows rail icon is selected
- **THEN** the app shows a grid of all items from libraries with `MetaCategory.collectionType == "tvshows"` (i.e. `shows`, `anime`, and `hentai` libraries)

#### Scenario: Search rail icon still shows placeholder
- **WHEN** the Search rail icon is selected
- **THEN** the app shows a "coming soon" placeholder and the user can return to Home
