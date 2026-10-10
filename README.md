# FastWOken

A challenging 2D pixel-art platformer built with **Godot 4** for desktop and Android.

## Current prototype
- Run, jump, and air movement
- Spikes, collectible crystals, and a goal portal
- Camera following the player
- Keyboard controls on desktop and on-screen controls on touch devices
- Pixel-art look drawn in code so the prototype has no external asset dependencies
- Procedurally generated looping forest ambience (wind and leaf rustle)
- Procedurally synthesized bird calls on a separate, quieter audio layer
- 10 handcrafted challenge levels with distinct platform layouts and hazard patterns
- Main menu with a selectable two-column list of all ten levels
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
- **LEVEL SELECT**: open the main menu and choose any of the ten levels
- On touch devices, use the on-screen arrows and jump button.

## Export
Use Godot's Export menu to install export templates and create a Windows/Linux/macOS build or an Android APK. Android export requires the Android build template/SDK setup in Godot.

## Project structure
- `project.godot` — project settings
- `scenes/main.tscn` — level
- `scenes/player.tscn` — player character
- `scripts/game.gd` — level logic, ten level layouts, hazards, collectibles, touch controls, procedural forest audio
- `scripts/player.gd` — player physics and pixel character drawing

This is the first playable prototype; graphics and level design can be expanded without changing the cross-platform foundation.
