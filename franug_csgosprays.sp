#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <emitsoundany>

#define SOUND_SPRAY_REL "*/player/sprayer.mp3"
#define SOUND_SPRAY "player/sprayer.mp3"

#define MAX_SPRAYS 128
#define MAX_MAP_SPRAYS 200

new g_iLastSprayed[MAXPLAYERS + 1];
new String:path_decals[PLATFORM_MAX_PATH];
new g_sprayElegido[MAXPLAYERS + 1];

new g_time;
new g_distance;
new bool:g_use;
new g_maxMapSprays;
new g_resetTimeOnKill;
new Handle:h_distance;
new Handle:h_time;
new Handle:hCvar;
new Handle:h_use;
new Handle:h_maxMapSprays;
new Handle:h_resetTimeOnKill;

new Handle:c_GameSprays = INVALID_HANDLE;

enum Listado
{
	String:Nombre[32],
	index
}

enum MapSpray
{
	Float:vecPos[3],
	index3
}

new g_sprays[MAX_SPRAYS][Listado];
new g_sprayCount = 0;

// Array to store previous sprays
new g_spraysMapAll[MAX_MAP_SPRAYS][MapSpray];
// Running count of all sprays on the map
new g_sprayMapCount = 0;
// Current index of the last spray in the array; this resets to 0 when g_maxMapSprays is reached (FIFO)
new g_sprayIndexLast = 0;


#define PLUGIN "1.4.4"

public Plugin:myinfo =
{
	name = "SM Franug CSGO Sprays",
	author = "Franc1sco Steam: franug",
	description = "Use sprays in CSGO",
	version = PLUGIN,
	url = "http://steamcommunity.com/id/franug"
};

public OnPluginStart()
{
	c_GameSprays = RegClientCookie("Sprays", "Sprays", CookieAccess_Private);
	hCvar = CreateConVar("sm_franugsprays_version", PLUGIN, "SM Franug CSGO Sprays", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	SetConVarString(hCvar, PLUGIN);
	
	RegConsoleCmd("sm_spray", MakeSpray);
	RegConsoleCmd("sm_sprays", GetSpray);
	HookEvent("round_start", roundStart);
	HookEvent("player_death", Event_PlayerDeath);
	
	h_time = CreateConVar("sm_csgosprays_time", "30");
	h_distance = CreateConVar("sm_csgosprays_distance", "115");
	h_use = CreateConVar("sm_csgosprays_use", "1");
	h_maxMapSprays = CreateConVar("sm_csgosprays_mapmax", "25");
	h_resetTimeOnKill = CreateConVar("sm_csgosprays_reset_time_on_kill", "1");
	
	g_time = GetConVarInt(h_time);
	g_distance = GetConVarInt(h_distance);
	g_use = GetConVarBool(h_use);
	g_maxMapSprays = GetConVarInt(h_maxMapSprays);
	g_resetTimeOnKill = GetConVarBool(h_resetTimeOnKill);
	HookConVarChange(h_time, OnConVarChanged);
	HookConVarChange(h_distance, OnConVarChanged);
	HookConVarChange(hCvar, OnConVarChanged);
	HookConVarChange(h_use, OnConVarChanged);
	HookConVarChange(h_maxMapSprays, OnConVarChanged);
	HookConVarChange(h_resetTimeOnKill, OnConVarChanged);
}

public OnPluginEnd()
{
	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			OnClientDisconnect(client);
		}
	}
}

public OnClientCookiesCached(client)
{
	new String:SprayString[12];
	GetClientCookie(client, c_GameSprays, SprayString, sizeof(SprayString));
	g_sprayElegido[client]  = StringToInt(SprayString);
}

public OnClientDisconnect(client)
{
	if(AreClientCookiesCached(client))
	{
		new String:SprayString[12];
		Format(SprayString, sizeof(SprayString), "%i", g_sprayElegido[client]);
		SetClientCookie(client, c_GameSprays, SprayString);
	}
}

public OnConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (convar == h_time)
	{
		g_time = StringToInt(newValue);
	}
	else if (convar == h_distance)
	{
		g_distance = StringToInt(newValue);
	}
	else if (convar == hCvar)
	{
		SetConVarString(hCvar, PLUGIN);
	}
	else if (convar == h_use)
	{
		g_use = bool:StringToInt(newValue);
	}
	else if (convar == h_maxMapSprays)
	{
		if(StringToInt(newValue) > MAX_MAP_SPRAYS)
		{		
			g_maxMapSprays = MAX_MAP_SPRAYS;
			SetConVarInt(h_maxMapSprays, MAX_MAP_SPRAYS);
		}
		else
			g_maxMapSprays = StringToInt(newValue);
	}
	else if (convar == h_resetTimeOnKill)
	{
		g_resetTimeOnKill = bool:StringToInt(newValue);
	}
}

public Action:roundStart(Handle:event, const String:name[], bool:dontBroadcast) 
{
	for (new i = 1; i < GetMaxClients(); i++)
		if (IsClientInGame(i))
			g_iLastSprayed[i] = false;
			
	if(g_sprayMapCount > g_maxMapSprays)
		g_sprayMapCount = g_maxMapSprays;
	for (new j = 0; j < g_sprayMapCount; j++)
	{
		TE_SetupBSPDecalCall(g_spraysMapAll[j][vecPos], g_spraysMapAll[j][index3]);
		TE_SendToAll();
	}

}

public OnClientPostAdminCheck(iClient)
{
	g_iLastSprayed[iClient] = false;
	//g_sprayElegido[iClient] = 0;
}

public OnMapStart()
{
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "sound/%s", SOUND_SPRAY);
	AddFileToDownloadsTable(sBuffer);
	
	FakePrecacheSound(SOUND_SPRAY_REL);
	
	BuildPath(Path_SM, path_decals, sizeof(path_decals), "configs/csgo-sprays/sprays.cfg");
	ReadDecals();
	g_sprayMapCount = 0;
	g_sprayIndexLast = 0;
}

public Action:MakeSpray(iClient, args)
{	
	if(!iClient || !IsClientInGame(iClient))
		return Plugin_Continue;

	if(!IsPlayerAlive(iClient))
	{
		PrintToChat(iClient, " \x04[SM_CSGO-SPRAYS]\x01 You need to be alive for use this command");
		return Plugin_Handled;
	}

	new iTime = GetTime();
	new restante = (iTime - g_iLastSprayed[iClient]);
	
	if(restante < g_time)
	{
		PrintToChat(iClient, " \x04[SM_CSGO-SPRAYS]\x01 You need to wait %i seconds more to use this command", g_time-restante);
		return Plugin_Handled;
	}

	decl Float:fClientEyePosition[3];
	GetClientEyePosition(iClient, fClientEyePosition);

	decl Float:fClientEyeViewPoint[3];
	GetPlayerEyeViewPoint(iClient, fClientEyeViewPoint);

	decl Float:fVector[3];
	MakeVectorFromPoints(fClientEyeViewPoint, fClientEyePosition, fVector);

	if(GetVectorLength(fVector) > g_distance)
	{
		PrintToChat(iClient, " \x04[SM_CSGO-SPRAYS]\x01 You are away from the wall to use this command");
		return Plugin_Handled;
	}

	if(g_sprayElegido[iClient] == 0)
	{
		TE_SetupBSPDecal(fClientEyeViewPoint, g_sprays[GetRandomInt(1, g_sprayCount-1)][index]);
	}
	else
	{
		if(g_sprays[g_sprayElegido[iClient]][index] == 0)
		{
			PrintToChat(iClient, " \x04[SM_CSGO-SPRAYS]\x01 your spray doesn't work, choose other with !sprays");
			return Plugin_Handled;
		}
		TE_SetupBSPDecal(fClientEyeViewPoint, g_sprays[g_sprayElegido[iClient]][index]);
		
		// Save spray position and identifier
		if(g_sprayIndexLast == g_maxMapSprays)
			g_sprayIndexLast = 0;
		g_spraysMapAll[g_sprayIndexLast][vecPos] = fClientEyeViewPoint;
		g_spraysMapAll[g_sprayIndexLast][index3] = g_sprays[g_sprayElegido[iClient]][index];
		g_sprayIndexLast++;
		if(g_sprayMapCount != g_maxMapSprays)
			g_sprayMapCount++;
	}
	TE_SendToAll();

	EmitSoundToAll(SOUND_SPRAY_REL, iClient, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6);

	g_iLastSprayed[iClient] = iTime;
	return Plugin_Handled;
}

public Action:GetSpray(client, args)
{	
	new Handle:menu = CreateMenu(DIDMenuHandler);
	SetMenuTitle(menu, "Choose your Spray");
	decl String:item[4];
	AddMenuItem(menu, "0", "Random spray");
	for (new i=1; i<g_sprayCount; ++i) {
		Format(item, 4, "%i", i);
		AddMenuItem(menu, item, g_sprays[i][Nombre]);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public DIDMenuHandler(Handle:menu, MenuAction:action, client, itemNum) 
{
	if ( action == MenuAction_Select ) 
	{
		decl String:info[4];
		
		GetMenuItem(menu, itemNum, info, sizeof(info));
		g_sprayElegido[client] = StringToInt(info);
		PrintToChat(client, " \x04[SM_CSGO-SPRAYS]\x01 You have choosen\x03 %s \x01as your spray!",g_sprays[g_sprayElegido[client]][Nombre]);
	}
	else if (action == MenuAction_Cancel) 
	{ 
		PrintToServer("Client %d's menu was cancelled.  Reason: %d", client, itemNum); 
	} 
		
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

stock GetPlayerEyeViewPoint(iClient, Float:fPosition[3])
{
	decl Float:fAngles[3];
	GetClientEyeAngles(iClient, fAngles);

	decl Float:fOrigin[3];
	GetClientEyePosition(iClient, fOrigin);

	new Handle:hTrace = TR_TraceRayFilterEx(fOrigin, fAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);
	if(TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fPosition, hTrace);
		CloseHandle(hTrace);
		return true;
	}
	CloseHandle(hTrace);
	return false;
}

public bool:TraceEntityFilterPlayer(iEntity, iContentsMask)
{
	return iEntity > GetMaxClients();
}

TE_SetupBSPDecalCall(const Float:vecOrigin[], index2) {
	
	// I know.. couldn't get the array to play nice with the compiler.
	new Float:vector[3];
	for (new i=0; i < 3; i++)
		vector[i] = vecOrigin[i];
	TE_SetupBSPDecal(vector, index2);
}

TE_SetupBSPDecal(const Float:vecOrigin[3], index2) {
	
	TE_Start("World Decal");
	TE_WriteVector("m_vecOrigin",vecOrigin);
	TE_WriteNum("m_nIndex",index2);
}

ReadDecals() {
	
	decl String:buffer[PLATFORM_MAX_PATH];
	decl String:download[PLATFORM_MAX_PATH];
	decl Handle:kv;
	decl Handle:vtf;
	g_sprayCount = 1;
	

	kv = CreateKeyValues("Sprays");
	FileToKeyValues(kv, path_decals);

	if (!KvGotoFirstSubKey(kv)) {

		SetFailState("CFG File not found: %s", path_decals);
		CloseHandle(kv);
	}
	do {

		KvGetSectionName(kv, buffer, sizeof(buffer));
		Format(g_sprays[g_sprayCount][Nombre], 32, "%s", buffer);
		KvGetString(kv, "path", buffer, sizeof(buffer));
		
		new precacheId = PrecacheDecal(buffer, true);
		g_sprays[g_sprayCount][index] = precacheId;
		decl String:decalpath[PLATFORM_MAX_PATH];
		Format(decalpath, sizeof(decalpath), buffer);
		Format(download, sizeof(download), "materials/%s.vmt", buffer);
		AddFileToDownloadsTable(download);
		vtf = CreateKeyValues("LightmappedGeneric");
		FileToKeyValues(vtf, download);
		KvGetString(vtf, "$basetexture", buffer, sizeof(buffer), buffer);
		CloseHandle(vtf);
		Format(download, sizeof(download), "materials/%s.vtf", buffer);
		AddFileToDownloadsTable(download);
		g_sprayCount++;
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	
	for (new i=g_sprayCount; i<MAX_SPRAYS; ++i) 
	{
		g_sprays[i][index] = 0;
	}
}

public Action:OnPlayerRunCmd(iClient, &buttons, &impulse)
{
	if(!g_use) return;
	
	if (buttons & IN_USE)
	{
		if(!IsPlayerAlive(iClient))
		{
			return;
		}

		new iTime = GetTime();
		new restante = (iTime - g_iLastSprayed[iClient]);
	
		if(restante < g_time)
		{
			return;
		}

		decl Float:fClientEyePosition[3];
		GetClientEyePosition(iClient, fClientEyePosition);

		decl Float:fClientEyeViewPoint[3];
		GetPlayerEyeViewPoint(iClient, fClientEyeViewPoint);

		decl Float:fVector[3];
		MakeVectorFromPoints(fClientEyeViewPoint, fClientEyePosition, fVector);

		if(GetVectorLength(fVector) > g_distance)
		{
			return;
		}


		if(g_sprayElegido[iClient] == 0)
		{
			TE_SetupBSPDecal(fClientEyeViewPoint, g_sprays[GetRandomInt(1, g_sprayCount-1)][index]);
		}
		else
		{
			if(g_sprays[g_sprayElegido[iClient]][index] == 0)
			{
				PrintToChat(iClient, " \x04[SM_CSGO-SPRAYS]\x01 your spray doesn't work, choose other with !sprays");
				return;
			}
			TE_SetupBSPDecal(fClientEyeViewPoint, g_sprays[g_sprayElegido[iClient]][index]);
			
			// Save spray position and identifier
			if(g_sprayIndexLast == g_maxMapSprays)
				g_sprayIndexLast = 0;
			g_spraysMapAll[g_sprayIndexLast][vecPos] = fClientEyeViewPoint;
			g_spraysMapAll[g_sprayIndexLast][index3] = g_sprays[g_sprayElegido[iClient]][index];
			g_sprayIndexLast++;
			if(g_sprayMapCount != g_maxMapSprays)
				g_sprayMapCount++;
		}
		TE_SendToAll();

		PrintToChat(iClient, " \x04[SM_CSGO-SPRAYS]\x01 You have used your spray!");
		EmitAmbientSoundAny(SOUND_SPRAY_REL, fVector, iClient, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6);

		g_iLastSprayed[iClient] = iTime;
	}
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_resetTimeOnKill)
	{
		new user = GetClientOfUserId(GetEventInt(event, "attacker"));
		new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
		if(user == 0 || user == victim || IsFakeClient(user))
			return Plugin_Continue;
		
		// Reset attacker's spray time on a kill
		g_iLastSprayed[user] = false;
	}
	
	return Plugin_Continue;
}

stock FakePrecacheSound( const String:szPath[] )
{
	AddToStringTable( FindStringTable( "soundprecache" ), szPath );
}