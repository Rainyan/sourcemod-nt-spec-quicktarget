#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

#define PLUGIN_VERSION "0.5"

#define NEO_MAX_PLAYERS 32

#define OBS_MODE_FOLLOW 4
#define OBS_MODE_FREEFLY 5

// This plugin relies on the nt_ghostcap plugin for detecting ghost events.
// If for whatever reason you don't want to run that plugin, comment out this define
// to remove support for ghost related spectating events detection.
#define REQUIRE_NT_GHOSTCAP_PLUGIN

//#define DEBUG

static stock float vec3_origin[3];

static int _spec_userid_target[NEO_MAX_PLAYERS + 1];
static bool _is_lerping_specview[NEO_MAX_PLAYERS + 1];
static bool _is_following_grenade[NEO_MAX_PLAYERS + 1];
// Doing this check ahead of time to avoid having to do it for every frame.
static bool _is_spectator[NEO_MAX_PLAYERS + 1];

static int _last_attacker_userid;
static int _last_killer_userid;
#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
static int _last_ghost_carrier_userid;
#endif
static int _last_event_userid_generic;
static int _last_hurt_userid;
static int _last_shooter_userid;

static int _last_live_grenade;

ConVar g_hCvar_LerpSpeed = null;

public Plugin myinfo = {
	name = "NT Spectator Quick Target",
	description = "Binds for quickly spectating where the action is",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-nt-spec-quicktarget"
};

public void OnPluginStart()
{
#if defined DEBUG
	RegConsoleCmd("sm_lm", Cmd_LerpMove);
#endif
	
	// This command lists and explains the binds. Make sure to update it if adding new commands.
	RegConsoleCmd("sm_binds", Cmd_ListBinds, "List of special spectator bindings provided by the NT Spectator Quick Target plugin.");
	
	RegConsoleCmd("sm_spec_last_attacker", Cmd_SpecLastAttacker, "Target on the last player who did damage.");
	RegConsoleCmd("sm_spec_last_killer", Cmd_SpecLastKiller, "Target on the last player who got a kill.");
	RegConsoleCmd("sm_spec_last_hurt", Cmd_SpecLastHurt, "Target on the last player who was damaged.");
#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
	RegConsoleCmd("sm_spec_last_ghoster", Cmd_SpecLastGhoster, "Target on the last ghost carrier.");
#endif
	RegConsoleCmd("sm_spec_last_shooter", Cmd_SpecLastShooter, "Target on the last player who fired their weapon.");
	RegConsoleCmd("sm_spec_last_event", Cmd_SpecLastEvent, "Target on the latest generic event of interest.");
	
	RegConsoleCmd("sm_spec_toggle_lerp", Cmd_ToggleLerp, "Toggle smoothly lerping to the spectating events.");
	
	RegConsoleCmd("sm_spec_follow_grenade", Cmd_FollowGrenade, "Follow the path of the last live grenade.");
	
	CreateConVar("sm_spec_quicktarget_version", PLUGIN_VERSION, "NT Spectator Quick Target plugin version.", FCVAR_DONTRECORD);
	
	g_hCvar_LerpSpeed = CreateConVar("sm_spec_lerp_speed", "2.0", "How fast to lerp the spectating event switch.", _, true, 0.001, true, 10.0);
	
	if (!HookEventEx("player_death", Event_PlayerDeath, EventHookMode_Post)) {
		SetFailState("Failed to hook event player_death");
	}
	else if (!HookEventEx("player_hurt", Event_PlayerHurt, EventHookMode_Post)) {
		SetFailState("Failed to hook event player_hurt");
	}
	else if (!HookEventEx("player_team", Event_PlayerTeam, EventHookMode_Pre)) {
		SetFailState("Failed to hook event player_team");
	}
}

#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
public void OnAllPluginsLoaded()
{
	if (FindConVar("sm_ntghostcap_version") == null) {
		SetFailState("This plugin requires the nt_ghostcap plugin.");
	}
}
#endif

public void OnClientDisconnected(int client)
{
	_spec_userid_target[client] = 0;
	_is_lerping_specview[client] = false;
	_is_spectator[client] = false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "grenade_projectile"))
	{
		_last_live_grenade = entity;
	}
}

public void OnEntityDestroyed(int entity)
{
	if (entity == _last_live_grenade) {
		_last_live_grenade = 0;
	}
}

public void Event_PlayerDeath(Event event, const char[] name,
	bool dontBroadcast)
{	
	_last_killer_userid = event.GetInt("attacker");
	_last_event_userid_generic = _last_killer_userid;
	
	// If someone attempts to spectate to an already dead player,
	// give them some other event of interest, instead.
	if (_last_hurt_userid == event.GetInt("userid")) {
		_last_hurt_userid = _last_event_userid_generic;
	}
}

public void Event_PlayerHurt(Event event, const char[] name,
	bool dontBroadcast)
{
	_last_hurt_userid = event.GetInt("userid");
	_last_attacker_userid = event.GetInt("attacker");
	_last_event_userid_generic = _last_attacker_userid;
}

public void Event_PlayerTeam(Event event, const char[] name,
	bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int this_client = GetClientOfUserId(userid);
	
	if (this_client != 0) {
		_spec_userid_target[this_client] = 0;
		_is_spectator[this_client] = (event.GetInt("team") == TEAM_SPECTATOR);
		
		// Cancel special spectate mode for anyone who was actively spectating this team-changing client.
		for (int client = 1; client <= MaxClients; ++client) {
			if (_spec_userid_target[client] == userid) {
				_spec_userid_target[client] = 0;
			}
		}
	}
	else {
		_is_spectator[this_client] = false;
	}
}

#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
// This global forward listener relies on nt_ghostcap plugin.
public void OnGhostPickUp(int client)
{
	_last_ghost_carrier_userid = GetClientUserId(client);
	_last_event_userid_generic = _last_ghost_carrier_userid;
}
#endif

public Action Cmd_ListBinds(int client, int argc)
{
	PrintToConsole(client, "\n== NT Spectator Quick Target bindings ==\n\
sm_binds — This bindings list.\n\
sm_spec_toggle_lerp — Toggle lerping between the spectating events.\n\
sm_spec_lerp_speed — Server cvar for controlling the lerp speed (sm_cvar ...).\n\
\n\
sm_spec_follow_grenade — Follow the last live HE grenade.\n\
sm_spec_last_hurt — Target on the last player who was damaged.\n\
sm_spec_last_shooter — Target on the last player who fired their weapon.\n\
sm_spec_last_event — Target on the latest event of any kind from the list below:\n\
sm_spec_last_attacker — Target on the last player who did damage.\n\
sm_spec_last_killer — Target on the last player who got a kill.");
#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
	PrintToConsole(client, "sm_spec_last_ghoster — Target on the last ghost carrier.");
#endif
	ReplyToCommand(client, "\n[SM] Spectator Quick Target bindings have been printed to your console.");
	return Plugin_Handled;
}

#if defined DEBUG
public Action Cmd_LerpMove(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	
	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientInGame(i) && IsFakeClient(i)) {
			_spec_userid_target[client] = GetClientUserId(i);
		}
	}
	return Plugin_Handled;
}
#endif

public Action Cmd_SpecLastAttacker(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_spec_userid_target[client] = _last_attacker_userid;
	return Plugin_Handled;
}

public Action Cmd_SpecLastKiller(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_spec_userid_target[client] = _last_killer_userid;
	return Plugin_Handled;
}

public Action Cmd_SpecLastHurt(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_spec_userid_target[client] = _last_hurt_userid;
	return Plugin_Handled;
}

#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
public Action Cmd_SpecLastGhoster(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_spec_userid_target[client] = _last_ghost_carrier_userid;
	return Plugin_Handled;
}
#endif

public Action Cmd_ToggleLerp(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_is_lerping_specview[client] = !_is_lerping_specview[client];
	return Plugin_Handled;
}

public Action Cmd_SpecLastShooter(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_spec_userid_target[client] = _last_shooter_userid;
	return Plugin_Handled;
}

public Action Cmd_SpecLastEvent(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_spec_userid_target[client] = _last_event_userid_generic;
	return Plugin_Handled;
}

public Action Cmd_FollowGrenade(int client, int argc)
{
	if (GetClientTeam(client) != TEAM_SPECTATOR) {
		return Plugin_Handled;
	}
	_is_following_grenade[client] = !_is_following_grenade[client];
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3],
	float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount,
	int& seed, int mouse[2])
{
	// Not a spectator
	if (!_is_spectator[client]) {
		if ((buttons & IN_ATTACK) && IsPlayerAlive(client)) {
			_last_shooter_userid = GetClientUserId(client);
		}
		return Plugin_Continue;
	}
	
	// No spectator transition active
	if (_spec_userid_target[client] == 0) {
		return Plugin_Continue;
	}
	
	// Spectator is overriding the transition with their input
	if (buttons != 0) {
		_spec_userid_target[client] = 0;
		return Plugin_Continue;
	}
	
	if (_is_following_grenade[client]) {
		if (_last_live_grenade == 0 || !IsValidEntity(_last_live_grenade)) {
			_is_following_grenade[client] = false;
			return Plugin_Continue;
		}
		
		float start_pos[3];
		float target_pos[3];
		float final_pos[3];
		
		float start_ang[3];
		float target_dir[3];
		float target_ang[3];
		float final_ang[3];
		
		GetClientEyePosition(client, start_pos);
		GetEntPropVector(_last_live_grenade, Prop_Send, "m_vecOrigin", target_pos);
		VectorLerp(start_pos, target_pos, final_pos);
		
		GetClientEyeAngles(client, start_ang);
		SubtractVectors(target_pos, start_pos, target_dir);
		NormalizeVector(target_dir, target_dir);
		GetVectorAngles(target_dir, target_ang);
		LerpAngles(start_ang, target_ang, final_ang);
		
		TeleportEntity(client, final_pos, final_ang, NULL_VECTOR);
		
		return Plugin_Continue;
	}
	
	int target_client = GetClientOfUserId(_spec_userid_target[client]);
	// Make sure the target hasn't disconnected
	if (target_client == 0 ||
		// And make sure they're still alive
		!IsPlayerAlive(target_client))
	{
		_spec_userid_target[client] = 0;
		return Plugin_Continue;
	}
	
	if (_is_lerping_specview[client]) {
		float start_pos[3];
		float target_pos[3];
		float final_pos[3];
		
		float start_ang[3];
		float target_dir[3];
		float target_ang[3];
		float final_ang[3];
		
		GetClientEyePosition(client, start_pos);
		GetClientEyePosition(target_client, target_pos);
		VectorLerp(start_pos, target_pos, final_pos);
		
		GetClientEyeAngles(client, start_ang);
		SubtractVectors(target_pos, start_pos, target_dir);
		NormalizeVector(target_dir, target_dir);
		GetVectorAngles(target_dir, target_ang);
		LerpAngles(start_ang, target_ang, final_ang);
		
		TeleportEntity(client, final_pos, final_ang, NULL_VECTOR);
		
		// Observer follow mode distance from spectated player is 100 units (expressed as squared here)
		if (GetVectorDistance(start_pos, target_pos, true) > 10000) {
			// Make sure we're free flying for the smooth transition
			if (GetEntProp(client, Prop_Send, "m_iObserverMode") != OBS_MODE_FREEFLY) {
				SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FREEFLY);
			}
		}
		else {
			PrintToChat(client, "Reached target (obsmode: %d, handle: %d)",
				GetEntProp(client, Prop_Send, "m_iObserverMode"),
				GetEntPropEnt(client, Prop_Send, "m_hObserverTarget"));
			
			// Reached target, start following the spectated player
			SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FOLLOW);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target_client);
			_spec_userid_target[client] = 0;
		}
	}
	else {
		SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FOLLOW);
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target_client);
		_spec_userid_target[client] = 0;
	}
	
	return Plugin_Continue;
}

stock bool VectorsEqual(const float[3] v1, const float[3] v2, const float max_ulps = 0.0)
{
	// Needs to exactly equal.
	if (max_ulps == 0) {
		return v1[0] == v2[0] && v1[1] == v2[1] && v1[2] == v2[2];
	}
	// Allow an inaccuracy of size max_ulps.
	else {
		if (FloatAbs(v1[0] - v2[0]) > max_ulps) { return false; }
		if (FloatAbs(v1[1] - v2[1]) > max_ulps) { return false; }
		if (FloatAbs(v1[2] - v2[2]) > max_ulps) { return false; }
		return true;
	}
}

stock float Clamp(float value, float min, float max)
{
	return value < min ? min : value > max ? max : value;
}

stock float Lerp(float a, float b, float scale = 0.0)
{
	if (scale == 0) {
		scale = GetGameFrameTime() * g_hCvar_LerpSpeed.FloatValue;
	}
#if(0)
	scale = fclamp(scale, -1.0, 1.0);
#endif
	return a + (b - a) * scale;
}

stock void VectorLerp(const float[3] v1, const float[3] v2, float[3] res, const float scale = 0.0)
{
	res[0] = Lerp(v1[0], v2[0], scale);
	res[1] = Lerp(v1[1], v2[1], scale);
	res[2] = Lerp(v1[2], v2[2], scale);
}

stock float LerpAngles(const float a[3], const float b[3], float res[3], const float t = 0.0)
{
	res[0] = LerpAngle(a[0], b[0], t);
	res[1] = LerpAngle(a[1], b[1], t);
	res[2] = LerpAngle(a[2], b[2], t);
}

// Lerp that takes the shortest rotation around a circle
stock float LerpAngle(const float a, const float b, float t = 0.0)
{
	float dt = Clamp((b - a) - RoundToFloor((b - a) / 360.0) * 360.0, 0.0, 360.0);
	return Lerp(a, a + (dt > 180 ? dt - 360 : dt), t);
}