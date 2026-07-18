# jellyfin-data-layer Specification

## Purpose

Defines the shared `JellyTVKit` Jellyfin REST API client, DTOs, and authenticated image URL loading that enable the tvOS app to fetch real library and item data from a connected Jellyfin server.

## ADDED Requirements

### Requirement: Jellyfin API client
`JellyTVKit` SHALL provide a `JellyfinClient` that executes authenticated HTTP requests against a Jellyfin server. It SHALL be initialized with a `baseURL`, `apiKey`, and `deviceId` and SHALL attach the `MediaBrowser` authorization header to every request. It SHALL decode Jellyfin's PascalCase JSON responses into typed Swift DTOs.

#### Scenario: Client fetches user views
- **WHEN** `JellyfinClient.fetchUserViews(userId:)` is called with a valid base URL and API key
- **THEN** it issues `GET /UserViews?userId=...` and returns `[JellyfinUserView]` decoded from the `Items` array in the response

#### Scenario: Client fetches items with filters
- **WHEN** `JellyfinClient.fetchItems(userId:parentId:includeItemTypes:filters:sortBy:limit:)` is called
- **THEN** it issues `GET /Items` with the corresponding query parameters and returns `[JellyfinItem]`

#### Scenario: Client builds authenticated image URLs
- **WHEN** `JellyfinClient.imageURL(itemId:type:tag:maxWidth:)` is called
- **THEN** it returns an absolute URL pointing to `/Items/{itemId}/Images/{type}` with `tag`, `quality`, and `maxWidth` query parameters

### Requirement: Jellyfin item DTO
`JellyTVKit` SHALL define `JellyfinItem: Decodable, Identifiable, Sendable` mapping the Jellyfin `/Items` response fields with explicit PascalCase `CodingKeys`. Fields SHALL include: `id`, `name`, `type`, `overview`, `genres`, `productionYear`, `officialRating`, `communityRating`, `runTimeTicks`, `seriesName`, `seriesId`, `indexNumber`, `parentIndexNumber`, `imageTags`, `backdropImageTags`, `parentBackdropItemId`, `parentBackdropImageTags`, `userData` (with `playbackPositionTicks`, `played`, `lastPlayedDate`, `isFavorite`, `playCount`), and `childCount`.

#### Scenario: Item decodes from Jellyfin JSON
- **WHEN** a Jellyfin `/Items` response containing a Movie item is decoded as `[JellyfinItem]`
- **THEN** the `type` field is `"Movie"`, `name` and `id` are populated, and `userData` fields are present when the response includes them

#### Scenario: Item handles optional fields
- **WHEN** a Jellyfin item response omits `genres`, `officialRating`, or `userData`
- **THEN** those fields decode as `nil` without error

### Requirement: Jellyfin user view DTO
`JellyTVKit` SHALL define `JellyfinUserView: Decodable, Identifiable, Sendable` mapping `GET /UserViews` response fields: `id`, `name`, `collectionType`, and `imageTags`.

#### Scenario: User view decodes library
- **WHEN** a Jellyfin `/UserViews` response is decoded
- **THEN** each element has a non-empty `id`, `name`, and optional `collectionType` (e.g. `"movies"`, `"tvshows"`)

### Requirement: Items response wrapper
`JellyTVKit` SHALL define `ItemsResponse<T: Decodable>: Decodable` with an `items: [T]` field mapped from the `Items` JSON key and an optional `totalRecordCount` mapped from `TotalRecordCount`.

#### Scenario: Paged response is decoded
- **WHEN** a Jellyfin list endpoint response is decoded as `ItemsResponse<JellyfinItem>`
- **THEN** the `items` array contains the decoded items and `totalRecordCount` reflects the server-side total

### Requirement: Authenticated async image
`JellyTVKit` SHALL provide a `JellyfinAsyncImage` SwiftUI view that loads and displays an image from a Jellyfin server's `/Items/{id}/Images/{type}` endpoint, attaching the `MediaBrowser` authorization header. It SHALL accept `baseURL`, `apiKey`, `itemId`, `imageType`, and optional `imageTag` and `maxWidth` parameters.

#### Scenario: Image loads with auth header
- **WHEN** `JellyfinAsyncImage` is rendered with valid credentials and an existing item ID
- **THEN** the image is fetched from the server and displayed

#### Scenario: Missing image shows placeholder
- **WHEN** `JellyfinAsyncImage` is rendered for an item with no `imageTag`
- **THEN** a fallback gradient placeholder is displayed instead of a broken image
