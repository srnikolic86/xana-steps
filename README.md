# XanaSteps

Shows the steps of your current RestedXP guide as numbered pins on the world
map and the minimap in World of Warcraft: Forever. That's all it does: no arrow, no routes,
no extra windows.

Version 0.2.1, written for the WoW Forever beta (interface 16001).
Not yet tested in game.

## Requirements

RestedXP Guides (`RXPGuides`) must be installed and enabled, with a guide
loaded. XanaSteps reads the steps from it. RestedXP-Navigator is **not**
needed.

## Install

1. Copy the `XanaSteps` folder into:

   ```
   World of Warcraft/<Forever client folder>/Interface/AddOns/
   ```

2. Restart the game.
3. On the character screen open AddOns and make sure XanaSteps is ticked.

## What you see

Open the world map. Each step that has a location gets a round pin with its
step number from the guide:

- **Gold** pins are the step(s) you're on now.
- **Blue** pins are the next steps, up to 6 steps in total.

Hover a pin to see the step's instructions. Pins follow the guide: when a
step completes, its pin disappears and the next step's pin turns gold.

Pins show on whichever map is open: a zone map, a city map, or the
continent map when the location is on it.

The same pins (a bit smaller) show on the minimap and move as you walk. A
current-step pin that's too far away for the minimap sits on its edge,
dimmed, pointing the way. Later steps only show once they're within the
minimap's range. Rotating minimaps are supported.

## Good to know

- XanaSteps doesn't change RestedXP. To stop RestedXP drawing its own pins
  next to these, open `/rxp` and tick **Disable Map Pins** and **Hide Mini
  Map Pins**. To hide its
  guide window and arrow as well, tick **Hide Window** and **Hide waypoint
  arrow**. The guide keeps advancing with the window hidden.
- XanaSteps has no settings and no commands.

## Uninstall

Delete the `Interface/AddOns/XanaSteps` folder.
