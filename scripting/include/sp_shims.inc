#if defined(_SP_SHIMS_INC_)
#endinput
#endif
#define _SP_SHIMS_INC_

#define SP_SHIMS_VERSION "0.1"

// Compatibility shims for SM backwards compatibility.

#if SOURCEMOD_V_MAJOR <= 1 && SOURCEMOD_V_MINOR <= 8
/**
 * Check if the given vector is equal to the NULL_VECTOR.
 *
 * @param v       The vector to test.
 * @return        True if equal to NULL_VECTOR, false otherwise.
 */
stock bool IsNullVector(const float v[3])
{
    return v[0] == 0.0 && v[1] == 0.0 && v[2] == 0.0;
}
#endif

#if SOURCEMOD_V_MAJOR <= 1 && SOURCEMOD_V_MINOR <= 8
#if !defined(SHIM_EXCLUDE_ONGAMEFRAME)
static float _last_time_OnGameFrame;
static float _delta_time_OnGameFrame;
static Handle _fwd_OnGameFrame = INVALID_HANDLE;
public void OnGameFrame()
{
    float time = GetGameTime();
    _delta_time_OnGameFrame = time - _last_time_OnGameFrame;
    _last_time_OnGameFrame = time;

    if (_fwd_OnGameFrame == INVALID_HANDLE)
    {
        _fwd_OnGameFrame = CreateGlobalForward("SHIM_OnGameFrame", ET_Ignore);
    }
    Call_StartForward(_fwd_OnGameFrame);
    Call_Finish();
}

/**
 * Returns the time the Game took processing the last frame.
 *
 * @return              Game frame time.
 */
stock float GetGameFrameTime()
{
    return _delta_time_OnGameFrame;
}
#endif
#endif
