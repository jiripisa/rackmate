# Changelog

## 1.1.1 — 2026-11-01

- Effects of type `aumf`, which include Arturia's, are now in the Effects list and can go in a channel's chain. They stay in the Instruments list too, since vocoders use that type.
- The second input of such a plugin now shows as Sidechain in.

## 1.1.0 — 2026-11-01

- Delete a rack: the × on its row on the Start screen, or Delete rack in the rack menu. It goes to the Trash, and its presets stay.

## 1.0.0 — 2026-11-01

- Each channel shows the plugin's maker above its name.
- Pluginarium is now Rackmate. Your racks, presets and settings come along at the first launch.
- A configuration is now called a rack.
- A new look: the panel is a rack of units with ears, screws and brushed metal, with the logo on the Start screen and a gear for Settings.
- Each channel is now a rack unit. MIDI channel and audio routing show on seven-segment displays: click a value to change it. Open plugin and Follow Start/Stop are lit icons, with their names in tooltips.
- Effects run left to right. Each has an on and off switch, saved with the rack. Drag an effect beside another to run it in series, or under it to run it in parallel, also into another channel.
- Hold a dragged effect near the rack's top or bottom edge and the rack scrolls, so a drag can reach a channel out of view.
- The window is now at least 1200 points wide.
- The app icon fills its whole shape instead of sitting small on a light plate.

## 0.1.0 — 2026-11-01

- First version.
- Start screen with your saved configurations and the plugins each one uses, on the synth panel with walnut cheeks.
- A configuration keeps playing through device changes and comes back when its audio device returns.
- Mixer screen with a column per instrument or effect: MIDI, audio and sidechain selectors that follow the plugin and the audio device, level meters, the MIDI clock and CPU load in the top bar, and clear messages for missing plugins, MIDI devices and audio channels.
- Level meters hold each peak until it is drawn, so short notes are not missed.
- Add dialog: type a few letters, press Return, and the plugin is in. Recent plugins come first, the sound can be picked, and the routing follows the plugin. It also replaces the plugin of a channel.
- Effect slots: series rows and up to three parallel effects joined by split and merge lines, each with a menu to open the plugin, pick its preset and sidechain, add a parallel effect, move it to series or remove it. An effect that failed to load shows in red, with the reason in its tooltip.
- Plugin windows open over the mixer, follow the size the plugin asks for, step aside for dialogs and Settings, and close with their plugin.
- Presets: pick your own or the plugin's factory presets on a running plugin, save the current sound under a name, and choose whether the saved configuration follows. A sound that moved away from its preset reads "(changed)".
- Saving: Save, Save as and a name for a new configuration, in the top bar and the File menu with Command-S and Command-Shift-S. Leaving a configuration with unsaved changes, or quitting, asks "Save changes?". A plugin whose sound cannot be read keeps its last saved sound, and a configuration that cannot be written stays unsaved. A plugin you did not touch stays on "Default sound" after saving.
- Settings (Command-comma, from the Start screen and the mixer): audio device, sample rate and buffer size, MIDI clock source, and the default routing of instrument and effect positions. With System default the device keeps its own sample rate and buffer size, and these show what runs.
- A new channel whose usual output (or input, for an effect) does not exist on your audio device takes the first free stereo pair the device has, so it plays at once instead of staying silent.
- The configuration menu in the top bar marks the current configuration in amber, like the other menus.
- Follow Start/Stop on every channel and insert effect, saved in the configuration. Tempo always reaches a plugin, but it sees the transport start and stop only with the switch on. Instruments start with it off, so an internal sequencer stays still until you ask for it, and effects start with it on.
- In a low window the effects of a channel scroll, so its warnings and audio output stay in view.
- A plugin counts as changed only when its sound differs between opening and closing its window, and that marks the configuration unsaved. Plugins that stamp the time or renew their ids in their state, like Mariana, do not read as changed when nobody touched them. A long plugin name on a channel shrinks to fit before it is cut off.
- A plugin that runs away can no longer blast the outputs: broken samples become silence and the signal stops at +12 dB, on every channel and on the device. This is a safety ceiling that clips, not a limiter.
- When microphone access is denied, the mixer and Settings say "Microphone access denied, inputs are silent" instead of leaving every audio and sidechain input quietly dead.
- When your audio device or the system's default output has inputs, the app asks for microphone access before it opens any device, and the mixer says "Waiting for microphone access" until you answer. The app no longer hangs while its own question is open: Settings, menus and Quit keep working.
- Updates: at every launch the app asks whether a newer version exists and offers it, and Check for Updates… in the app menu asks right away. Nothing is installed without your OK.
