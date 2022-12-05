#pragma semicolon 1
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
// #include <morecolors>
#include <tfdb>
#pragma newdecls required

Handle db = null;

enum struct TopSpeedPlayer {
		int iTopSpeed;
		int iTopDeflects;
}

TopSpeedPlayer Player[MAXPLAYERS + 1];

int iNewSpeed = 0;
int iOldSpeed = 0;

/**
 * We get this from our config, since we always want to use
 * different servers ids like, tf, tf1 etc.
 */
char cServerId[64];

public Plugin myinfo =
{
	name = "topspeed",
	author = "Tolfx",
	description = "Topspeed plugin for Dodgeball",
	version = "1.1.0",
	url = "https://github.com/Tolfx/OfficialDodgeball"
};

public void OnPluginStart()
{
	RegConsoleCmd("topspeed", CommandTopSpeed, "Shows the top speed of the server");
	RegConsoleCmd("ts", CommandTopSpeed, "Shows the top speed of the server");

	RegConsoleCmd("topcurrent", CommandTopCurrent, "Shows yours top speed on the server");
	RegConsoleCmd("tc", CommandTopCurrent, "Shows yours top speed on the server");

	/* Hook players deaths */
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	RegAdminCmd("sm_updatetopspeeds", UpdateStats, ADMFLAG_ROOT, "Updates the top speed stats", _, FCVAR_PROTECTED);

	AutoExecConfig(true, "tfdb_topspeed");
}

void GetConfigs(char[] path = "tfdb_topspeed.cfg")
{
	// Get the server id from the config
	char strPath[PLATFORM_MAX_PATH];
	char strFileName[PLATFORM_MAX_PATH];
	FormatEx(strFileName, sizeof(strFileName), "configs/dodgeball/%s", path);
	BuildPath(Path_SM, strPath, sizeof(strPath), strFileName);

	LogMessage("[topspeed] Config path: %s", strPath);

	if (FileExists(strPath, true))
	{
		KeyValues kv = new KeyValues("tfdb_topspeed");
		if (!kv.ImportFromFile(strPath))
		{
			LogError("[TFDB] Failed to load config file: %s", strPath);
			delete kv;
			return;
		}

		kv.GotoFirstSubKey();

		do
		{
			char strSection[64];
			kv.GetSectionName(strSection, sizeof(strSection));
			LogMessage("[TFDB] Loaded config section: %s", strSection);
			if (StrEqual(strSection, "general"))
			{
				kv.GetString("serverid", cServerId, sizeof(cServerId));
				LogMessage("[TFDB] Server id: %s", cServerId);
			}

		} while (kv.GotoNextKey());
	}
}

public void OnConfigsExecuted() {
	GetConfigs();
	LogMessage("[TFDB] Configs executed");
	if (!cServerId) {
		LogError("[TFDB] Server id is not set, please set it in the config");
		return;
	}
	/* Start Database */
	StartDatabase();
}

/**
 * SQL Database stuff..
 */

void StartDatabase()
{
	char error[255], Query[255];
	if (SQL_CheckConfig("topspeed"))
	{
		db = SQL_Connect("topspeed", true, error, sizeof(error));
	}
	else
	{
		LogError("Could not find database config!");
		return;
	}

	SQL_LockDatabase(db);
	// Create a new table, with steamid, name, topspeed, topdeflects and serverid
	// We want to ensure that we only have one entry per steamid and serverid
	Format(Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS topspeed (steamid VARCHAR(32) NOT NULL, name VARCHAR(32) NOT NULL, topspeed INT NOT NULL, topdeflects INT NOT NULL, serverid VARCHAR(32) NOT NULL, PRIMARY KEY (steamid, serverid))");
	SQL_FastQuery(db, Query);
	SQL_UnlockDatabase(db);

	LoadData();
}

void LoadData()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsEntityConnectedClient(iClient) || IsFakeClient(iClient)) return;
		UpdateOrAddToDatabase(iClient);
	}
}

public void UpdateOrAddToDatabase(int iClient)
{
	char Query[255];
	char name[32];
	GetClientName(iClient, name, sizeof(name));
	Format(Query, sizeof(Query), "SELECT * FROM topspeed WHERE steamid = '%s' AND serverid = '%s'", GetSteamId(iClient), cServerId);
	SQL_TQuery(db, hsql_Player, Query, GetClientUserId(iClient));
}

public void hsql_Player(Handle owner, Handle query, const char[] error, any data)
{
	// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	} else {
		int iClient = GetClientOfUserId(data);
		// Log our query
		LogMessage("Affected rows: %i", SQL_GetAffectedRows(query));
		if (SQL_GetAffectedRows(query) == 0)
		{
			LogMessage("No rows found, adding to database");
			// If there is no rows, we add the player to the database, edge case
			Player[iClient].iTopSpeed = 0;
			Player[iClient].iTopDeflects = 0;
			EdgeCaseAddPlayerToDatabase(iClient);
		} else {
			SQL_FetchRow(query);
			Player[iClient].iTopSpeed = SQL_FetchInt(query, 2);
			Player[iClient].iTopDeflects = SQL_FetchInt(query, 3);
			UpdatePlayerToDB(iClient);
		}
	}

}

public void hsql_TopSpeed(Handle owner, Handle query, const char[] error, any data)
{
	// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	}
	int iClient = GetClientOfUserId(data);
 	char PlayerName[40], PlayerID[40], menuline[40];
	Menu menu = CreateMenu(hMenu_TopSpeed);
	while (SQL_FetchRow(query))
	{
		SQL_FetchString(query, 0, PlayerName , 40);
		SQL_FetchString(query, 1, PlayerID , 40);
		Format(menuline, sizeof(menuline), "%s", PlayerName);
		AddMenuItem(menu, PlayerID, menuline);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, iClient, 60);
}

public void hsql_TopSpeedPlayer(Handle owner, Handle query, const char[] error, any data)
{
	if (query == null)
	{
		LogError("Query is null!");
		return;
	}

	int iClient = GetClientOfUserId(data);
	if(!SQL_MoreRows(query))
	{
			PrintToChat(iClient, "The target was not found.");
			return;
	}


	Panel panel = CreatePanel();
	char PlayerName[40], PlayerID[40];
	int iTopSpeed = 0;
	int iTopDeflects = 0;

	while(SQL_FetchRow(query))
	{
		SQL_FetchString(query, 1, PlayerName, sizeof(PlayerName));
		SQL_FetchString(query, 0, PlayerID, sizeof(PlayerID));
		iTopSpeed = SQL_FetchInt(query, 2);
		iTopDeflects = SQL_FetchInt(query, 3);
	}

	SetPanelTitle(panel, "Speed stats");
	char buffer[255];
	Format(buffer, sizeof(buffer), "Name: %s", PlayerName);
	DrawPanelItem(panel, buffer);
	Format(buffer, sizeof(buffer), "Top speed: %i MpH", iTopSpeed);
	DrawPanelItem(panel, buffer);
	Format(buffer, sizeof(buffer), "Top deflects: %i", iTopDeflects);
	DrawPanelItem(panel, buffer);
	DrawPanelItem(panel, "Close");
	SendPanelToClient(panel, iClient, PanelHandlerNothing, 15);
	CloseHandle(panel);
}

public int PanelHandlerNothing(Handle menu, MenuAction action, int param1, int param2)
{
	// Do nothing
}

void UpdatePlayerToDB(int client) {
	char Query[255];
	Format(Query, sizeof(Query), "UPDATE topspeed SET topspeed = '%i', topdeflects = '%i' WHERE steamid = '%s' AND serverid = '%s'", Player[client].iTopSpeed, Player[client].iTopDeflects, GetSteamId(client), cServerId);
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
}


void EdgeCaseAddPlayerToDatabase(int iClient)
{
	char Query[255];
	char name[32];
	GetClientName(iClient, name, sizeof(name));
	LogMessage("Adding to database client %s", name);
	Format(Query, sizeof(Query), "INSERT INTO topspeed (steamid, name, topspeed, topdeflects, serverid) VALUES ('%s', '%s', '%i', '%i', '%s')", GetSteamId(iClient), name, Player[client].iTopSpeed, Player[client].iTopDeflects, cServerId);
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
}

public void SQL_ErrorCheckCallBack(Handle owner, Handle query, const char[] error, any data) {
	// This is just an errorcallback for function who normally don't return any data
	if (query == null) {
		SetFailState("Query failed! %s", error);
	}
}

/**
 * END: SQL Database stuff..
 */

/**
 * Menus
 */

public int hMenu_TopSpeed(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
		return;
	}

	if (action == MenuAction_Select)
	{
		char Query[255];
		char steamid[32];
		GetMenuItem(menu, param2, steamid, sizeof(steamid));
		Format(Query, sizeof(Query), "SELECT * FROM topspeed WHERE steamid = '%s' AND serverid = '%s'", steamid, cServerId);
		SQL_TQuery(db, hsql_TopSpeedPlayer, Query, GetClientUserId(param1));
		return;
	}
}

/**
 * End: Menus
 */

/**
 * Commands
 */

public Action UpdateStats(int iClients, int args)
{
	// It should look like: sm_updatetopspeeds speed deflects owner target
	// Should be hooked on "on deflfect" for the tfdb plugin we are using

	if (args < 4)
	{
		PrintToChat(iClients, "Usage: sm_updatetopspeeds speed deflects");
		return Plugin_Handled;
	}

	char arg1[128], arg2[128];

	int speed, deflections, owner, target;

	iOldSpeed = iNewSpeed;

	GetCmdArg(1, arg1, sizeof(arg1));
	speed = StringToInt(arg1, 10);
	GetCmdArg(2, arg2, sizeof(arg2));
	deflections = StringToInt(arg2, 10);
	GetCmdArg(3, arg1, sizeof(arg1));
	owner = StringToInt(arg1, 10);
	GetCmdArg(4, arg2, sizeof(arg2));
	target = StringToInt(arg2, 10);

	if (IsEntityConnectedClient(owner) && IsEntityConnectedClient(target) && !IsFakeClient(owner) && !IsFakeClient(target))
	{
		// Update owner
		if (speed > Player[owner].iTopSpeed)
		{
			Player[owner].iTopSpeed = speed;
		}

		// Update target
		if (deflections > Player[target].iTopDeflects)
		{
			Player[target].iTopDeflects = deflections;
		}
	}

	return Plugin_Handled;
}

public Action CommandTopSpeed(int iClient, int args)
{
	// Get client by args 0
	if (args < 1)
	{
		// Say top speed
		ShowTopSpeed(iClient);
		return Plugin_Handled;
	}

	// Show menu
	char strTarget[36];
	char Query[255];
	GetCmdArg(1, strTarget, sizeof(strTarget));
	Format(Query, sizeof(Query), "SELECT * FROM topspeed WHERE name LIKE '%%%s%%' AND serverid = '%s'", strTarget, cServerId);
	SQL_TQuery(db, hsql_TopSpeedPlayer, Query, GetClientUserId(iClient));
	return Plugin_Handled;
}

public Action CommandTopCurrent(int iClient, int args)
{
	// Get our self top speed from iClient
	char Query[255];
	Format(Query, sizeof(Query), "SELECT * FROM topspeed WHERE steamid = '%s' AND serverid = '%s'", GetSteamId(iClient), cServerId);
	SQL_TQuery(db, hsql_TopSpeedPlayer, Query, GetClientUserId(iClient));
	return Plugin_Handled;
}

public void ShowTopSpeed(int iClient)
{
	char Query[255];
	Format(Query, sizeof(Query), "SELECT name,steamid FROM topspeed WHERE serverid = '%s' ORDER BY topspeed DESC LIMIT 100", cServerId);
	SQL_TQuery(db, hsql_TopSpeed, Query, GetClientUserId(iClient));
}

/**
 * END: Commands
 */

/**
 * Methods
 */

char GetSteamId(int client) {
	char SteamID[32];
	if (IsEntityConnectedClient(client)) {
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID), true);
	}
	return SteamID;
}

stock bool IsEntityConnectedClient(int entity) {
	return 0 < entity <= MaxClients && IsClientInGame(entity);
}

/**
 * END: Methods
 */

/**
 * Hooks
 */

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	char Attacker[32], Victim[32];
	iNewSpeed = 0;
	iOldSpeed = 0;
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	GetClientName(victim, Victim, sizeof(Victim));
	GetClientName(attacker, Attacker, sizeof(Attacker));

	if (IsEntityConnectedClient(attacker) && IsEntityConnectedClient(victim) && !IsFakeClient(attacker) && !IsFakeClient(victim) && victim != attacker)
	{
		// Lets check if new top speed and top deflects is higher than the old one
		UpdatePlayerToDB(attacker);
		UpdatePlayerToDB(victim);
	}
}

/* Client put in server */
public void OnClientPutInServer(int iClient) {
	if (!IsEntityConnectedClient(iClient) || IsFakeClient(iClient)) return;
	UpdateOrAddToDatabase(iClient);
}

/**
 * END: Hooks
 */