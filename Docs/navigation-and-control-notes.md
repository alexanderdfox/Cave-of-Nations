# Navigation & Placement Notes

## Overview

This document captures the current interaction model for navigation, unit selection, and building placement inside the SceneKit client. It complements the inline comments that annotate the implementation.

## Camera Rig

- Camera state lives in `GameWorld` (`cameraTarget`, `cameraAngles`, `cameraDistance`).
- `SceneViewWrapper.Coordinator` funnels gesture deltas from the macOS view into the following entry points:
  - `GameViewModel.orbitCamera(by:)` → `GameWorld.orbitCamera(by:)`
  - `GameViewModel.panCamera(by:)`   → `GameWorld.panCamera(by:)`
  - `GameViewModel.zoomCamera(by:)`  → `GameWorld.zoomCamera(by:)`
- Panning is clamped to a padded bounding box so players cannot lose the dig site.
- Orbit angle pitch is limited to keep the camera above the horizon.

## Unit Selection

- Dragging with the left mouse button spawns a screen-space marquee (`selectionRect` in `ContentView`), rendered by `selectionOverlay`.
- Releasing the drag calls `Coordinator.finalizeSelection`, which projects scene nodes back into screen space and gathers the ids for `GameViewModel.selectUnits(in:additive:)`.
- Holding `⇧` or `⌘` while dragging merges the result with the current selection; otherwise selection is replaced.
- Clicking a single unit snaps directly to `select(unit:additive:)`. Clicking empty terrain clears selection unless `⇧`/`⌘` are held.

## Click-to-Move Pathfinding

- Left-clicking navigable terrain while no build is in progress calls `GameViewModel.movePlayer(to:)`.
- `GameWorld.movePlayer(to:)` converts the hit-test point into a grid coordinate, runs A*, and issues a queued action sequence that rotates and moves the guardian along the path.
- The path follower updates `playerGridPosition` and notifies listeners through `onPlayerPositionChange`.

## Building Placement

- The command bar exposes a `Menu` populated by `GameViewModel.availableBuildings`.
- Choosing a template calls `beginPlacement`, which:
  - Stores `PlacementState`.
  - Clears any previous preview node (`GameWorld.updatePlacementPreview(for: nil)`).
- Mouse movement drives `updatePlacementHover`. The world:
  - Validates the footprint (`evaluatePlacement`) ensuring navigable headroom and level-enough terrain.
  - Updates a translucent preview mesh, coloring green or red based on validity.
- Clicking while valid commits the placement via `commitPlacement`, which enqueues a `Unit.Command.build` for selected units.
- Right-clicking, choosing another template, or the menu’s “Cancel Placement” option calls `cancelPlacement`.

## Input Summary

| Interaction                              | Result                                                                  |
|------------------------------------------|-------------------------------------------------------------------------|
| Click unit                               | Selects unit (⇧/⌘ add to selection).                                    |
| Drag select                              | Draws marquee, selects units within it.                                 |
| Click empty terrain                      | Moves guardian via pathfinding (unless additive modifiers held).        |
| Right-drag                               | Orbits camera.                                                          |
| Option-drag or Middle-drag               | Pans camera.                                                            |
| Scroll wheel / Pinch gesture             | Zooms camera in or out.                                                 |
| Menu → Place Building                    | Enters placement mode with ghost preview.                               |
| Placement mode + valid click             | Issues build command, exits placement mode.                             |
| Placement mode + invalid click           | Emits audible feedback (`NSSound.beep()`), remains in placement mode.   |
| Placement mode + Cancel action           | Exits placement mode, removes preview.                                  |

## Future Considerations

- Visual selection rings for multiple units are still pending (currently only guardian ring toggles).
- Resource availability is not yet validated when committing builds; costs are attached for future integration with the economy system.
- Camera speed scaling could be refined for tighter control when fully zoomed in.


