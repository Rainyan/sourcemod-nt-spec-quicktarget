# sourcemod-nt-spec-quicktarget
SourceMod plugin for Neotokyo. Binds for quickly spectating where the action is.

# Compile requirements
* SourceMod 1.7 or newer
* [SourceMod Neotokyo include](https://github.com/softashell/sourcemod-nt-include)

# Server requirements
This plugin depends on the [nt_ghostcap](https://github.com/softashell/nt-sourcemod-plugins/blob/master/scripting/nt_ghostcap.sp) plugin.

If for whatever reason you don't want to run the nt_ghostcap plugin, uncomment the *REQUIRE_NT_GHOSTCAP_PLUGIN* define in the source code before compiling to disable ghost related features.

# Usage

## Console commands
These commands are recommended to be used as binds. They only work for players in the spectator team.

* *sm_binds* — Print this usage info into game console.

* *sm_spec_follow_grenade* — Follow the last live HE grenade.
* *sm_spec_last_hurt* — Target on the last player who was damaged.
* *sm_spec_last_shooter* — Target on the last player who fired their weapon.
* *sm_spec_last_event* — Target on the latest event of any kind from the list below:
  * *sm_spec_last_attacker* — Target on the last player who did damage.
  * *sm_spec_last_killer* — Target on the last player who got a kill.
  * *sm_spec_last_ghoster* — Target on the last ghost carrier.

## Cvars
**TODO: turn these into cookies**
* *sm_spec_lerp_speed* — Server cvar for controlling the lerp speed ("sm_cvar ..."). Default: 2. Range: (0.001 - 10).

## Cookies
These cookies are opt-in (default is off), and the value will persist on the server.

Supported values: 0 and 1. You can set these commands in the game console.

* *sm_cookies spec_newround_ghost 0/1* — Whether to automatically spectate the ghost spawn position on new rounds.
* *sm_cookies spec_newround_ghost_no_fade 0/1* — Whether to disable the fade-from-black effect when speccing a ghost spawn.
