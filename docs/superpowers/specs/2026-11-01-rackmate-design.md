# Rackmate 0.2.0

**Status:** approved by the owner through the prototype on 2026-11-01.

This extends `2026-10-31-pluginarium-design.md`. Where the two differ, this document wins. The visual reference is `ui-prototype/`. Where this document and the prototype differ, this document wins.

## Name

- The app is **Rackmate**. Repository `jiripisa/rackmate`, public. Website https://jiripisa.github.io/rackmate/.
- Bundle identifier `io.jp4.rackmate`. Update feed `https://jiripisa.github.io/rackmate/appcast.xml`.
- The data folder is `~/Library/Application Support/Rackmate`. At launch, when that folder does not exist and `~/Library/Application Support/Pluginarium` does, the old folder is copied to the new one. It is never moved, changed or deleted. If the copy fails, the partial folder is removed, the failure is logged and the app starts empty.
- The owner deletes the old repository by hand. Installed copies of Pluginarium 0.1.0 do not update to Rackmate; a tester installs it from the new site.
- The word **rack** replaces both "configuration" and "stack" everywhere a person reads it: New rack, Load rack, Save rack, Update rack?, Add to rack, No racks yet, "position in the rack", "in all racks". The type `Configuration` and the folder `configurations` keep their names, because a rename gains nothing and existing data would need migrating.
- "Channel" stays.
- Assets, from the owner's `_images/`: the monogram icon is `Resources/AppIcon.png`. The white and amber logo goes on dark surfaces: the Start screen, in place of the set wordmark, and the website's dark hero. The black and amber lockup goes on light surfaces: the manual's header. The orange and muted variants are not used. The top bar stays set in DIN Condensed, since the logo does not read at that size.

## Look

The panel becomes a rack, as in `ui-prototype/`:

- Walnut cheeks stay. Between them, rack units stacked top to bottom, each with ears, two screws and a slot, on a brushed metal plate.
- Colours: amber is for displays only (presets, seven-segment digits, effect names). Green is for lit status (LEDs, lit icon keys). Red is for faults.
- Under the last unit a vent panel fills free height. It disappears when less than 74 points are free.
- Default window 1280×760. Minimum 1200×600. Channels scroll vertically when they do not fit; the top bar stays.

## Top bar

Left to right: `RACKMATE` set wide in muted DIN Condensed, a divider, the rack name with its menu, unsaved state with Save, then at the right any microphone or device fault, the clock readout, CPU, a divider, and Settings as a gear icon key with the tooltip "Settings". The Start screen keeps its Settings button with text.

## A channel

A channel is one rack unit, at least 132 points high, growing with its content. Columns left to right:

1. **Position:** two-digit number, × to remove, and an LED at the bottom. On an instrument the LED flashes on incoming MIDI. On a standalone effect it flashes on output signal.
2. **Inputs:** see Displays. The first block's display shares its bottom edge with the plugin picture.
3. **Identity:** the plugin's maker as a legend above, in the same line as MIDI in, left out when the plugin is not installed or names none. A generic picture and the plugin name on the first row, the preset display on the second. Pictures come from the plugin kind: keys for an instrument, a wave for an effect. A plugin tagged as a sampler by Audio Unit tags gets pads, if the tag is available; otherwise keys.
4. **Keys:** two 34-point icon keys, level with the two identity rows. Open plugin, then Follow Start/Stop. A key that is on lights green and glows. Text lives in tooltips: "Open plugin", "Close plugin", "Follow Start/Stop: On", "Follow Start/Stop: Off". Open plugin is dimmed while the plugin cannot open.
5. **Effects:** see Effects.
6. **Output:** Audio out display aligned right, under it segmented L and R meters, green, then yellow from 68 %, red from 88 %.

Faults replace boxes with lit text:

- Plugin not installed or failed to load: the plugin name is red, and the reason is in its tooltip and available to VoiceOver.
- Not installed: a `Replace plugin` key takes the preset's place. Failed: the saved sound shows dimmed in the preset's place.
- Loading: the preset place shows `Loading`, dimmed.
- MIDI device missing: the device value itself reads "Hapax is not connected", in red.
- Output missing: the display lights red and the warning sits under it.
- An effect that failed: red border and name, red LED, its only menu item is Remove.

## Plugin types

Music effects (`aumf`) take audio and MIDI. That type covers a vocoder played over MIDI and a plain effect that also takes MIDI, such as Arturia's, and nothing in it tells them apart. So the Add dialog offers them as instruments, as standalone effects and in Add effect, and what the owner picks decides the channel's kind. Their second input bus is a sidechain, as on an effect. Where `2026-10-31-pluginarium-design.md` lists them as instruments only, this section wins.

## Displays

No comboboxes on the mixer. Every route is a value that opens a menu.

- **MIDI in:** a seven-segment display of three digits with a small `CH` label, showing right aligned `1` to `16`, `ALL`, or a dimmed `---` with no MIDI, when it does not open. Under it the device name in small muted text; a click opens the device menu.
- **Audio in, Audio out, Sidechain in:** a five-digit display, `3-4`, `11-12`, a mono `3`, or a dimmed `OFF`.
- Unlit segments stay faintly visible. Digits are drawn as vector shapes, not a font.
- Channel menu: All, then 1 to 16 in a 4×4 grid. Route menus: two columns.
- Forms keep their fields: the Add dialog and Settings.

## Effects

- Series runs left to right, joined by arrows. Parallel effects stack in one stage, joined by brackets. Up to 3 in a stage.
- A slot shows a small picture, the name, an LED and a vertical three-dot menu. The picture is hidden below 150 points of slot width.
- **On and off.** The LED is a switch, also in the menu as "Turn effect off" and "Turn effect on". The state is saved, marks the rack unsaved, and a file without it reads as on. An effect that is off:
  - stays loaded and keeps its window, presets and state,
  - in series passes the signal unchanged,
  - in a parallel stage drops out of the sum, so the level does not jump,
  - when all of a stage are off, the stage passes the signal dry.
  - It leaves the audio graph. Its tail is cut, and what its buffers held may sound when it returns.
- Clicking the name opens or closes the plugin window. The three dots open the menu: Open plugin, Turn effect off, Presets, Sidechain in, Follow Start/Stop, then Add parallel effect, Move to series, Remove.
- **Add effect** is a round plus. On hover or keyboard focus it unfolds smoothly into a labelled button, then back. No motion with Reduce Motion on.
- **Dragging.** A drag starts after 5 points on the name. The source dims, a ghost follows, an amber line shows the landing place.
  - Outer 30 % of a slot's width: a series stage before or after that slot's stage.
  - Middle: parallel, above or below that slot by its upper or lower half.
  - A full stage offers only the sides.
  - Anywhere else in a channel's effects area, including an empty one: the end of that chain.
  - Dropping on itself changes nothing. A drag can end in another channel. The plugin is not reloaded and keeps its sound. Its open window closes first.
  - A failed effect does not drag.
  - The move marks the rack unsaved.

## Website

A new site in `docs/`, same structure as before in English and Czech, with the Rackmate logo and icon, and new screenshots of this interface. The home page opens on a dark hero with the white and amber logo. The manual stays on a light page for long reading. Everything a person reads says Rackmate and rack. `docs/superpowers/` is history and is not rewritten.
