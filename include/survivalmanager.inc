#if defined _survivalmanager_included
 #endinput
#endif
#define _survivalmanager_included

// Where the CDirectorSurvivalMode is stored at in CDirector or TheDirector
#define CDirectorSurvivalModeOffset 0x640

//#define CDirectorChallengeModeOffset 0x638

/*
	CDirector
		CDirectorSurvivalMode
		CDirectorChallengeMode // mutations
		CDirectorVersusMode
		CDirectorScavengeMode
*/

/*
 * Offsets of CDirectorSurvivalMode responsible for changing survival properties
 * Modifications last for a round- and reset on the new round initiated
 * Note: Some could be wrong and representing a different function or property
*/
enum SurvivalOffsets
{
	TANK_LIMIT = 0x6C, 						// int
	TANK_WAVE_TIMER = 0x78, 				// float, spawn interval for the tank waves. Starts from 80. -20s is subracted between some waves and minimum guessing becomes 30-40s or something.
	MAX_TANK_STAGE = 0x88, 					/* int - Current director's stage for tank spawning, scales the difficulty. Stages are 1 and 2. */ 
	MAX_TANK_SPAWN = 0x90, 					// int, Max tanks allowed to spawn
	SURVIVAL_TANK_RESPAWN_TIME = 0x50, 		// float, Time before a tank can respawn
	SURVIVAL_TANK_SPAWN_COUNT = 0x94,  		// int - How many tanks have spawned in total in the current wave
	SURVIVAL_STAGE = 0x98, 					// int, Stage of survival, incremented when tanks are spawned and killed per wave. 1min = stage 1, 2min = stage2 etc
	SURVIVAL_SPAWN_MODIFIER = 0x74, 		// float
	SURVIVAL_SPAWN_THROTTLE = 0x7C, 		// float, throttling for SI/Horde interval, probably horde
	SURVIVAL_DIFFICULTY_STAGE = 0x60, 		// int, Current difficulty stage (increases over time), 1-5 values i believe.
	SURVIVAL_SPAWN_TIMER = 0x38,     		// float, General spawn timer (maybe for SI?)
	SURVIVAL_NEXT_STAGE_TIME = 0x58, 		// float, Time until the next difficulty increase, always reads 0, could be something else.
	SURVIVAL_COMMON_LIMIT = 0x64,    		// int, Max number of common infected
	SURVIVAL_COMMON_SPAWN_COUNT = 0x68,		// int, Current count of common infected
	SURVIVAL_NEXT_TANK_WAVE_TIME = 0x80, 	// float, When the next tank wave is expected. 
	SURVIVAL_NEXT_SI_WAVE_TIME = 0x84,   	// float, When the next SI wave is expected. Seems to return 0.0 always, could be UpdateSurvival func
	SURVIVAL_DIRECTOR_TIME = 0xA0,  		// float, Current director's game time
	SURVIVAL_CURRENT_WAVE = 0x20, 			// int, Current wave number
	SURVIVAL_SPAWN_FLOW = 0x24, 			// float, Unknown but affects spawn pacing
	SURVIVAL_SCORE_MULTIPLIER = 0x44, 		// float, Multiplier for score scaling?
	SURVIVAL_MAX_ALLOWED_TANKS = 0x70, 		// int, Hard limit on tanks per wave?
	SURVIVAL_HORDE_STAGE_INTERVAL = 0x0C, 	// Starts at 60 secs. Horde Stage interval, decays by -2 seconds every wave, after 15 minutes its around 10seconds
	SURVIVAL_LULL_DURATION = 0x3C,			// The duration for the lull time (breaks)
	
	SURVIVAL_UNKNOWN_TIMER = 0xC
	
	// Next tank spawn 0x18
	
	
	/*
		Tested and wasnt useful:
		0x10 0x18 0x1C 0x28 0x2C 0x30 0x34 0x40 0x48 0x4C
	*/
}

enum SurvivalMedal
{
	MEDAL_NONE = -1,
	MEDAL_BRONZE = 0,
	MEDAL_SILVER = 1,
	MEDAL_GOLD = 2
}

Address TheDirector, CDirectorSurvivalMode;

// CDirectorSurvivalMode
methodmap SurvivalDirector
{	
	public void Init()
	{
		Handle hGamedata = LoadGameConfigFile("SurvivalRoundManager");
		TheDirector = GameConfGetAddress(hGamedata, "CDirector");
		if(TheDirector == Address_Null) {
			ThrowError("Unable to get CDirector address");
		}
		
		delete hGamedata;
	 
		// Get a Address-class for CDirectorSurvivalMode which is a subclass of CDirector responsible for controlling the majority of survival mode
		CDirectorSurvivalMode = view_as<Address>(LoadFromAddress(TheDirector + view_as<Address>(CDirectorSurvivalModeOffset), NumberType_Int32));
		if (CDirectorSurvivalMode == Address_Null) {
			ThrowError("Unable to get Address for CDirectorSurvivalMode");
		}
		
		/*
		CDirectorChallengeMode = view_as<Address>(LoadFromAddress(TheDirector + view_as<Address>(CDirectorChallengeModeOffset), NumberType_Int32));
		if (CDirectorSurvivalMode == Address_Null) {
			ThrowError("Unable to get Address for CDirectorSurvivalMode");
		}
		*/
	}
	
	public Address GetOffset(SurvivalOffsets offset)
	{
		if (CDirectorSurvivalMode == Address_Null)
		{
			ThrowError("SurvivalDirector address is invalid.");
		}
		return CDirectorSurvivalMode + view_as<Address>(offset);
	}
	
	public SurvivalMedal GetSurvivalTopMedal(int client)
	{
		int resource = L4D_GetResourceEntity();
		if (resource == -1)
			return MEDAL_NONE;
		
		int topmedal = GetEntProp(resource, Prop_Send, "m_nSurvivalTopMedal", _, client);
		if (topmedal < view_as<int>(MEDAL_BRONZE) || topmedal > view_as<int>(MEDAL_GOLD)) {
			return MEDAL_NONE;
		}
		return view_as<SurvivalMedal>(topmedal);
	}
	
	// Methods for reading offsets
	public int GetInt(SurvivalOffsets offset)
	{
		return LoadFromAddress(this.GetOffset(offset), NumberType_Int32);
	}
	public void SetInt(SurvivalOffsets offset, int value)
	{
		StoreToAddress(this.GetOffset(offset), value, NumberType_Int32);
	}
	public float GetFloat(SurvivalOffsets offset)
	{
		return view_as<float>(LoadFromAddress(this.GetOffset(offset), NumberType_Int32));
	}
	public void SetFloat(SurvivalOffsets offset, float value)
	{
		StoreToAddress(this.GetOffset(offset), view_as<int>(value), NumberType_Int32);
	}
}

/*@dustins
 * Gets the resource entity or -1 on failure.
*/
int L4D_GetResourceEntity()
{
	return FindEntityByClassname(-1, "terror_player_manager");
}

/*@dustin's
 * Gets a player's survival record time
 * @param client index
 * @return record time int, or -1 on failure.
*/
stock int GetSurvivalRecordTime(int client)
{
	int terror_player_manager = L4D_GetResourceEntity();
	if (terror_player_manager != -1 && HasEntProp(terror_player_manager, Prop_Send, "m_flSurvivalRecordTime"))
	{
		float fSeconds = GetEntPropFloat(terror_player_manager, Prop_Send, "m_flSurvivalRecordTime", client);
		return RoundToFloor(fSeconds / 60);
	}
	return -1;
}

/*
 * Was the client present at survival start?
 * @param client index
 * @return true if present from survival start, false if not
*/
stock bool WasPresentAtSurvivalStart(int client)
{
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_bWasPresentAtSurvivalStart", 4));
}

/*
 * Toggles the present prop on the client
 * @param client index
 * @param bPresent - set to false to disable record from saving, set to true to enable saving
*/
stock void ToggleSurvivalPresense(int client, bool bPresent=true)
{
	SetEntProp(client, Prop_Send, "m_bWasPresentAtSurvivalStart", bPresent);
} 

/*
 * Sets a desired timescale. Note: Must be called again to reset it since the entity is deleted after its used and no longer referrable.
 * @param, char[] scale - Scale val, use floats etc: 1.0-20.0
*/
stock void SetTimeScale(const char[] scale)
{
	int eTime = CreateEntityByName("func_timescale");
	if (eTime != -1)
	{
		DispatchKeyValue(eTime, "desiredTimescale", scale);
		DispatchSpawn(eTime);
		AcceptEntityInput(eTime, "Start");
		AcceptEntityInput(eTime, "Kill");	
	}
}