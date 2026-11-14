# MIDI learn — design

Status: draft for the owner's review, 2026-11-14.

## Intent

The owner wants to play plugin parameters from ordinary hardware MIDI
controllers (Faderfox, OXI E16 and the like): mainly filters (cutoff,
resonance and similar), but any parameter a plugin exposes. The owner does
not use it yet; it is the next feature listed in the first spec's "Later" section
(`2026-10-31-pluginarium-design.md`).

The controllers reach the Mac the same way as the notes from the sequencer,
through the same MIDI interface and source.

Today a channel's single MIDI input (`Channel.midiIn`, a `MIDIRoute`) passes
every message, control changes included, to that channel's instrument.
Effects (`InsertEffect`, and a standalone effect channel) get no MIDI at all,
so a filter in an effect chain cannot be played from a controller. Several
instruments have their own MIDI learn, but its mappings live in the plugin's
state and do not cover effects.

## Goals

1. Map a controller knob to a parameter of any plugin in the rack: the
   instrument of a channel, an effect in its chain, or a standalone effect.
2. Learn by touch: the owner moves the parameter in the plugin's window, then
   the knob. No browsing through parameter lists (Mariana exposes 177).
3. One knob can drive several parameters, in one plugin or in several.
4. Each mapping has a range: the parameter value at the knob's minimum and at
   its maximum. A first value above the second turns the direction round, so
   one movement can open a filter and close a reverb.
5. Soft takeover: after a rack opens, or after the parameter changed by
   another way, the parameter does not move until the knob passes its current
   value.
6. Mappings are saved with the rack and work as soon as it opens.

## Non-goals (this version)

- Relative (endless encoder) modes. Controllers are used in absolute mode,
  values 0–127.
- Sending values back to the controller (LED rings, motor faders). The app
  stays listen-only; `MIDIRouter` has no output port.
- Mapping notes, program changes, pitch bend, aftertouch or 14-bit CC pairs.
  Only 7-bit control change messages.
- Mapping Rackmate's own controls (effect LED, preset menu, rack switching).
- MIDI learn for plugins whose window is closed.

## Anti-goals

Failure even if it technically works:

- A sequencer that sends CCs creates mappings by itself. Learning happens only
  while the owner has Learn switched on.
- A parameter jumps when a knob is first touched after the rack opens.
- A rack refuses to open, or loses its mappings, because a controller is not
  connected. A mapping whose device is missing stays and waits for it.
- The owner has to look at the Mac to play: once mapped, nothing on screen is
  needed.
- A knob reaches an instrument both through a mapping and through the
  plugin's own CC handling, so one knob does two things the owner did not ask
  for.

## Decided by the owner

- **Where:** a strip titled `MIDI CONTROL` under the plugin's own view, in the
  plugin window (`PluginWindows`), for every plugin: instrument, effect in a
  chain, standalone effect. The mixer does not show mappings. (Variant A of
  the mockups in `.superpowers/brainstorm/79447-1794575107/content/`, files
  `learn-placement.html` and `learn-strip-v2.html`.)
- **Learn flow:** switch `LEARN` on in the strip, move a control in the plugin
  with the mouse, then move a knob. The mapping appears as a row.
- **One knob, several parameters:** allowed.
- **Range and direction:** each mapping has both.
- **Takeover:** the parameter waits until the knob passes its value; no jump.
- **Interface text** is English, like the rest of the app.

## How it behaves

### The strip

Under the plugin view, the full width of the window:

- A `LEARN` switch (amber when on) and the title `MIDI CONTROL`.
- While Learn is on, a hint: "Move a control in the plugin, then a knob on
  your controller."
- One row per mapping of this plugin: parameter name; the knob as device name,
  MIDI channel and CC number (`OXI E16 · CH 1 · CC 74`); the range as two
  editable percentages, knob minimum → knob maximum; a `×` that deletes the
  row.
- A row half learned (parameter picked, no knob yet) shows
  `waiting for a knob…`.

### Learning

1. With Learn on, the last parameter the owner moved in this plugin's window
   becomes the pending parameter, and a pending row shows it. Only moves made
   after Learn was switched on count.
2. The next control change from any source sets the knob of that row. The
   row's range starts at 0 % → 100 %.
3. Learn stays on, so the owner can map the next parameter straight away.
   Learn goes off when the owner switches it off or closes the window.
4. Moving another parameter before a knob arrives replaces the pending
   parameter.
5. Learning a knob already mapped to the same parameter of the same plugin
   does not add a second row, and the existing row keeps its range.

Learn on in one window and a knob moved: only that window's pending row takes
it. Learn may be on in several windows; the knob goes to the window whose
pending parameter was picked last.

### Playing

- Rackmate listens to every MIDI source, on every MIDI channel, whatever the
  channel's `MIDIRoute` says. A mapping is identified by source name, MIDI
  channel (1–16) and controller number (0–127).
- A control change that matches mappings sets each mapped parameter to
  `from + (to − from) × value / 127`, with `from` and `to` as fractions of the
  parameter's range. The fractions follow the parameter's own scale as the
  plugin declares it (linear, logarithmic and so on), so a cutoff knob moves
  like the plugin's own cutoff control, not linearly in Hz. A stepped
  parameter (switch, menu) takes the nearest step.
- A control change whose source, MIDI channel and controller match any
  mapping in the rack is never delivered to an instrument: also while the
  mapping waits for takeover, and also when its plugin failed to load or its
  parameter is gone. Every other message goes to the instruments as today.
- Takeover per mapping: after the rack opens, after a preset is picked, and
  after the owner moves the parameter in the plugin window, the mapping waits.
  The app's own mapped writes do not make it wait. It takes over when a knob
  value lands on, or moves across, the parameter's current value; from then
  on it follows the knob.
- A current value outside the mapping's range counts as the nearer end of the
  range, so the mapping takes over there instead of waiting for ever. A range
  with both ends equal holds the parameter at that value and takes over at
  the first knob move.
- A mapped move marks the rack as changed and the plugin's sound as custom
  (`isCustomSound`), like a mouse move in the plugin window does today
  (decided by the owner): knob positions played live are saved with the rack
  when the owner saves. This holds with the plugin window closed too, so it
  needs a path of its own: today a change is found by comparing the state
  read when the window opened with the state read when it closes, and
  plugin state must never be compared with stored state.

### Saving

- Mappings belong to the rack (`Configuration`), stored with the plugin they
  drive (on `PluginSlot`, which both `Channel.slot` and
  `InsertEffect.slot` use). Rack files from before this feature have no
  mappings and open as before.
- Learning, deleting or editing a mapping's range marks the rack unsaved.
- Mappings are not part of a plugin preset. Picking a preset keeps the
  mappings; saving a preset does not store them.
- A mapping names its parameter by the Audio Unit parameter ID, and keeps
  the parameter's name for display. If the plugin no longer has that
  parameter (for example after a plugin update), the row stays, dimmed, and
  does nothing until the owner deletes it.
- Removing a plugin from the rack removes its mappings. Moving an effect
  (`EffectMove`) keeps them. Replacing a plugin with another drops them.

## Constraints

From `CLAUDE.md` and the existing code, binding:

- Logic without UI goes into `RackmateCore`, test first (Swift Testing): the
  mapping model and its coding, the value formula, the takeover rule, which
  messages are swallowed, learn's pending state.
- The render thread never allocates, locks, logs or calls Swift.
- MIDI goes from the CoreMIDI thread into the render core without waiting
  for the main actor (`MIDIRouter`); a mapped CC must not add a hop to the main
  actor on its way to the parameter.
- Every Audio Unit lifecycle call stays on the main thread.
- A missing device or plugin never stops a rack from loading.
- Checks with audio running use silent units only. Hardware tests with real
  plugins need the owner's OK.
- A user-visible change is not done until `docs/manual.html` and
  `docs/cs/manual.html` describe it (with a screenshot in
  `docs/assets/manual/`), and `CHANGELOG.md` has a line under `## Unreleased`.
- Release as a minor version (new feature): 1.2.0, through the `release`
  skill.

## My calls (not discussed with the owner)

- Learning works only with the plugin's window open, since learning starts
  from a move in that window.
- A mapping whose device is missing stays in the list, shown dimmed, and
  starts working when the device comes back.
- If a plugin does not tell the host which parameter was moved, Learn cannot
  pick it by touch. The strip then offers a menu of the plugin's parameters
  to pick the pending parameter from instead.
- Percentages in the range fields are whole numbers, 0–100, in the
  parameter's own scale.
- A current value outside the range takes over at the nearer end of the
  range; equal ends take over at the first move.
- A mapped CC is swallowed whatever the state of its mapping.
- Parameters are named by Audio Unit parameter ID; a missing one leaves a
  dimmed row.
- Relearning an existing knob and parameter pair keeps the row's range.
- Stepped parameters can be mapped and take the nearest step.

## Left to the builder

- How the plugin window learns which parameter moved (AU parameter listener,
  begin-gesture or value-change events) and how the fallback menu is fed
  (the AU parameter list).
- On which thread, and by which call, a mapped value reaches the plugin, as
  long as the constraints above hold.
- The window layout: how the strip and the plugin view share the window,
  how the list scrolls when long, how resizing behaves.
- Names of types and fields, the coding of the mapping, and the test units
  needed to cover parameters in tests.
