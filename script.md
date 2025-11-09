# Cave of Nations – Game Script & Implementation Guide

## High-Level Concept
- The player commands an Anubis-inspired fox avatar to explore an underground grid of blocks.
- Core loop: click-to-move pathfinding, dig to gather resources, recover relics for progression.
- Presentation: Egyptian-inspired UI with quicksand stage, gold/teal accents, and a point-and-click control scheme.

## Gameplay Overview
1. **Starting State**
   - Game opens paused. Player presses "Start" or toggles pause to begin.
   - Anubis avatar is centered on the quicksand floor above the block grid.
2. **Movement**
   - Click destinations to move. The engine uses A* pathfinding to navigate around obstacles.
   - WASD/arrow keys still provide step-based movement.
3. **Digging & Resources**
   - Click or press Space to dig the block in front of Anubis.
   - Soil, rock, pipestone, and relics feed directly into the economy/inventory.
   - Digging triggers particles and squash/stretch animation for feedback.
4. **UI & Monitoring**
   - Minimap shows explored depths, relic locations, and Anubis position.
   - Collapsible HUD lists resources/inventory, plus command buttons for economy actions.
5. **Objective**
   - Recover relics from multiple factions to unify the underground nations.
   - Optional expansions: save/load seeds, minimap tooltips, active quests.

## Technical Systems
### Scene Composition
- `GameWorld` (SceneKit) maintains quicksand plane, block terrain, and Anubis node.
- Blocks load from USDZ cube templates for consistent geometry and low memory overhead.
- Quicksand stage is a textured `SCNPlane` with procedurally generated visual elements.

### Pathfinding & Movement
- Implemented in `GameWorld.findPath` using A* on the grid.
- `movePlayer(to:)` builds path, rotates/moves Anubis smoothly, updates grid coordinate callbacks.

### Digging Feedback
- `digPlayerForward` removes block, spawns `SCNParticleSystem`, and runs idle/impact animation.
- Particle color highlights block type; animation uses simple squash/stretch to avoid repetitive movement.

### Resource & Relic Tracking
- `GameViewModel` collects economy/inventory data; `GameWorld` caches relic coordinates.
- Minimap in `ContentView` draws depth map, player marker, and relic highlights via `Canvas`.

### UI/UX
- `ContentView` renders a full-window SceneKit view with glass-effect overlays.
- HUD elements leverage gold/teal theme, collapsible resource panel (defaults minimized), and pause controls.
- Main menu & options board use matching theming; game state begins paused.

## Implementation Steps Summary
1. **Core Scene & Blocks**: create quicksand stage, load USDZ cubes, manage block caches.
2. **Controls**: implement click-to-move A*, keyboard fallback, and dig interactions.
3. **Feedback**: particle effects, animation blends, selection ring toggles.
4. **Economy & Inventory**: track resources, update UI with collapsible panel and summary.
5. **Minimap**: maintain depth grid, player coordinate, and relic positions to render in SwiftUI.
6. **Polish**: pause/resume controls, theme-coherent buttons/panels, block regeneration script.

## Running & Building
- Regenerate blocks: `python3 Tools/generate_usdz.py`.
- Clean build artifacts: `swift package clean`.
- Build: `swift build` (macOS 13+ target).
- `.gitignore` excludes SPM and macOS artifacts.

## Future Enhancements
- Save/load generation seeds, audio volume hooks, advanced digging VFX.
- Expanded minimap tooltips, quest milestones, and economy automation.

