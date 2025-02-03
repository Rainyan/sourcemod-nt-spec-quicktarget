# sourcemod-nt-spec-quicktarget

SourceMod plugin for Neotokyo. Binds for quickly spectating where the action is.

# Compile requirements

- SourceMod 1.10 or newer
- [SourceMod Neotokyo include](https://github.com/softashell/sourcemod-nt-include)

# Server requirements

This plugin depends on the [nt_ghostcap](https://github.com/softashell/nt-sourcemod-plugins/blob/master/scripting/nt_ghostcap.sp) plugin.

If for whatever reason you don't want to run the nt_ghostcap plugin, uncomment the `REQUIRE_NT_GHOSTCAP_PLUGIN` define in the source code before compiling to disable ghost related features.

# Usage

For detailed information, see the sections below in this document.

There's also [the wiki](https://github.com/Rainyan/sourcemod-nt-spec-quicktarget/wiki/So-You-Wanna-Be-An-Observer) for more info, example configs, etc.

## Console commands

These commands are recommended to be used as binds. They only work for players in the spectator team.

- _sm_binds_ — Print this usage info into game console.

- _sm_spec_slot <1-10>_ — Binds for spectating specific players in a 5v5 match context, by ascending client index number.

  - The indices 1-5 represent Jinrai team
  - The indices 6-10 represent NSF team

- _sm_spec_caster_slot <1-32>_ — Binds for spectating whatever/whomever another caster/observer is currently spectating, by slot number.

  - Index 1 will be the first caster/observer other than yourself.
  - Any other casters/observers will follow in contiguous n+1 order (1, 2, 3, ...) up to the maximum index of 32.

- _sm_spec_toggle_lerp_ — Toggle smoothly lerping to the spectating events of this plugin. Defaults to off.
- _sm_spec_follow_grenade_ — Follow the last live HE grenade.
- _sm_spec_latch_to_closest_ — Spectate the player closest to camera position.
- _sm_spec_latch_to_fastest_ — Spectate the fastest moving player.
- _sm_spec_latch_to_aim_ — Spectate the player currently being aimed at, ignoring walls. Alternative hotkey: hold sprint and press mouse1.

- _sm_spec_last_hurt_ — Target on the last player who was damaged.
- _sm_spec_last_shooter_ — Target on the last player who fired their weapon.
- _sm_spec_last_event_ — Target on the latest event of any kind from the list below:

  - _sm_spec_last_attacker_ — Target on the last player who did damage.
  - _sm_spec_last_killer_ — Target on the last player who got a kill.
  - _sm_spec_last_ghoster_ — Target on the last ghost carrier.

- _sm_spec_pos_ — Teleport to position.
  - Recommended to be set up beforehand for interesting camera shots, and bound to keys for ease of use.
  - You can use this by first using `getpos` at desired location, which returns your current position encoded as:
    - `setpos <x> <y> <z>;setang <x> <y> <z>`
  - Then, append `sm_spec_pos` with that `getpos` output, wrapped inside double quotes. For example:
    - `sm_spec_pos "setpos 242.187500 717.187500 -66.406250;setang 5.447200 50.649540 0.000000"`
  - You may optionally omit the `setang` portion of the encoded position string, if you don't want to modify the viewing angle.
- _sm_spec_lerpto_ — Lerp to position.
  - The same as `sm_spec_pos`, but uses a smoothed\* transition between the positions instead of snapping instantly.
    - _\*Depends on your server ping._

## Binds

- `+thermoptic` — Camera orbit.
  - Allows orbiting the camera around the center of the current view in third-person mode.
  - The smoothness of this relies on your ping to the server; if you have high ping, doing a slow orbit may look nicer than a fast one.
- `+up` — Move camera up.
- `+down` — Move camera down.
- Regular movement keys — Will automatically unlatch to free-fly mode, if currently latched onto a player.
  - Convenient for not needing to press spacebar to leave a player when transitioning to free-fly mode.
- Sprint key + Attack — Shortcut for `sm_spec_latch_to_aim`

## Cookies

These per-client cookies are opt-in (default is off), and the value will persist on the server.

### Binary cookies

Supported values: 0 and 1. You can set these commands in the game console.

- _sm_cookies spec_autorotate 0/1_ — Whether to automatically rotate the camera towards the spectated target's orientation. Auto rotation is currently supported with the _sm*spec_last*..._ binds, and when using mouse1/2 to select spectator targets. Default: 1.
- _sm_cookies spec_newround_ghost 0/1_ — Whether to automatically spectate the ghost spawn position on new rounds. Default: 0.
- _sm_cookies spec_newround_ghost_no_fade 0/1_ — By default, the _spec_newround_ghost_ option will apply a short fade-from-black to hide the visual of the ghost spawning from thin air. This cookies controls whether to disable that fade effect. Default: 0.

### Float cookies

- _sm_cookies spec_lerp_scale 2.0_ — Controls the lerp speed scale. Higher value results in a faster lerp. Default: 2.0. Allowed range: (0.001 - 10.0).
