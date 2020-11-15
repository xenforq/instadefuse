#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

new EngineVersion:GameName;

#undef REQUIRE_PLUGIN
#tryinclude <autoexecconfig>

#define PREFIX "\x01[\x05Retakes\x01] "

new const String:PLUGIN_VERSION[] = "1.0.2";

new Handle:hcv_NoobMargin = INVALID_HANDLE;
new Handle:hcv_AutoExplode = INVALID_HANDLE;

new Handle:hcv_InfernoDuration = INVALID_HANDLE;
new Handle:hcv_InfernoDistance = INVALID_HANDLE;

new Handle:fw_OnInstantDefusePre = INVALID_HANDLE;
new Handle:fw_OnInstantDefusePost = INVALID_HANDLE;

new Float:LastDefuseTimeLeft;

new Handle:hTimer_MolotovThreatEnd = INVALID_HANDLE;

new ForceUseEntity[MAXPLAYERS+1];

public Plugin:myinfo =
{
	name = "instadefuse",
	author = "Orbit One",
	description = "Allows you to instantly defuse the bomb when all terrorists are dead and nothing can stop the defuse.",
	version = PLUGIN_VERSION,
	url = ""
}

public OnPluginStart()
{
	GameName = GetEngineVersion();
	
	#if defined _autoexecconfig_included
	
	AutoExecConfig_SetFile("instadefuse");
	
	#endif
	
	HookEvent("bomb_begindefuse", Event_BombBeginDefuse, EventHookMode_Post);
	HookEvent("bomb_defused", Event_BombDefused, EventHookMode_Post);
	
	if(isCSGO())
		HookEvent("molotov_detonate", Event_MolotovDetonate);
		
	HookEvent("hegrenade_detonate", Event_AttemptInstantDefuse, EventHookMode_Post);

	HookEvent("player_death", Event_AttemptInstantDefuse, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	
	SetConVarString(CreateConVar("instadefuse_version", PLUGIN_VERSION), PLUGIN_VERSION);
	
	hcv_NoobMargin = UC_CreateConVar("instadefuse_questionable", "5.2", "To prevent players from running for their lives when instadefuse fails, instadefuse won't become active if the time is below the set threshold.", FCVAR_NOTIFY);
	hcv_AutoExplode = UC_CreateConVar("instadefuse_auto_explode", "0.0", "Toggle to make defuses with no chance trigger the bomb explostion instantly. Requires instadefuse_questionable to be 0.0.", FCVAR_NOTIFY);
	
	if(isCSGO())
	{
		hcv_InfernoDuration = UC_CreateConVar("instadefuse_inferno_duration", "7.0", "The active duration of molotovs in seconds.");
		hcv_InfernoDistance = UC_CreateConVar("instadefuse_inferno_distance", "225.0", "The maximum spread distance of molotovs.");
	}
	
	fw_OnInstantDefusePre = CreateGlobalForward("InstaDefuse_OnInstantDefusePre", ET_Event, Param_Cell, Param_Cell);
	fw_OnInstantDefusePost = CreateGlobalForward("InstaDefuse_OnInstantDefusePost", ET_Ignore, Param_Cell, Param_Cell);
	
	#if defined _autoexecconfig_included
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	#endif
	
	#if defined _updater_included
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
}


public OnMapStart()
{
	hTimer_MolotovThreatEnd = INVALID_HANDLE;
}

public Action:Event_RoundStart(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	if(hTimer_MolotovThreatEnd != INVALID_HANDLE)
	{
		CloseHandle(hTimer_MolotovThreatEnd);
		hTimer_MolotovThreatEnd = INVALID_HANDLE;
	}
}

public Action:Event_BombDefused(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(client == 0)
		return;
		
	if(LastDefuseTimeLeft != -1.0)
		PrintToChatAll("%s%N \x05defused \x01the bomb with \x09%.3f seconds \x01left.", PREFIX, client, -1.0 * LastDefuseTimeLeft);
}

public Action:Event_BombBeginDefuse(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{	
	RequestFrame(Event_BombBeginDefusePlusFrame, GetEventInt(hEvent, "userid"));
	
	AttemptInstantDefuse(GetClientOfUserId(GetEventInt(hEvent, "userid")));
	return Plugin_Continue;
}

public Event_BombBeginDefusePlusFrame(UserId)
{
	new client = GetClientOfUserId(UserId);
	
	if(client == 0)
		return;
		
	AttemptInstantDefuse(client);
}

stock AttemptInstantDefuse(client, exemptNade = 0)
{
 	LastDefuseTimeLeft = -1.0;
	
	if(!GetEntProp(client, Prop_Send, "m_bIsDefusing"))
		return;
		
	new StartEnt = MaxClients + 1;
		
	new c4 = FindEntityByClassname(StartEnt, "planted_c4");
	
	if(c4 == -1)
		return;
		
	else if(FindAlivePlayer(CS_TEAM_T) != 0)
		return;
	
	LastDefuseTimeLeft = GetEntPropFloat(c4, Prop_Send, "m_flDefuseCountDown") - GetEntPropFloat(c4, Prop_Send, "m_flC4Blow");
	
	if(GetEntPropFloat(c4, Prop_Send, "m_flC4Blow") - GetConVarFloat(hcv_NoobMargin) < GetEntPropFloat(c4, Prop_Send, "m_flDefuseCountDown"))
	{
		if(GetConVarFloat(hcv_NoobMargin) == 0.0)
		{
			switch(GetConVarBool(hcv_AutoExplode))
			{
				case true:	SetEntPropFloat(c4, Prop_Send, "m_flC4Blow", 0.0);
				case false:
				{
					PrintToChatAll("%sOops, too late. The bomb is exploding.", PREFIX);
					PrintToChatAll("%s%N was \x09%.3f seconds \x01too late to defusing the bomb.", PREFIX, client, LastDefuseTimeLeft);
				}
			}
		}	
		else
			PrintToChatAll("%sTime is ticking. Good luck defusing!", PREFIX);
		
		LastDefuseTimeLeft = -1.0;
		
		return;
	}

	new ent
	if((ent = FindEntityByClassname(StartEnt, "hegrenade_projectile")) != -1)
	{
		if(ent != exemptNade)
		{
			PrintToChatAll("%sThere is an active grenade somewhere. Good luck defusing!", PREFIX);
			
			LastDefuseTimeLeft = -1.0;
			
			return;
		}
	}	
	
	ent = -1;
	
	if((ent = FindEntityByClassname(StartEnt, "molotov_projectile")) != -1)
	{
		if(ent != exemptNade)
		{
			PrintToChatAll("%sThere is an active grenade somewhere. Good luck defusing!", PREFIX);
			
			LastDefuseTimeLeft = -1.0;
			
			return;
		}
	}
	else if(hTimer_MolotovThreatEnd != INVALID_HANDLE)
	{
		PrintToChatAll("%sThere is a molotov close to the bomb. Good luck defusing!", PREFIX);
		
		LastDefuseTimeLeft = -1.0;
		
		return;
	}
	
	new Action:ReturnValue;
	
	Call_StartForward(fw_OnInstantDefusePre);
	
	Call_PushCell(client);
	Call_PushCell(c4);
	
	Call_Finish(ReturnValue);
	
	if(ReturnValue != Plugin_Continue && ReturnValue != Plugin_Changed)
	{
		LastDefuseTimeLeft = -1.0;
		
		return;
	}
	ForceUseEntity[client] = 30;
	SDKUnhook(client, SDKHook_PreThink, OnClientPreThink);
	SDKHook(client, SDKHook_PreThink, OnClientPreThink);
}

public Action:OnClientPreThink(client)
{
	if(ForceUseEntity[client] <= 0)
	{
		SetEntPropEnt(client, Prop_Send, "m_hUseEntity", -1);

		SDKUnhook(client, SDKHook_PreThink, OnClientPreThink);
		
		return;
	}
	
	ForceUseEntity[client]--;
	
	new StartEnt = MaxClients + 1;
		
	new c4 = FindEntityByClassname(StartEnt, "planted_c4");
	
	if(c4 == -1)
	{
		SDKUnhook(client, SDKHook_PreThink, OnClientPreThink);
		
		SetEntPropEnt(client, Prop_Send, "m_hUseEntity", -1);
		
		return;
	}	
	
	SetEntPropEnt(client, Prop_Send, "m_hUseEntity", c4);
	SetEntPropFloat(c4, Prop_Send, "m_flDefuseCountDown", 0.0);
	SetEntPropFloat(c4, Prop_Send, "m_flDefuseLength", 0.0);
	SetEntProp(client, Prop_Send, "m_iProgressBarDuration", 0);

}


public Frame_InstantDefuseAgain(UserId)
{
	new client = GetClientOfUserId(UserId);
	
	if(client == 0)
		return;
	
	new StartEnt = MaxClients + 1;
	
	new c4 = FindEntityByClassname(StartEnt, "planted_c4");
	
	if(c4 == -1)
		return;
		
	SetEntProp(client, Prop_Send, "m_bIsDefusing", true);
	SetEntPropEnt(c4, Prop_Send, "m_hBombDefuser", client);
	SetEntPropFloat(c4, Prop_Send, "m_flDefuseCountDown", 0.0);
	SetEntPropFloat(c4, Prop_Send, "m_flDefuseLength", 0.0);
	SetEntProp(client, Prop_Send, "m_iProgressBarDuration", 0);
	
	Call_StartForward(fw_OnInstantDefusePost);
	
	Call_PushCell(client);
	Call_PushCell(c4);
	
	Call_Finish();
}

public Action:Event_AttemptInstantDefuse(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	new defuser = FindDefusingPlayer();
	
	new ent = 0;
	
	if(StrContains(Name, "detonate") != -1)
		ent = GetEventInt(hEvent, "entityid");
		
	if(defuser != 0)
		AttemptInstantDefuse(defuser, ent);
}
public Action:Event_MolotovDetonate(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	if(!isCSGO())
		return;
		
	new Float:Origin[3];
	Origin[0] = GetEventFloat(hEvent, "x");
	Origin[1] = GetEventFloat(hEvent, "y");
	Origin[2] = GetEventFloat(hEvent, "z");
	
	new c4 = FindEntityByClassname(MaxClients + 1, "planted_c4");
	
	if(c4 == -1)
		return;
	
	new Float:C4Origin[3];
	GetEntPropVector(c4, Prop_Data, "m_vecOrigin", C4Origin);
	
	if(GetVectorDistance(Origin, C4Origin, false) > GetConVarFloat(hcv_InfernoDistance))
		return;

	if(hTimer_MolotovThreatEnd != INVALID_HANDLE)
	{
		CloseHandle(hTimer_MolotovThreatEnd);
		hTimer_MolotovThreatEnd = INVALID_HANDLE;
	}
	
	hTimer_MolotovThreatEnd = CreateTimer(GetConVarFloat(hcv_InfernoDuration), Timer_MolotovThreatEnd, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_MolotovThreatEnd(Handle:hTimer)
{
	hTimer_MolotovThreatEnd = INVALID_HANDLE;
	
	new defuser = FindDefusingPlayer();
	
	if(defuser != 0)
		AttemptInstantDefuse(defuser);
}

stock FindDefusingPlayer()
{
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
			
		else if(!GetEntProp(i, Prop_Send, "m_bIsDefusing"))
			continue;
			
		return i;
	}
	
	return 0;
}

stock FindAlivePlayer(Team)
{
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
			
		else if(GetClientTeam(i) != Team)
			continue;
			
		return i;
	}
	
	return 0;
}


// From Useful Commands by eyal282
#if defined _autoexecconfig_included

stock ConVar:UC_CreateConVar(const String:name[], const String:defaultValue[], const String:description[]="", flags=0, bool:hasMin=false, Float:min=0.0, bool:hasMax=false, Float:max=0.0)
{
	return AutoExecConfig_CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
}

#else

stock ConVar:UC_CreateConVar(const String:name[], const String:defaultValue[], const String:description[]="", flags=0, bool:hasMin=false, Float:min=0.0, bool:hasMax=false, Float:max=0.0))AutoExecConfig_CreateConVar(const char[] name, const char[] defaultValue, const char[] description="", int flags=0, bool hasMin=false, float min=0.0, bool hasMax=false, float max=0.0)
{
	return CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
}

#endif

stock bool:isCSGO()
{
	return GameName == Engine_CSGO;
}