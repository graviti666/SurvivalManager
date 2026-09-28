#include <sourcemod>
#include <sdktools>
#include <survivalmanager>
#include <adminmenu>

#pragma newdecls required
#pragma semicolon	1

// Custom presets
bool g_bThirteenMinuteSurvival, g_bOnlyDoubles, g_bOnlyTrio, g_bTankRush, g_bHardSurvival;

bool g_bInTestMode;

Handle g_hNoLullTimer;

SurvivalDirector g_SurvivalDirector;

#define DIRECTORSCRIPT_TYPE1	"DirectorScript.MapScript.LocalScript.DirectorOptions"

// modules
#include "modules/commands.sp"

public Plugin myinfo =
{
	name = "Survival Manager",
	author = "Gravity",
	description = "Exposes some functions of the survival director and other survival related stuff into a neat menu",
	version = "1.0",
	url = ""
};

public void OnPluginStart()
{
	g_SurvivalDirector.Init();

	//RegServerCmd("sm_timetest", Cmd_TimeTest);
	
	RegAdminCmd("sm_offset", Cmd_TestOffset, ADMFLAG_ROOT, "Test a CDirectorSurvivalMode offset");

	RegAdminCmd("sm_test", Cmd_TestRec, ADMFLAG_ROOT);
	//RegAdminCmd("sm_breaktime", Cmd_BreakTest, ADMFLAG_ROOT);
	RegAdminCmd("sm_endtime", Cmd_SetEndTime, ADMFLAG_ROOT);
	
	RegAdminCmd("sm_settime", Command_SetSurvivalTime, ADMFLAG_ROOT, "Sets the survival time clock");
	RegAdminCmd("sm_timescale", Command_TimeScale, ADMFLAG_ROOT, "Sets a desired timescale");
	RegAdminCmd("sm_skiptime", Command_SkipTime, ADMFLAG_ROOT, "Raises the timescale and teleports all players to 0.0.");
	RegAdminCmd("sm_backtime", Cmd_SetBackTime, ADMFLAG_ROOT, "Updates the survival timer in reverse counting down.");
	RegAdminCmd("sm_tspawntimer", Cmd_TankSpawnsInfo, ADMFLAG_ROOT, "Toggle tank spawn timer display");
	RegAdminCmd("sm_endsurvival", Cmd_EndSurvivalRound, ADMFLAG_ROOT, "Ends a survival round with the scoreboard appearing");
	RegAdminCmd("sm_fakesurvival", Cmd_FakeSurvivalStart, ADMFLAG_ROOT, "Starts a fake survival round with the timer not running");
	RegAdminCmd("sm_startsurvival", Cmd_StartSurvivalRound, ADMFLAG_ROOT, "Starts the survival round.");
	RegAdminCmd("sm_introstate", Cmd_introState, ADMFLAG_ROOT);
	RegAdminCmd("sm_hardsurvival", Cmd_ToggleHardSurvival, ADMFLAG_ROOT, "Toggles no-lull, fast-SI survival mode");
	
	HookEvent("survival_round_start", Event_SurvivalStart);
	HookEvent("round_end", Event_RoundEnd);

	HookEvent("tank_spawn", Event_TankSpawned);

	LoadTranslations("common.phrases");
	TopMenu SurvivalTopMenu = GetAdminTopMenu();
	if (LibraryExists("adminmenu") && (SurvivalTopMenu != null))
		OnAdminMenuReady(SurvivalTopMenu);
}

stock float SM_LoadFloat(Address addr)
{
	int bits = LoadFromAddress(addr, NumberType_Int32);
	return view_as<float>(bits);
}

stock void SM_StoreFloat(Address addr, float value)
{
	int bits = view_as<int>(value);
	StoreToAddress(addr, bits, NumberType_Int32);
}

/**
 * Rewinds CDirectorSurvivalMode's 6 CountdownTimer targets by `seconds`,
 * making Director pacing (hordes/tanks/lull/limit-ramp) think that much
 * time has already elapsed since round start.
 */
stock void SurvivalMode_RewindDirectorTimers(Address pDirectorSurvivalMode, float seconds)
{
	if (pDirectorSurvivalMode == Address_Null)
	{
		LogError("[Survival] RewindDirectorTimers: bad address");
		return;
	}

	static const int timestampOffsets[] = { 0x10, 0x1C, 0x28, 0x34, 0x40, 0x4C };

	for (int i = 0; i < sizeof(timestampOffsets); i++)
	{
		Address field = pDirectorSurvivalMode + view_as<Address>(timestampOffsets[i]);
		float current = SM_LoadFloat(field);

		// dword_BEAE3C sentinel timers (never Start()'d) will read as a large/garbage
		// value here - skip anything that isn't a plausible in-round timestamp so we
		// don't accidentally "expire" a timer that was never active.
		if (current <= 0.0)
			continue;

		SM_StoreFloat(field, current - seconds);
	}
}

/**
 * Forces the wave counter (+0x84) permanently odd, which skips the lull-start
 * branch in UpdateSurvival entirely. Also collapses the lull-end timer (+0x40)
 * if a lull is already active.
 */
stock void SurvivalMode_DisableLulls(Address pDirectorSurvivalMode)
{
	if (pDirectorSurvivalMode == Address_Null)
		return;

	Address lullEndAddr = pDirectorSurvivalMode + view_as<Address>(0x40);
	float lullEnd = SM_LoadFloat(lullEndAddr);

	if (lullEnd != -1.0)
		SM_StoreFloat(lullEndAddr, -1.0);
}

/**
 * Sets the Special Infected spawn interval (+0x7C, confirmed via
 * "[SURVIVAL]: Special Spawn Interval: %f" debug string).
 */
stock void SurvivalMode_SetSIInterval(Address pDirectorSurvivalMode, float interval)
{
	if (pDirectorSurvivalMode == Address_Null)
		return;

	SM_StoreFloat(pDirectorSurvivalMode + view_as<Address>(0x7C), interval);
}

public void Event_TankSpawned(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || !IsFakeClient(client) || !g_bInTestMode)
		return;
	
	float fNow = GetGameTime() - GameRules_GetPropFloat("m_flRoundStartTime");
	float fNextTank = g_SurvivalDirector.GetFloat(TANK_WAVE_TIMER);
	
	float fNewTankTime = fNow + fNextTank;
	int min = RoundToNearest(fNewTankTime) / 60;
	int sec = RoundToNearest(fNewTankTime) % 60;
	
	PrintToChatAll("\x01[Survival] \x03%N\x01 spawned. Next in \x04%.2f\x01 seconds. at approx \x04%i:%02d", client, g_SurvivalDirector.GetFloat(TANK_WAVE_TIMER), min, sec);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bThirteenMinuteSurvival)
	{
		g_bThirteenMinuteSurvival = false;
	}

	if (g_bHardSurvival)
	{
		// Toggle khans SI spawner plugin
		//SetConVarInt(FindConVar("is_enabled"), 0);
		//SetConVarInt(FindConVar("is_thirteen_min_spawns"), 0);
		
		ServerCommand("sm plugins unload hardest.smx");
		
		g_bHardSurvival = false;
		delete g_hNoLullTimer;
	}
}

public void Event_SurvivalStart(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bHardSurvival)
	{
		PrintToChatAll("[Survival] Starting a Hard Survival round.");
		
		SurvivalMode_DisableLulls(CDirectorSurvivalMode);
		//SurvivalMode_SetSIInterval(CDirectorSurvivalMode, 1.0); // tune to taste

		g_SurvivalDirector.SetInt(SURVIVAL_STAGE, 20);
		g_SurvivalDirector.SetInt(SURVIVAL_DIFFICULTY_STAGE, 3);
	
		// Rewind the Director's own scheduling clocks by 20minutes 1200.0 seconds
		SurvivalMode_RewindDirectorTimers(CDirectorSurvivalMode, 1200.0);

		// Toggle khans SI spawner plugin
		//SetConVarInt(FindConVar("is_enabled"), 1);
		//SetConVarInt(FindConVar("is_thirteen_min_spawns"), 1);
		
		delete g_hNoLullTimer;
		//g_hNoLullTimer = CreateTimer(1.0, Timer_KeepLullsDisabled, _, TIMER_REPEAT);
		
		ServerCommand("sm plugins load disabled/hardest.smx");
	}
	
	if (g_bThirteenMinuteSurvival)
	{
		//g_bThirteenMinuteSurvival = false;
		PrintToChatAll("[Survival] Starting a 13minutes from round-start game.");

		g_SurvivalDirector.SetInt(SURVIVAL_STAGE, 13);
		g_SurvivalDirector.SetInt(SURVIVAL_DIFFICULTY_STAGE, 3);
	
		// Rewind the Director's own scheduling clocks by 780s (13 min)
		SurvivalMode_RewindDirectorTimers(CDirectorSurvivalMode, 780.0);

		// Also rewind the actual GameRules round-start time so the HUD clock
		// and CTerrorPlayer::UpdateSurvivalRecordTime agree it's been 13 minutes
		//float startTime = GameRules_GetPropFloat("m_flRoundStartTime");
		//GameRules_SetPropFloat("m_flRoundStartTime", startTime - 780.0);
		
		// Toggle khans SI spawner plugin
		//SetConVarInt(FindConVar("is_enabled"), 1);
		//SetConVarInt(FindConVar("is_thirteen_min_spawns"), 1);
	}
	
	if (g_bOnlyDoubles)
	{
		g_bOnlyDoubles = false; // Just unload these after starting
		PrintToChatAll("[Survival] Starting a Only Double Tank Spawns round.");
		
		g_SurvivalDirector.SetInt(MAX_TANK_STAGE, 2);
		g_SurvivalDirector.SetInt(MAX_TANK_SPAWN, 2);
		g_SurvivalDirector.SetInt(TANK_LIMIT, 2);
		g_SurvivalDirector.SetFloat(TANK_WAVE_TIMER, 30.0); // Gets overriden by something doesn't set properly.
		g_SurvivalDirector.SetInt(SURVIVAL_DIFFICULTY_STAGE, 5);
	}
	
	if (g_bOnlyTrio)
	{
		g_bOnlyTrio = false; // Just unload these after starting
		PrintToChatAll("[Survival] Starting a Trio tank round.");
		
		g_SurvivalDirector.SetInt(MAX_TANK_STAGE, 2);
		g_SurvivalDirector.SetInt(MAX_TANK_SPAWN, 3);
		g_SurvivalDirector.SetInt(TANK_LIMIT, 4);
		g_SurvivalDirector.SetFloat(TANK_WAVE_TIMER, 30.0); // Gets overriden by something doesn't set properly.
		g_SurvivalDirector.SetInt(SURVIVAL_DIFFICULTY_STAGE, 5);
	}
	
	// Sucks, would need handling of extra SI since tanks fill up the spawning que so SI barely spawn
	if (g_bTankRush)
	{
		g_bTankRush = false; // Just unload these after starting
		PrintToChatAll("[Survival] Starting a Tank Rush round.");
		
		g_SurvivalDirector.SetInt(MAX_TANK_STAGE, 10);
		g_SurvivalDirector.SetInt(MAX_TANK_SPAWN, 10);
		g_SurvivalDirector.SetInt(TANK_LIMIT, 10);
		g_SurvivalDirector.SetFloat(TANK_WAVE_TIMER, 5.0);
		g_SurvivalDirector.SetInt(SURVIVAL_DIFFICULTY_STAGE, 5);
	}
}

public Action Timer_KeepLullsDisabled(Handle timer)
{
	if (CDirectorSurvivalMode == Address_Null || !g_bHardSurvival)
		return Plugin_Continue;

	//SetDirectorValues();
	SurvivalMode_DisableLulls(CDirectorSurvivalMode);
	//SurvivalMode_SetSIInterval(CDirectorSurvivalMode, 1.0); // tune to taste¨
	
	return Plugin_Continue;
}

public Action Cmd_ToggleHardSurvival(int client, int args)
{
	g_bHardSurvival = !g_bHardSurvival;
	PrintToChatAll("\x01[Survival] Hard Survival is now \x03%s", g_bHardSurvival ? "enabled" : "disabled");
	return Plugin_Handled;
}

public void OnAdminMenuReady(Handle topmenu)
{
	if (topmenu == null) 
	{
		LogError("Unable to add commands to admin menu. invalid handle.");
		return;
	}
	
	// Admin menu category
	TopMenuObject SurvivalManagerOpt = AddToTopMenu(topmenu, "sm_survival_manager_cat", TopMenuObject_Category, Category_Handler, INVALID_TOPMENUOBJECT);
	
	// Commands
	AddToTopMenu(topmenu, "sm_survivalmanager_info", TopMenuObject_Item, AdminMenu_SurvivalInfo, SurvivalManagerOpt, "sm_survivalmanager_info", ADMFLAG_ROOT); // Info
}

public void Category_Handler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		Format(buffer, maxlength, "Survival Manager");
	}
	else if(action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Survival Manager");
	}
}

public void AdminMenu_SurvivalInfo(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Info");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		MakeInfoMenu(param);
	}
}

void MakeInfoMenu(int client)
{
	if (!client)
		return;
	
	Menu menu = new Menu(Menu_InfoCallback);
	menu.SetTitle("Info:\n");
	menu.AddItem("records", "Player Records");
	menu.AddItem("director_vars", "Survival Status");
	menu.AddItem("survpresets", "Survival Presets");
	menu.AddItem("presense", "Survivor Presense (Record Saving)");
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitBackButton = false;
}

public int Menu_InfoCallback(Handle menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char select[128];
			GetMenuItem(menu, param2, select, sizeof(select));
			
			if (StrEqual(select, "records"))
			{
				MakeRecordsMenu(param1);
			}
			else if (StrEqual(select, "director_vars"))
			{
				MakeDirectorStatsMenu(param1);
			}
			else if (StrEqual(select, "presense"))
			{
				MakeRecordOptionsMenu(param1);
			}
			else if (StrEqual(select, "survpresets"))
			{
				MakePresetsMenu(param1);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void MakePresetsMenu(int client)
{
	if (!client)
		return;
		
	Menu menu = new Menu(Menu_PresetsSurvival);
	menu.SetTitle("Survival Preset Configs:\n");
	menu.AddItem("doubles", "Always Double Tanks");
	menu.AddItem("onlytrio", "Always Trio Tanks");
	menu.AddItem("13minute", "Thirteen Minute Survival From Round-Start");
	menu.AddItem("tankrush", "Tank Rush Hardcore");
	menu.AddItem("hardsurv", "No Breaks & Fast SI Spawns");
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitBackButton = false;
}

void MakeRecordOptionsMenu(int client)
{
	if (!client)
		return;
		
	Menu menu = new Menu(Menu_PresenceTracking);
	menu.SetTitle("Record Tracking Status:\n");
	
	char present[128];
	char sID[42];
	int id;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		
		id = GetClientUserId(i);
		IntToString(id, sID, sizeof(sID));
		
		Format(present, sizeof(present), "%N - %s", i, WasPresentAtSurvivalStart(i) ? "Record will save (1)" : "Record won't save (0)");
		menu.AddItem(sID, present);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitBackButton = false;
}

void MakeDirectorStatsMenu(int client)
{
	if (!client)
		return;
		
	Menu menu = new Menu(Menu_DirectorStatsCallback);
	menu.SetTitle("Round Status:\n");
	
	if (CDirectorSurvivalMode == Address_Null)
		menu.AddItem("fail", "Failed to retrieve survival stats. Bad address.");
	
	menu.AddItem("refresh", "(Refresh)");
	
	char stage[32];
	FormatEx(stage, sizeof(stage), "Survival Stage: %i", g_SurvivalDirector.GetInt(SURVIVAL_STAGE));
	menu.AddItem("stage", stage);
	
	char sdiffstage[32];
	FormatEx(sdiffstage, sizeof(sdiffstage), "Difficulty Stage: %i", g_SurvivalDirector.GetInt(SURVIVAL_DIFFICULTY_STAGE));
	menu.AddItem("diffstage", sdiffstage);
	
	float fNextDifficulty = g_SurvivalDirector.GetFloat(SURVIVAL_NEXT_STAGE_TIME);
	char sNextDifftime[32];
	FormatEx(sNextDifftime, sizeof(sNextDifftime), "Next Difficulty Time: %.1f", fNextDifficulty);
	menu.AddItem("nextdifftime", sNextDifftime);
	
	char stanklimit[32];
	FormatEx(stanklimit, sizeof(stanklimit), "Tank Limit: %i", g_SurvivalDirector.GetInt(TANK_LIMIT));
	menu.AddItem("tanklimit", stanklimit);
	
	char stankstage[32];
	FormatEx(stankstage, sizeof(stankstage), "Tank Stage Limit: %i", g_SurvivalDirector.GetInt(MAX_TANK_STAGE));
	menu.AddItem("tankstage", stankstage);
	
	char stankwavetime[32];
	FormatEx(stankwavetime, sizeof(stankwavetime), "Tank Wave Time: %.1f", g_SurvivalDirector.GetFloat(TANK_WAVE_TIMER));
	menu.AddItem("tankwave", stankwavetime);
	
	char sNextTankWave[32];
	FormatEx(sNextTankWave, sizeof(sNextTankWave), "Next Tank Wave: %.1f", g_SurvivalDirector.GetFloat(SURVIVAL_NEXT_TANK_WAVE_TIME));
	menu.AddItem("nexttankwave", sNextTankWave);
	
	char sNextSIWave[32];
	FormatEx(sNextSIWave, sizeof(sNextSIWave), "Next SI Wave: %.1f", g_SurvivalDirector.GetFloat(SURVIVAL_NEXT_SI_WAVE_TIME));
	menu.AddItem("nexttankwave", sNextSIWave);
	
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitBackButton = false;
}

void MakeRecordsMenu(int client)
{
	if (!client)
		return;
	
	Menu menu = new Menu(Menu_RecordsCallback);
	menu.SetTitle("Records:\n(Click for Info)");
	
	char sRecord[128], sID[16];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
	
		int userid = GetClientUserId(i);
		IntToString(userid, sID, sizeof(sID));

		Format(sRecord, sizeof(sRecord), "%N - %i Minutes", i, GetSurvivalRecordTime(i));
		
		menu.AddItem(sID, sRecord);
	}
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitBackButton = false;
}

public int Menu_PresetsSurvival(Handle menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char select[128];
			GetMenuItem(menu, param2, select, sizeof(select));
			
			if (StrEqual(select, "doubles"))
			{
				g_bOnlyDoubles = !g_bOnlyDoubles;
				PrintToChatAll("\x01[Survival] Double Tanks only is now \x03%s", g_bOnlyDoubles ? "enabled" : "disabled");
			}
			else if (StrEqual(select, "13minute"))
			{
				g_bThirteenMinuteSurvival = !g_bThirteenMinuteSurvival;
				PrintToChatAll("\x01[Survival] Start from 13-minute survival is now \x03%s", g_bThirteenMinuteSurvival ? "enabled" : "disabled");
			}
			else if (StrEqual(select, "tankrush"))
			{
				g_bTankRush = !g_bTankRush;
				PrintToChatAll("\x01[Survival] Tank Rush is now \x03%s", g_bTankRush ? "enabled" : "disabled");
			}
			else if (StrEqual(select, "onlytrio"))
			{
				g_bOnlyTrio = !g_bOnlyTrio;
				PrintToChatAll("\x01[Survival] Trio Tanks only is now \x03%s", g_bOnlyTrio ? "enabled" : "disabled");
			}
			else if (StrEqual(select, "hardsurv"))
			{
				g_bHardSurvival = !g_bHardSurvival;
				PrintToChatAll("\x01[Survival] No Lulls / Fast SI Spawns is now \x03%s", g_bHardSurvival ? "enabled" : "disabled");
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

bool bTog[MAXPLAYERS + 1];
public int Menu_PresenceTracking(Handle menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char select[128];
			GetMenuItem(menu, param2, select, sizeof(select));
			
			int id = StringToInt(select);
			int target = GetClientOfUserId(id);
			
			bTog[target] = !bTog[target];
			ToggleSurvivalPresense(target, bTog[target]);
			
			MakeRecordOptionsMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public int Menu_DirectorStatsCallback(Handle menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char select[128];
			GetMenuItem(menu, param2, select, sizeof(select));
			
			if (StrEqual(select, "refresh"))
			{
				MakeDirectorStatsMenu(param1);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public int Menu_RecordsCallback(Handle menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char select[128];
			GetMenuItem(menu, param2, select, sizeof(select));
			
			int id = StringToInt(select);
			int target = GetClientOfUserId(id);
			
			PrintToChat(param1, "Check console for output.");
			
			InfoAbout(param1, target);
			
			// Re-draw
			MakeInfoMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void InfoAbout(int client, int target)
{
	PrintToConsole(client, "");
	PrintToConsole(client, ">>>>>>>>>>>>>>>>>>>>> WIP <<<<<<<<<<<<<<<<<<<<<<<<<<<<");
	PrintToConsole(client, ">>>>>>>>>>>>>>>>> Info About %N <<<<<<<<<<<<<<<<<<<<<", target);
	PrintToConsole(client, "");
}

stock void SetDirectorValues()
{
	SetDirectorVar("SpecialRespawnInterval", "2.0");
	SetDirectorVar("cm_MaxSpecials", "20");
	SetDirectorVar("cm_DominatorLimit", "20");
	SetDirectorVar("SpecialInitialSpawnDelayMax", "3.0");
	SetDirectorVar("SpecialInitialSpawnDelayMin", "2.0");
	SetDirectorVar("MaxSpecials", "20");
	SetDirectorVar("DominatorLimit", "20");
	//SetDirectorVar("CommonLimit", "0");
	SetDirectorVar("BoomerLimit", "2");
	SetDirectorVar("HunterLimit", "5");
	SetDirectorVar("SmokerLimit", "5");
	SetDirectorVar("ChargerLimit", "4");
	SetDirectorVar("JockeyLimit", "4");
	SetDirectorVar("SpitterLimit", "2");
}

void SetDirectorVar(char[] dvar, char[] dvalue)
{
	L4D2_RunScript("%s.%s <- %s;", DIRECTORSCRIPT_TYPE1, dvar, dvalue);
}

void L4D2_RunScript(const char[] sCode, any ...)
{
	static int iScriptLogic = INVALID_ENT_REFERENCE;
	
	if(!IsValidEnt(EntRefToEntIndex(iScriptLogic))) {
		iScriptLogic = FindEntityByClassname(MaxClients+1, "info_director");	
	}
	
	if(!IsValidEnt(EntRefToEntIndex(iScriptLogic))) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(!IsValidEnt(EntRefToEntIndex(iScriptLogic)))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}

	char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}

bool IsValidEnt(int entity)
{
	return (entity > MaxClients && IsValidEntity(entity) && entity != INVALID_ENT_REFERENCE);
}