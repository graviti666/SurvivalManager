#pragma newdecls required
#pragma semicolon	1

float g_hOldPosition[MAXPLAYERS + 1][3];

bool g_bBackTimeEnabled;
bool bHasUsedSkip;
bool g_timerupdate[MAXPLAYERS + 1];

Handle g_hTimerBackwards;
Handle g_hSetEndTime;
Handle g_hEndSurvivalRound;
Handle g_hStartRoundSurvival;
Handle g_hScoreBoard;

/*
public Action Cmd_BreakTest(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	if (args < 1)
	{
		PrintToChat(client, "Usage: sm_breaktime <value>");
		return Plugin_Handled;
	}
	
	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	float val = StringToFloat(arg);
	
	PrintToChat(client, "\x01[SURVIVAL] Setting lull time to \x03%.2f", val);
	g_SurvivalDirector.SetFloat(SURVIVAL_LULL_DURATION, val);
	return Plugin_Handled;
}
*/

public Action Cmd_introState(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetSignature(SDKLibrary_Server, "@_ZN13CTerrorPlayer23OnEnterIntroCameraStateEv", 1))
		return Plugin_Handled;
	
	//PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	
	g_hScoreBoard = EndPrepSDKCall();
	
	SDKCall(g_hScoreBoard);
	
	PrintToChat(client, "Intro nigga");
	return Plugin_Handled;
}

public Action Cmd_TestOffset(int client, int args)
{
    if (args < 1)
    {
        PrintToChat(client, "Usage: !offset <hex offset>");
        return Plugin_Handled;
    }

    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));

    // Convert hex string to int
    int offset = StringToInt(arg, 16);

    // Try reading as float (useful for many survival vars)
    float value = view_as<float>(LoadFromAddress(CDirectorSurvivalMode+view_as<Address>(offset), NumberType_Int32));

    PrintToChat(client, "[Offset] %s (0x%X) = %f", arg, offset, value);

    return Plugin_Handled;
}

/*
 * sm_endtime - sets a end time record - CTerrorGameRules::SetRoundEndTime(float)
*/
public Action Cmd_SetEndTime(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	if (args < 1) {
		PrintToChat(client, "Usage: sm_endtime <minutes>");
		return Plugin_Handled;
	}
	
	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	
	StartPrepSDKCall(SDKCall_GameRules);
	if (!PrepSDKCall_SetSignature(SDKLibrary_Server, "@_ZN16CTerrorGameRules15SetRoundEndTimeEf", 1))
		return Plugin_Handled;
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	
	g_hSetEndTime = EndPrepSDKCall();
	
	float finput = StringToFloat(arg);
	float result = (finput * 60.0);
	
	SDKCall(g_hSetEndTime, result);
	return Plugin_Handled;
}

public Action Cmd_FakeSurvivalStart(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	PrintToChat(client, "Starting fake survival");
	
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetSignature(SDKLibrary_Server, "@_ZN21CDirectorSurvivalMode22OnSurvivalRoundStartedENS_19SurvivalTriggerTypeEb", 1)) {
		PrintToChat(client, "Couldn't prep signature for this func");
		return Plugin_Handled;
	}
	
	// SurvivalTriggerType triggerType
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	
	// Bool
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	
	
	g_hStartRoundSurvival = EndPrepSDKCall();
	if (g_hStartRoundSurvival == null)
		return Plugin_Handled;
	
	SDKCall(g_hStartRoundSurvival, CDirectorSurvivalMode, 0, false);
	
	return Plugin_Handled;
}

public Action Cmd_StartSurvivalRound(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	PrintToChat(client, "Starting survival..");
	
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetSignature(SDKLibrary_Server, "@_ZN21CDirectorSurvivalMode22OnSurvivalRoundStartedENS_19SurvivalTriggerTypeEb", 1)) {
		PrintToChat(client, "Couldn't prep signature for this func");
		return Plugin_Handled;
	}
	
	// SurvivalTriggerType triggerType
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	
	// Bool
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	
	
	g_hStartRoundSurvival = EndPrepSDKCall();
	if (g_hStartRoundSurvival == null)
		return Plugin_Handled;
	
	SDKCall(g_hStartRoundSurvival, CDirectorSurvivalMode, 0, true);
	return Plugin_Handled;
}

public Action Cmd_EndSurvivalRound(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetSignature(SDKLibrary_Server, "@_ZN21CDirectorSurvivalMode29InitiateEndScenarioNonVirtualEv", 1)) {
		PrintToChat(client, "Couldn't prep signature for this func");
		return Plugin_Handled;
	}
	
	g_hEndSurvivalRound = EndPrepSDKCall();
	if (g_hEndSurvivalRound == null)
		return Plugin_Handled;
	
	PrintToChat(client, "Ending the round..");
	SDKCall(g_hEndSurvivalRound, client);
	return Plugin_Handled;
}

public Action Cmd_TankSpawnsInfo(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	g_bInTestMode = !g_bInTestMode;
	PrintToChatAll("[Survival] Tank Spawn info is now %s", g_bInTestMode ? "Enabled" : "Disabled");
	return Plugin_Handled;
}

public Action Cmd_TimeTest(int args)
{
	// Reads NaN
	//PrintToServer("SURVIVAL_DIRECTOR_TIME = %f", g_SurvivalDirector.GetFloat(SURVIVAL_DIRECTOR_TIME));
	
	PrintToServer("Time: %f", g_SurvivalDirector.GetInt(SURVIVAL_SCORE_MULTIPLIER));
	
	return Plugin_Handled;
}

public Action Cmd_TestRec(int client, int args)
{
	g_timerupdate[client] = !g_timerupdate[client];
	PrintToChat(client, "Now %s", g_timerupdate[client] ? "Updating Variables test" : "Not updating variables");
	
	if (g_timerupdate[client])
		CreateTimer(1.0, Timer_Updateshit, GetClientUserId(client), TIMER_REPEAT);
		
	return Plugin_Handled;
}

public Action Timer_Updateshit(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsClientInGame(client) || !g_timerupdate[client])
	{
		return Plugin_Stop;
	}
	
	/*
	 * to format values: Some Val: %i\nSome other value: %i\nOther value %i
	*/

	PrintHintText(client, "m_flRoundDuration = %f", GameRules_GetPropFloat("m_flRoundDuration"));
	
	
	return Plugin_Continue;
}

/*
 * sm_settime - visual change only.. networked property for the survival time
*/
public Action Command_SetSurvivalTime(int client, int args)
{
	if (args < 1) {
		PrintToChat(client, "Usage: sm_settime <minutes>");
		return Plugin_Handled;
	}
	char text[24];
	GetCmdArg(1, text, sizeof(text));
	
	float ftime = StringToFloat(text);
	float currentTime = GetGameTime();
	
	GameRules_SetPropFloat("m_flRoundStartTime", currentTime - (ftime * 60.0));
	PrintToChat(client, "Survival Round time set to %.2f Minutes", ftime);
	return Plugin_Handled;
}

/*
 * sm_timescale - Change the timescale, dont go too high as it will lag the server and potentially crash
*/
public Action Command_TimeScale(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	if (args < 1) {
		PrintToChat(client, "Usage: sm_timecale <val 1.0-20.0>");
		return Plugin_Handled;
	}
	
	char arg[24];
	GetCmdArg(1, arg, sizeof(arg));
	
	SetTimeScale(arg);
	PrintToChat(client, "\x01Setting timescale to \x03%s", arg);
	return Plugin_Handled;
}

/*
 * sm_skiptime - Raise timescale and teleport all to safety and back, sets blind on nextbots while skip happens
*/
public Action Command_SkipTime(int client, int args)
{
	if (!bHasUsedSkip)
	{
		PrintToChat(client, "Preparing to skip time safely..");
		float newpos[3] =  { 0.0, 0.0, 0.0 };
	
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsPlayerAlive(i))
				continue;
			
			if (GetClientTeam(i) == 2)
			{
				static float vpos[3];
				GetClientAbsOrigin(i, vpos);
			
				// Raise Z a little to prevent stuck
				vpos[2] += 5.0;
				
				g_hOldPosition[i] = vpos;
				TeleportEntity(i, newpos, NULL_VECTOR, NULL_VECTOR);
			}
		}
	
		SetConVarInt(FindConVar("nb_blind"), 1);
		SetTimeScale("18.0");
		bHasUsedSkip = true;
	} 
	else
	{
		PrintToChat(client, "Done with skipping time, resetting...");
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsPlayerAlive(i))
				continue;
			
			if (GetClientTeam(i) == 2)
			{
				TeleportEntity(i, g_hOldPosition[i], NULL_VECTOR, NULL_VECTOR);
			}
		}
		
		SetTimeScale("1.0");
		SetConVarInt(FindConVar("nb_blind"), 0);
		bHasUsedSkip = false;
	}
	return Plugin_Handled;
}

/*
 * sm_backtime - Sets the timer in reverse
*/
public Action Cmd_SetBackTime(int client, int args)
{
	if (!client)
		return Plugin_Handled;
		
	g_bBackTimeEnabled = !g_bBackTimeEnabled;
	PrintToChat(client, "\x01Timer backwards is now \x03%s", g_bBackTimeEnabled ? "enabled" : "disabled");
	
	if (g_bBackTimeEnabled)
	{
		if (g_hTimerBackwards == null)
		{
			g_hTimerBackwards = CreateTimer(0.6, Timer_Update, _, TIMER_REPEAT);
		}
	}
	else
	{
		if (g_hTimerBackwards != null)
			g_hTimerBackwards = null;
	}
	return Plugin_Handled;
}

public Action Timer_Update(Handle timer)
{
	if (!g_bBackTimeEnabled)
		return Plugin_Stop;
	
	float now = GameRules_GetPropFloat("m_flRoundStartTime");
	now += 1.0;
	GameRules_SetPropFloat("m_flRoundStartTime", now);
	return Plugin_Continue;
}