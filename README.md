# sourcemod-nt-spec-quicktarget
SourceMod plugin for Neotokyo. Binds for quickly spectating where the action is.

# Compile requirements
* SourceMod 1.10 or newer
* [SourceMod Neotokyo include](https://github.com/softashell/sourcemod-nt-include)
* The [scripting/include files](scripting/include) of this project must be accessible for the compiler.

# Server requirements
This plugin depends on the [nt_ghostcap](https://github.com/softashell/nt-sourcemod-plugins/blob/master/scripting/nt_ghostcap.sp) plugin.

If for whatever reason you don't want to run the nt_ghostcap plugin, uncomment the *REQUIRE_NT_GHOSTCAP_PLUGIN* define in the source code before compiling to disable ghost related features.

# Usage

Also see [the wiki](https://github.com/Rainyan/sourcemod-nt-spec-quicktarget/wiki/So-You-Wanna-Be-An-Observer) for more info, example configs, etc.

## Console commands
These commands are recommended to be used as binds. They only work for players in the spectator team.

* *sm_binds* — Print this usage info into game console.

* *sm_spec_slot <1-10>* — Binds for spectating specific players in a 5v5 match context, by ascending client index number.
  * The indices 1-5 represent Jinrai team
  * The indices 6-10 represent NSF team

* *sm_spec_caster_slot <1-32>* — Binds for spectating whatever/whomever another caster/observer is currently spectating, by slot number.
  * Index 1 will be the first caster/observer other than yourself.
  * Any other casters/observers will follow in contiguous n+1 order (1, 2, 3, ...) up to the maximum index of 32.

* *sm_spec_toggle_lerp* — Toggle smoothly lerping to the spectating events of this plugin. Defaults to off.
* *sm_spec_follow_grenade* — Follow the last live HE grenade.
* *sm_spec_latch_to_closest* — Spectate the player closest to camera position.
* *sm_spec_latch_to_fastest* — Spectate the fastest moving player.
* *sm_spec_latch_to_aim* — Spectate the player currently being aimed at, ignoring walls. Alternative hotkey: hold sprint and press mouse1.

* *sm_spec_last_hurt* — Target on the last player who was damaged.
* *sm_spec_last_shooter* — Target on the last player who fired their weapon.
* *sm_spec_last_event* — Target on the latest event of any kind from the list below:
  * *sm_spec_last_attacker* — Target on the last player who did damage.
  * *sm_spec_last_killer* — Target on the last player who got a kill.
  * *sm_spec_last_ghoster* — Target on the last ghost carrier.

* *sm_spec_pos* — Teleport to position.
  * Recommended to be set up beforehand for interesting camera shots, and bound to keys for ease of use.
  * You can use this by first using `getpos` at desired location, which returns your current position encoded as:
    * `setpos <x> <y> <z>;setang <x> <y> <z>`
  * Then, append `sm_spec_pos` with that `getpos` output, wrapped inside double quotes. For example:
    * `sm_spec_pos "setpos 242.187500 717.187500 -66.406250;setang 5.447200 50.649540 0.000000"`
  * You may optionally omit the `setang` portion of the encoded position string, if you don't want to modify the viewing angle.
* *sm_spec_lerpto* — Lerp to position.
  * The same as `sm_spec_pos`, but uses a smoothed\* transition between the positions instead of snapping instantly.
    * *\*Depends on your server ping.*

## Binds
* `+thermoptic` — Camera orbit.
  * Allows orbiting the camera around the center of the current view in third-person mode.
  * The smoothness of this relies on your ping to the server; if you have high ping, doing a slow orbit may look nicer than a fast one.
* `+up` — Move camera up.
* `+down` — Move camera down.
* Regular movement keys — Will automatically unlatch to free-fly mode, if currently latched onto a player.
  * Convenient for not needing to press spacebar to leave a player when transitioning to free-fly mode.
* Sprint key + Attack — Shortcut for `sm_spec_latch_to_aim`

## Cvars
**TODO: turn these into cookies**

These values can be set in the server with *"sm_cvar ..."*, or in config files.

* *sm_spec_lerp_speed* — Server cvar for controlling the lerp speed. Default: 2. Range: (0.001 - 10).

## Cookies
These per-client cookies are opt-in (default is off), and the value will persist on the server.

Supported values: 0 and 1. You can set these commands in the game console.

* *sm_cookies spec_autorotate 0/1* — Whether to automatically rotate the camera towards the spectated target's orientation. Auto rotation is currently supported with the *sm_spec_last_...* binds, and when using mouse1/2 to select spectator targets.
* *sm_cookies spec_newround_ghost 0/1* — Whether to automatically spectate the ghost spawn position on new rounds.
* *sm_cookies spec_newround_ghost_no_fade 0/1* — By default, the *spec_newround_ghost* option will apply a short fade-from-black to hide the visual of the ghost spawning from thin air. This cookies controls whether to disable that fade effect.
