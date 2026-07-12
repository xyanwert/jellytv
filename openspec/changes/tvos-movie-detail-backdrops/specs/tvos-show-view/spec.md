## ADDED Requirements

### Requirement: Show synopsis
The Show view SHALL display the show's synopsis below the spec sheet in the title column.

#### Scenario: Synopsis renders
- **WHEN** the Show view is presented for a show with a synopsis
- **THEN** the synopsis text is displayed under the spec sheet

### Requirement: Atmospheric detail backdrop
The Show view SHALL render an atmospheric backdrop derived from the show's key art — a full-bleed, blurred, dimmed image scrimmed into the page background — behind the dossier content, rather than a flat gradient.

#### Scenario: Backdrop is present and legible
- **WHEN** the Show view is presented
- **THEN** the show's art is visible as a soft full-screen backdrop that fades into the background, and the title/spec text over it remains legible
