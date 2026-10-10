# FastWOken

A challenging 2D pixel-art platformer built with **Godot 4** for desktop and Android.

## Current prototype
- Run, jump, and air movement
- Spikes, collectible crystals, and a goal portal
- Camera following the player
- Keyboard controls on desktop and on-screen controls on touch devices
- Real photographic forest panorama background (Poly Haven, CC0)
- Photogrammetry-based forest-floor texture on platform tops (Poly Haven, CC0)
- Procedurally generated looping forest ambience (wind and leaf rustle)
- Procedurally synthesized bird calls on a separate, quieter audio layer
- Generated-in-code sound effects for jumping, collecting crystals, and activating the goal portal
- 10 handcrafted challenge levels with distinct platform layouts and hazard patterns
- First-launch tutorial explaining movement, jumping, hazards, crystals, and the goal portal; completion is saved so it does not repeat on later launches
- Main menu with a selectable two-column list of all ten levels
- Animated menu entrance with a fade-in backdrop, sliding panel, and staggered level buttons
- Smooth fade-to-dark transitions when switching levels
- Saved progression in Godot's `user://fastwoken_progress.cfg` using `ConfigFile`
- Levels unlock sequentially when the previous level is cleared; locked levels are disabled in the menu
- Best crystal count per cleared level is saved, and cleared levels are marked in the level menu
- In-game **LEVEL SELECT** button to return to the menu at any time
- Level selection using `[` / `]` or Page Down / Page Up; touch-device level buttons

## Run
1. Install Godot 4.3 or newer.
2. In Godot, choose **Import** and select this repository's `project.godot`.
3. Press **F6** or **F5** to run.

## Controls
- **A / D** or **Left / Right**: move
- **Space / W / Up**: jump
- **R**: restart after a death or replay the current level after clearing it
- **]** or **Page Up**: start the next level
- **[** or **Page Down**: start the previous level
- On the first launch, read the quick tutorial and press **LET'S GO!**; it is shown only once per saved profile
- **LEVEL SELECT**: open the main menu and choose any unlocked level
- Level selection fades smoothly between stages; menu elements animate into view
- On touch devices, use the on-screen arrows and jump button.

## Export
Use Godot's Export menu to install export templates and create a Windows/Linux/macOS build or an Android APK. Android export requires the Android build template/SDK setup in Godot.

## Project structure
- `project.godot` — project settings
- `scenes/main.tscn` — level
- `scenes/player.tscn` — player character
- `scripts/game.gd` — level logic, ten level layouts, hazards, collectibles, touch controls, procedural forest ambience and synthesized sound effects
- `scripts/player.gd` — player physics and pixel character drawing

This is the first playable prototype; graphics and level design can be expanded without changing the cross-platform foundation.


## Visual asset sources
- Forest Slope panoramic forest photo by Andreas Mischok, Poly Haven, CC0: https://polyhaven.com/a/forest_slope
- Forest Leaves 02 ground texture by Rob Tuytel, Poly Haven, CC0: https://polyhaven.com/a/forest_leaves_02
- Source assets are resized for real-time 2D rendering and mobile memory use.
