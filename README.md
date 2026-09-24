# Plainsrunner

A lightweight, native-style unit bar addon for World of Warcraft: Forever that tracks the Tauren Plainsrunning racial.

Attaches directly below the player frame mana bar with matching borders, textures, and drop shadows.

## What It Does

- Shows your current Plainsrunning stacks (0 to 30) and speed bonus (+0% to +30%).
- Status bar fills up every 5 seconds while running to show progress toward your next stack.
- Displays a glowing spark for the 1-second grace period before stacks start decaying when you stop.
- Shows when stacks are actively decaying while standing still.
- Hover tooltip with current speed and stack stats.
- Built-in test mode to simulate movement and decay (`/pr test`).

## Plainsrunning Mechanics

- Gain 1 stack (+1% movement speed) every 5 seconds of continuous movement outdoors.
- Caps at 30 stacks (+30% speed) after 2.5 minutes of running.
- 1.0 second grace period when stopping before decay starts.
- Stacks decay at 1 stack per second while stationary.
- Taking damage cuts your current stacks in half.

## Commands

- `/pr` - Show command list
- `/pr test` - Toggle test simulation mode
- `/pr log` - Show diagnostic logs
- `/pr reset` - Reset addon settings

## Installation

Extract the `Plainsrunner` folder into your WoW AddOns folder:
`World of Warcraft\_classic_beta_\Interface\AddOns\Plainsrunner\`
