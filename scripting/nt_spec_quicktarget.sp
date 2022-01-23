#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>

#include <neotokyo>

#include "sp_shims.inc"

#define PLUGIN_VERSION "0.8.5"

#define NEO_MAX_PLAYERS 32

#define OBS_MODE_FOLLOW 4
#define OBS_MODE_FREEFLY 5

// This plugin relies on the nt_ghostcap plugin for detecting ghost events.
// If for whatever reason you don't want to run that plugin, comment out this define
// to remove support for ghost related spectating events detection.
#define REQUIRE_NT_GHOSTCAP_PLUGIN

// This is the distance from player the spectator camera is at when following them.
#define FREEFLY_CAMERA_DISTANCE_FROM_TARGET 100.0

//#define DEBUG

static int _spec_userid_target[NEO_MAX_PLAYERS + 1];
static bool _is_lerping_specview[NEO_MAX_PLAYERS + 1];
static bool _is_following_grenade[NEO_MAX_PLAYERS + 1];
static int _follow_explosive[NEO_MAX_PLAYERS + 1];
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

static int _last_ghost;
static bool _is_currently_displaying_ghost_location;
static float _ghost_display_location[3];

static int _prev_consumed_buttons[NEO_MAX_PLAYERS + 1];

ConVar g_hCvar_LerpSpeed = null;

Handle _cookie_AutoSpecGhostSpawn = INVALID_HANDLE;
Handle _cookie_NoFadeFromBlackOnAutoSpecGhost = INVALID_HANDLE;
Handle _cookie_AutoRotate = INVALID_HANDLE;

static bool _client_wants_autospec_ghost_spawn[NEO_MAX_PLAYERS + 1];
static bool _client_wants_no_fade_for_autospec_ghost_spawn[NEO_MAX_PLAYERS + 1];
static bool _client_wants_auto_rotate[NEO_MAX_PLAYERS + 1];
static bool _client_wants_latch_to_closest[NEO_MAX_PLAYERS + 1];
static bool _client_wants_latch_to_fastest[NEO_MAX_PLAYERS + 1];

public Plugin myinfo = {
    name = "NT Spectator Quick Target",
    description = "Binds for quickly spectating where the action is",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-spec-quicktarget"
};

public void OnPluginStart()
{
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

    RegConsoleCmd("sm_spec_latch_to_closest", Cmd_LatchToClosest, "Start spectating the player closest to current camera position.");
    RegConsoleCmd("sm_spec_latch_to_fastest", Cmd_LatchToFastest, "Start spectating the player moving the fastest.");

    RegConsoleCmd("sm_spec_slot", Cmd_Slot, "Target player by slot number (1-10).");

    CreateConVar("sm_spec_quicktarget_version", PLUGIN_VERSION, "NT Spectator Quick Target plugin version.", FCVAR_DONTRECORD);

    // TODO: convert into cookie
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
    else if (!HookEventEx("game_round_start", Event_RoundStart, EventHookMode_Post)) {
        SetFailState("Failed to hook event game_round_start");
    }

    // Spectator team consumes IN_ATTACK bits when triggering spec_next, so need to set up a command listener, instead of capturing the buttons.
    if (!AddCommandListener(CommandListener_SpecNext, "spec_next")) {
        SetFailState("Failed to set command listener for spec_next");
    }

    _cookie_AutoSpecGhostSpawn = RegClientCookie("spec_newround_ghost",
        "NT Spectator Quick Target plugin: Whether to automatically spectate the ghost spawn position on new rounds.",
        CookieAccess_Public);
    _cookie_NoFadeFromBlackOnAutoSpecGhost = RegClientCookie("spec_newround_ghost_no_fade",
        "NT Spectator Quick Target plugin: Whether to disable the fade-from-black effect when speccing a ghost spawn.",
        CookieAccess_Public);
    _cookie_AutoRotate = RegClientCookie("spec_autorotate",
        "NT Spectator Quick Target plugin: Automatically rotate according to spectator direction.",
        CookieAccess_Public);

    for (int client = 1; client <= MaxClients; ++client) {
        if (AreClientCookiesCached(client)) {
            OnClientCookiesCached(client);
        }
        if (IsClientInGame(client))
        {
            _is_spectator[client] = (GetClientTeam(client) == TEAM_SPECTATOR);
        }
    }
    RegConsoleCmd("sm_cookies", Cmd_Cookies);
}

public Action CommandListener_SpecNext(int client, const char[] command, int argc)
{
    // Even though the game handles spec_next natively,
    // we call our own implementation here to enable custom camera rotation.
    if (_is_spectator[client])
    {
        // The "spec_next" cmd will have already modified this,
        // so we can just use the value it as-is.
        int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        if (target > 0 && target <= MaxClients && IsClientInGame(target))
        {
            SetClientSpectateTarget(client, target);
        }
        _is_following_grenade[client] = false;
    }

    return Plugin_Continue;
}

public Action Cmd_Cookies(int client, int argc)
{
    if (AreClientCookiesCached(client))
    {
        OnClientCookiesCached(client);
    }

    return Plugin_Continue;
}

#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
public void OnAllPluginsLoaded()
{
    if (FindConVar("sm_ntghostcap_version") == null) {
        SetFailState("This plugin requires the nt_ghostcap plugin.");
    }
}
#endif

public Action Cmd_Slot(int client, int argc)
{
    _is_following_grenade[client] = false;

    if (!_is_spectator[client])
    {
        return Plugin_Handled;
    }

    int min = 1;
    int max = 10;

    if (argc != 1)
    {
        char cmdname[32];
        GetCmdArg(0, cmdname, sizeof(cmdname));
        ReplyToCommand(client, "Usage: %s <number in range %d-%d>",
            cmdname, min, max);
        return Plugin_Handled;
    }

    char num_buffer[3];
    GetCmdArg(1, num_buffer, sizeof(num_buffer));
    int num = Clamp(StringToInt(num_buffer), min, max);

    // Jinrai: slots 1-5 and NSF: slots 6-10
    int team = (num <= 5) ? TEAM_JINRAI : TEAM_NSF;
    if (team == TEAM_NSF)
    {
        // How manieth client do we want of this team. Offset NSF by -5 slots,
        // so 6 becomes 1 for NSF, etc.
        num -= 5;
    }

    int target;
    for (int i = 1; i <= MaxClients && num > 0; ++i)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != team)
        {
            continue;
        }

        target = i;
        --num;
    }

    if (target != 0)
    {
        SetClientSpectateTarget(client, target);
    }

    return Plugin_Handled;
}

void SetClientSpectateTarget(int client, int target)
{
    bool rotate = _client_wants_auto_rotate[client] ||
        (GetEntProp(client, Prop_Send, "m_iObserverMode") == OBS_MODE_FREEFLY);

    float pos[3];
    float ang[3];

    if (rotate)
    {
        GetClientAbsAngles(target, ang);
        GetFreeflyCameraPosBehindPlayer(target, ang, pos);
    }

    SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);

    TeleportEntity(client,
        rotate ? pos : NULL_VECTOR,
        rotate ? ang : NULL_VECTOR,
        NULL_VECTOR);

    _spec_userid_target[client] = 0;
}

public void OnClientCookiesCached(int client)
{
    char wants_ghost_spawn_spec[2];
    char wants_no_fade[2];
    char wants_auto_rotate[2];

    GetClientCookie(client, _cookie_AutoSpecGhostSpawn, wants_ghost_spawn_spec, sizeof(wants_ghost_spawn_spec));
    GetClientCookie(client, _cookie_NoFadeFromBlackOnAutoSpecGhost, wants_no_fade, sizeof(wants_no_fade));
    GetClientCookie(client, _cookie_AutoRotate, wants_auto_rotate, sizeof(wants_auto_rotate));

    _client_wants_autospec_ghost_spawn[client] = (wants_ghost_spawn_spec[0] != 0 && wants_ghost_spawn_spec[0] != '0');
    _client_wants_no_fade_for_autospec_ghost_spawn[client] = (wants_no_fade[0] != 0 && wants_no_fade[0] != '0');
    _client_wants_auto_rotate[client] = (wants_auto_rotate[0] != 0 && wants_auto_rotate[0] != '0');
}

public void OnClientDisconnected(int client)
{
    _spec_userid_target[client] = 0;
    _is_lerping_specview[client] = false;
    _is_spectator[client] = false;
    _is_following_grenade[client] = false;
    _follow_explosive[client] = 0;

    _client_wants_autospec_ghost_spawn[client] = false;
    _client_wants_no_fade_for_autospec_ghost_spawn[client] = false;
    _client_wants_auto_rotate[client] = false;
    _client_wants_latch_to_closest[client] = false;
    _client_wants_latch_to_fastest[client] = false;

    _prev_consumed_buttons[client] = 0;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "grenade_projectile")) {
        _last_live_grenade = entity;
    }
    else if (StrEqual(classname, "weapon_ghost")) {
        _last_ghost = EntIndexToEntRef(entity);
    }
}

public void OnEntityDestroyed(int entity)
{
    // Ent ref didn't seem to work well with the projectiles, so manually handling ent index lifetime.
    if (_last_live_grenade == entity)
    {
        _last_live_grenade = 0;
    }
    for (int i = 1; i <= MaxClients; ++i)
    {
        if (_follow_explosive[i] == entity)
        {
            _follow_explosive[i] = 0;
            _is_following_grenade[i] = false;
        }
    }
}

public void OnMapEnd()
{
    // Ent ref didn't seem to work well with the projectiles, so manually handling ent index lifetime.
    _last_live_grenade = 0;
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
        _is_following_grenade[this_client] = false;
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

static Handle g_hTimer_FinishDisplayGhostSpawnLocation = INVALID_HANDLE;

public void Event_RoundStart(Event event, const char[] name,
    bool dontBroadcast)
{
    _last_live_grenade = 0;
    for (int i = 1; i <= MaxClients; ++i)
    {
        _is_following_grenade[i] = false;
        _follow_explosive[i] = 0;
    }

    if (_last_ghost != 0) {
        _is_currently_displaying_ghost_location = true;
        _ghost_display_location = NULL_VECTOR;

        if (g_hTimer_FinishDisplayGhostSpawnLocation != INVALID_HANDLE) {
            KillTimer(g_hTimer_FinishDisplayGhostSpawnLocation);
        }
        g_hTimer_FinishDisplayGhostSpawnLocation = CreateTimer(5.0, Timer_FinishDisplayGhostSpawnLocation);

        FadeSpecs();
    }
}

void FadeSpecs()
{
    int specs[NEO_MAX_PLAYERS];
    int num_specs;

    for (int client = 1; client <= MaxClients; ++client) {
        if (!IsClientInGame(client) || !_is_spectator[client]) {
            continue;
        }

        if (!_client_wants_autospec_ghost_spawn[client]) {
            continue;
        }

        if (_client_wants_no_fade_for_autospec_ghost_spawn[client]) {
            continue;
        }

        specs[num_specs++] = client;
    }

    if (num_specs == 0) {
        return;
    }

    Handle userMsg = StartMessage("Fade", specs, num_specs);
    BfWriteShort(userMsg, 1000); // Fade alpha transition duration, in ms
    BfWriteShort(userMsg, 200); // How long to sustain the fade, in ms
    BfWriteShort(userMsg, 0x0001); // Fade in flag
    BfWriteByte(userMsg, 0); // RGBA red
    BfWriteByte(userMsg, 0); // RGBA green
    BfWriteByte(userMsg, 0); // RGBA blue
    BfWriteByte(userMsg, 255); // RGBA alpha
    EndMessage();
}

public Action Timer_FinishDisplayGhostSpawnLocation(Handle timer)
{
    _is_currently_displaying_ghost_location = false;
    _ghost_display_location = NULL_VECTOR;

    g_hTimer_FinishDisplayGhostSpawnLocation = INVALID_HANDLE;
    return Plugin_Stop;
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
\n\
sm_spec_slot <1-10> — Binds for spectating specific players in a 5v5 match \
context, by ascending client index number.\n\
The indices 1-5 represent Jinrai team, and indices 6-10 NSF team.\n\
\n\
sm_spec_toggle_lerp — Toggle lerping between the spectating events.\n\
sm_spec_lerp_speed — Server cvar for controlling the lerp speed (sm_cvar ...).\n\
\n\
sm_spec_latch_to_closest — Spectate the player closest to camera position.\n\
sm_spec_latch_to_fastest — Spectate the fastest moving player.\n\
sm_spec_follow_grenade — Follow the last live HE grenade.\n\
\n\
sm_spec_last_hurt — Target on the last player who was damaged.\n\
sm_spec_last_shooter — Target on the last player who fired their weapon.\n\
\n\
sm_spec_last_event — Target on the latest event of any kind from the list below:\n\
\n\
\tsm_spec_last_attacker — Target on the last player who did damage.\n\
\tsm_spec_last_killer — Target on the last player who got a kill.");
#if defined REQUIRE_NT_GHOSTCAP_PLUGIN
    PrintToConsole(client, "\tsm_spec_last_ghoster — Target on the last ghost carrier.");
#endif
    ReplyToCommand(client, "\n[SM] Spectator Quick Target bindings have been printed to your console.");
    return Plugin_Handled;
}

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
    if (GetClientTeam(client) == TEAM_SPECTATOR) {
        _is_following_grenade[client] = true;
    }
    return Plugin_Handled;
}

public Action Cmd_LatchToClosest(int client, int argc)
{
    if (GetClientTeam(client) != TEAM_SPECTATOR) {
        return Plugin_Handled;
    }
    _client_wants_latch_to_closest[client] = true;
    return Plugin_Handled;
}

public Action Cmd_LatchToFastest(int client, int argc)
{
    if (GetClientTeam(client) != TEAM_SPECTATOR) {
        return Plugin_Handled;
    }
    _client_wants_latch_to_fastest[client] = true;
    return Plugin_Handled;
}

// Get the next (or previous, if iterate_backwards) valid alive player client index.
// Returns the inputted client index if no other valid candidates were found.
int GetNextClient(int client, bool iterate_backwards = false)
{
    int target_client = client;
    int add_num = iterate_backwards ? -1 : 1;

    if (client > 0 && client <= MaxClients && IsClientInGame(client)) {
        for (int iter_client = mod((target_client + add_num), MaxClients);
            iter_client != client;
            iter_client = mod((iter_client + add_num), MaxClients))
        {
            if (iter_client == 0 || !IsClientInGame(iter_client) ||
                GetClientTeam(iter_client) <= TEAM_SPECTATOR || !IsPlayerAlive(iter_client))
            {
                continue;
            }
            target_client = iter_client;
            break;
        }
    }
    return target_client;
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

    float target_pos[3];
    float final_ang[3];

    // If player is doing a manual mouse2 spectator change ("spec_prev").
    // Spectator won't emit IN_ATTACK bits for "spec_next",
    // so using a command listener for that instead of also capturing it here.
    if (buttons & IN_AIM) {
        _is_following_grenade[client] = false;

        if (_prev_consumed_buttons[client] & IN_AIM) {
            return Plugin_Continue;
        }

        int next_spec_client = GetNextClient(GetEntPropEnt(client, Prop_Send, "m_hObserverTarget"), true);
        if (next_spec_client != -1) {
            SetClientSpectateTarget(client, next_spec_client);
            // Consume the button(s) so they don't trigger further spectator target switches
            buttons &= ~IN_AIM;
            _prev_consumed_buttons[client] |= IN_AIM;
        }
        return Plugin_Continue;
    }
    else {
        _prev_consumed_buttons[client] = 0;
    }

    float start_pos[3];

    // We should be doing a fancy camera pan of the new ghost spawn location
    if (_client_wants_autospec_ghost_spawn[client] && _is_currently_displaying_ghost_location) {
        if (buttons != 0 || mouse[0] != 0 || mouse[1] != 0) {
            _client_wants_autospec_ghost_spawn[client] = false;
            return Plugin_Continue;
        }

        int ghost = EntRefToEntIndex(_last_ghost);
        if (ghost == INVALID_ENT_REFERENCE) {
            return Plugin_Continue;
        }

        if (VectorsEqual(_ghost_display_location, NULL_VECTOR)) {
            GetEntPropVector(_last_ghost, Prop_Send, "m_vecOrigin", _ghost_display_location);
            _ghost_display_location[0] += GetRandomFloat(-128.0, 128.0);
            _ghost_display_location[1] += GetRandomFloat(-128.0, 128.0);
            _ghost_display_location[2] += 64.0;
#if defined DEBUG
            if (VectorsEqual(_ghost_display_location, NULL_VECTOR)) {
                PrintToServer("!! VectorsEqual: _ghost_display_location, NULL_VECTOR");
                return Plugin_Continue;
            }
#endif
        }

        // Make sure we're free flying for the smooth transition
        if (GetEntProp(client, Prop_Send, "m_iObserverMode") != OBS_MODE_FREEFLY) {
            SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FREEFLY);
        }

        float start_ang[3];
        float target_dir[3];
        float target_ang[3];
        float actual_ghost_pos[3];

        GetEntPropVector(_last_ghost, Prop_Send, "m_vecOrigin", actual_ghost_pos);
        GetClientEyePosition(client, start_pos);
        SubtractVectors(actual_ghost_pos, start_pos, target_dir);
        NormalizeVector(target_dir, target_dir);
        GetVectorAngles(target_dir, target_ang);
        GetClientEyeAngles(client, start_ang);
        LerpAngles(start_ang, target_ang, final_ang);

        TeleportEntity(client, _ghost_display_location, final_ang, NULL_VECTOR);

        return Plugin_Continue;
    }

    if (_client_wants_latch_to_closest[client] || _client_wants_latch_to_fastest[client]) {
        int obsmode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        int current_spectated_target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

        int best_client = -1;
        float best_client_value;

        if (_client_wants_latch_to_closest[client]) {
            GetClientEyePosition(client, start_pos);

            for (int i = 1; i <= MaxClients; ++i) {
                if (!IsClientInGame(i) || i == client) {
                    continue;
                }
                // Only ignore current target if already in OBS_MODE_FOLLOW.
                if (obsmode == OBS_MODE_FOLLOW && i == current_spectated_target) {
                    continue;
                }
                if (!IsPlayerAlive(i) || GetClientTeam(i) <= TEAM_SPECTATOR) {
                    continue;
                }

                GetClientEyePosition(i, target_pos);

                float distance = GetVectorDistance(start_pos, target_pos, true);
                if (best_client == -1 || distance < best_client_value) {
                    best_client = i;
                    best_client_value = distance;
                }
            }
        }
        else { // _client_wants_latch_to_fastest[client]
            float velocity[3];

            for (int i = 1; i <= MaxClients; ++i) {
                if (!IsClientInGame(i) || i == client) {
                    continue;
                }
                // Only ignore current target if already in OBS_MODE_FOLLOW.
                if (obsmode == OBS_MODE_FOLLOW && i == current_spectated_target) {
                    continue;
                }
                if (!IsPlayerAlive(i) || GetClientTeam(i) <= TEAM_SPECTATOR) {
                    continue;
                }

                velocity[0] = GetEntPropFloat(i, Prop_Send, "m_vecVelocity[0]");
                velocity[1] = GetEntPropFloat(i, Prop_Send, "m_vecVelocity[1]");
                velocity[2] = GetEntPropFloat(i, Prop_Send, "m_vecVelocity[2]");

                float vel_length = GetVectorLength(velocity, true);
                if (best_client == -1 || vel_length > best_client_value) {
                    best_client = i;
                    best_client_value = vel_length;
                }
            }
        }

        if (best_client == -1) {
            best_client = (current_spectated_target == -1 ? GetNextClient(current_spectated_target) : current_spectated_target);
        }

        if (obsmode != OBS_MODE_FOLLOW) {
            SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FOLLOW);
        }
        SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", best_client);

        _spec_userid_target[client] = 0;
        _client_wants_latch_to_closest[client] = false;
        _client_wants_latch_to_fastest[client] = false;

        // Only auto rotate if user wants it (and there also actually was a new target client whose angles to rotate into)
        if (_client_wants_auto_rotate[client] && best_client != current_spectated_target) {
            GetClientAbsAngles(best_client, final_ang);
            TeleportEntity(client, NULL_VECTOR, final_ang, NULL_VECTOR);
        }

        return Plugin_Continue;
    }

    if (_is_following_grenade[client]) {
        if (buttons != 0) {
            _is_following_grenade[client] = false;
            return Plugin_Continue;
        }

        if (_follow_explosive[client] == 0) {
            if (_last_live_grenade == 0 || !IsValidEntity(_last_live_grenade)) {
                _is_following_grenade[client] = false;
                return Plugin_Continue;
            }
            // Have to check because we aren't using an ent ref
            if (!HasEntProp(_last_live_grenade, Prop_Send, "m_vecOrigin")) {
                _last_live_grenade = 0;
                _is_following_grenade[client] = false;
                return Plugin_Continue;
            }
            _follow_explosive[client] = _last_live_grenade;
            GetEntPropVector(_last_live_grenade, Prop_Send, "m_vecOrigin", target_pos);

            if (VectorsEqual(target_pos, NULL_VECTOR)) {
                _last_live_grenade = 0;
                _is_following_grenade[client] = false;
                return Plugin_Continue;
            }

            GetClientEyePosition(client, start_pos);
            float sqdist = GetVectorDistance(start_pos, target_pos, true);
            // If the nade is too far, snap us closer to it for a smoother spec experience
            if (sqdist > Pow(512.0, 2.0)) {
                TeleportEntity(client, target_pos, NULL_VECTOR, NULL_VECTOR);
            }
        }

        if (_follow_explosive[client] == 0 || !IsValidEntity(_follow_explosive[client])) {
            _is_following_grenade[client] = false;
            return Plugin_Continue;
        }

        // Have to check because we aren't using an ent ref
        if (!HasEntProp(_follow_explosive[client], Prop_Send, "m_vecOrigin")) {
            _last_live_grenade = 0;
            _is_following_grenade[client] = false;
            return Plugin_Continue;
        }
        GetEntPropVector(_follow_explosive[client], Prop_Send, "m_vecOrigin", target_pos);

        if (GetEntProp(client, Prop_Send, "m_iObserverMode") != OBS_MODE_FREEFLY) {
            SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FREEFLY);
        }

        if (VectorsEqual(target_pos, NULL_VECTOR)) {
            _is_following_grenade[client] = false;
            return Plugin_Continue;
        }

        float final_pos[3];
        float start_ang[3];
        float target_dir[3];
        float target_ang[3];

        GetClientEyePosition(client, start_pos);
        VectorLerp(start_pos, target_pos, final_pos, GetGameFrameTime());

        GetClientEyeAngles(client, start_ang);
        SubtractVectors(target_pos, start_pos, target_dir);
        NormalizeVector(target_dir, target_dir);
        GetVectorAngles(target_dir, target_ang);
        LerpAngles(start_ang, target_ang, final_ang);

        if (GetVectorDistance(final_pos, target_pos, true) > Pow(FREEFLY_CAMERA_DISTANCE_FROM_TARGET + 0.1, 2.0)) {
            TeleportEntity(client, final_pos, final_ang, NULL_VECTOR);
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
        float final_pos[3];

        float start_ang[3];
        float target_dir[3];
        float target_ang[3];

        GetClientEyePosition(client, start_pos);
        GetClientEyePosition(target_client, target_pos);
        VectorLerp(start_pos, target_pos, final_pos);

        GetClientEyeAngles(client, start_ang);
        SubtractVectors(target_pos, start_pos, target_dir);
        NormalizeVector(target_dir, target_dir);
        GetVectorAngles(target_dir, target_ang);
        LerpAngles(start_ang, target_ang, final_ang);

        // Observer follow mode distance from spectated player is 100 units (expressed as squared here)
        bool reached_target_distance =
            (GetVectorDistance(start_pos, target_pos, true) <=
            (FREEFLY_CAMERA_DISTANCE_FROM_TARGET * FREEFLY_CAMERA_DISTANCE_FROM_TARGET));

        TeleportEntity(client, final_pos,
            (reached_target_distance && _client_wants_auto_rotate[client])
            ? NULL_VECTOR : final_ang, NULL_VECTOR);

        if (!reached_target_distance) {
            // Make sure we're free flying for the smooth transition
            if (GetEntProp(client, Prop_Send, "m_iObserverMode") != OBS_MODE_FREEFLY) {
                SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FREEFLY);
            }
        }
        else {
#if defined DEBUG
            PrintToChat(client, "Reached target (obsmode: %d, handle: %d)",
                GetEntProp(client, Prop_Send, "m_iObserverMode"),
                GetEntPropEnt(client, Prop_Send, "m_hObserverTarget"));
#endif

            // Reached target, start following the spectated player
            SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FOLLOW);
            SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target_client);
            _spec_userid_target[client] = 0;

            if (_client_wants_auto_rotate[client]) {
                GetClientAbsAngles(target_client, final_ang);
                TeleportEntity(client, NULL_VECTOR, final_ang, NULL_VECTOR);
            }
        }
    }
    else {
        SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_FOLLOW);
        SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target_client);
        _spec_userid_target[client] = 0;

        if (_client_wants_auto_rotate[client]) {
            GetClientAbsAngles(target_client, final_ang);
            TeleportEntity(client, NULL_VECTOR, final_ang, NULL_VECTOR);
        }
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

stock any Clamp(any value, any min, any max)
{
    return value < min ? min : value > max ? max : value;
}

stock float Lerp(float a, float b, float scale = 0.0)
{
    if (scale == 0) {
        scale = GetGameFrameTime() * g_hCvar_LerpSpeed.FloatValue;
    }
#if(0)
    scale = Clamp(scale, -1.0, 1.0);
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
stock float LerpAngle(const float a, const float b, const float t = 0.0)
{
    float dt = Clamp((b - a) - RoundToFloor((b - a) / 360.0) * 360.0, 0.0, 360.0);
    return Lerp(a, a + (dt > 180 ? dt - 360 : dt), t);
}

// Needed for a "negative mod" that cycles back to positive range.
int mod(int a, int b)
{
    int r = a % b;
    return r < 0 ? r + (b < 0 ? -b : b) : r;
}

void GetFreeflyCameraPosBehindPlayer_Vec(const float camera_ang[3], float[3] out_camera_pos)
{
    float sp, sy, sr, cp, cy, cr;
    GetSinCos(camera_ang[0], sp, cp);
    GetSinCos(camera_ang[1], sy, cy);
    GetSinCos(camera_ang[2], sr, cr);

    float crcy = cr * cy;
    float crsy = cr * sy;
    float srcy = sr * cy;
    float srsy = sr * sy;

    float matrix[3][3];
    matrix[0][0] = cp * cy;
    matrix[1][0] = cp * sy;
    matrix[2][0] = -sp;

    matrix[0][1] = sp * srcy - crsy;
    matrix[1][1] = sp * srsy + crcy;
    matrix[2][1] = sr * cp;

    matrix[0][2] = sp * crcy + srsy;
    matrix[1][2] = sp * crsy - srcy;
    matrix[2][2] = cr * cp;

    float offset[3];
    // Move slightly further than FREEFLY_CAMERA_DISTANCE_FROM_TARGET for smoother camera transitions.
    offset[0] = -FREEFLY_CAMERA_DISTANCE_FROM_TARGET - 0.1;

    out_camera_pos[0] += GetVectorDotProduct(offset, matrix[0]);
    out_camera_pos[1] += GetVectorDotProduct(offset, matrix[1]);
    out_camera_pos[2] += GetVectorDotProduct(offset, matrix[2]);
}

void GetFreeflyCameraPosBehindPlayer(int client, const float camera_ang[3], float[3] out_camera_pos)
{
    if (!IsClientInGame(client)) {
        ThrowError("Client is not in game");
    }

    GetClientEyePosition(client, out_camera_pos);
    GetFreeflyCameraPosBehindPlayer_Vec(camera_ang, out_camera_pos);
}

stock void GetSinCos(const float degrees, float& sine, float& cosine)
{
    float radians = DegToRad(degrees);
    sine = Sine(radians);
    cosine = Cosine(radians);
}
