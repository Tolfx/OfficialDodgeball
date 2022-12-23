#pragma semicolon 1
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <multicolors>
#pragma newdecls required

#define PHRASE_KISS_SAY "Kiss_Say"
#define PHRASE_HUG_SAY "Hug_Say"
#define PHRASE_KISS_COOLDOWN "Kiss_Cooldown"
#define PHRASE_HUG_COOLDOWN "Hug_Cooldown"
#define PHRASE_NOT_FOUND "Not_Found"
#define PHRASE_KISS_YOURSELF "Kiss_Yourself"
#define PHRASE_HUG_YOURSELF "Hug_Yourself"
#define PHRASE_HUG_BOT "Hug_Bot"
#define PHRASE_KISS_BOT "Kiss_Bot"

Handle db = INVALID_HANDLE;

enum struct PlayerKissesHugged {
	int KISS;
	int HUG;
	int LAST_KISSED;
	int LAST_HUGGED;
	int LAST_TIMED_KISSED;
	int LAST_TIMED_HUGGED;
}

ConVar g_cvarKissCooldown;
ConVar g_cvarHugCooldown;

PlayerKissesHugged Players[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "hugkiss",
	author = "Tolfx",
	description = "Hugs & Kisses plugin",
	version = "1.0.0",
	url = "https://github.com/Tolfx/OfficialDodgeball"
};

public void OnPluginStart()
{
	LoadTranslations("hugkiss.phrases.txt");
	LoadTranslations("common.phrases.txt");
	RegConsoleCmd("kiss", Command_Kiss, "Kiss a player");
	RegConsoleCmd("hug", Command_Hug, "Hug a player");
	RegAdminCmd("reload_hugkiss", Command_Reload, ADMFLAG_GENERIC, "Reloads the hugkiss plugin");

	g_cvarKissCooldown = CreateConVar("hugkiss_kiss_cooldown", "30", "Cooldown for kissing a player", _, true, 0.0);
	g_cvarHugCooldown = CreateConVar("hugkiss_hug_cooldown", "30", "Cooldown for hugging a player", _, true, 0.0);
}

public void OnConfigsExecuted()
{
	/* Start Database */
	StartDatabase();
}

// Commands

public Action Command_Reload(int iClient, int args)
{
	LoadTranslations("hugkiss.phrases.txt");
	LoadTranslations("common.phrases.txt");
	ReplyToCommand(iClient, "Reloaded hugkiss plugin");
	return Plugin_Handled;
}

public Action Command_Kiss(int iClient, int args)
{
	// We can have some difderent cases here, if it's no args
	// We can try to assume is menu we want to show
	// If we got a arg we can assume is kissing a player by name

	if (args == 0)
	{
		// Show menu
		ShowKissMenu(iClient);
		return Plugin_Handled;
	}
	else
	{
		// Try to find player by name
		char name[MAX_NAME_LENGTH];
		GetCmdArg(1, name, sizeof(name));
		int iTarget = FindTarget(iClient, name);
		if (iTarget == -1)
		{
			// Player not found
			CPrintToChat(iClient, "%t", PHRASE_NOT_FOUND, name);
			return Plugin_Handled;
		}
		else
		{
			HandleAction(iClient, iTarget, false);
		}
	}

	return Plugin_Handled;
}

public void ShowKissMenu(int iClient)
{
	// Create menu
	Menu menu = new Menu(KissMenuHandler);
	menu.SetTitle("Kiss Menu");
	menu.AddItem("0", "Top kisses", ITEMDRAW_DEFAULT);
	menu.AddItem("1", "Kiss a player", ITEMDRAW_DEFAULT);
	menu.AddItem("2", "My kisses given", ITEMDRAW_DEFAULT);
	menu.Display(iClient, MENU_TIME_FOREVER);
}

public Action Command_Hug(int iClient, int args)
{
	// We can have some difderent cases here, if it's no args
	// We can try to assume is menu we want to show
	// If we got a arg we can assume is kissing a player by name

	if (args == 0)
	{
		// Show menu
		ShowHugMenu(iClient);
		return Plugin_Handled;
	}
	else
	{
		// Try to find player by name
		char name[MAX_NAME_LENGTH];
		GetCmdArg(1, name, sizeof(name));
		int iTarget = FindTarget(iClient, name);
		if (iTarget == -1)
		{
			// Player not found
			CPrintToChat(iClient, "%t", PHRASE_NOT_FOUND, name);
			return Plugin_Handled;
		}
		else
		{
			HandleAction(iClient, iTarget, true);
		}
	}
	return Plugin_Handled;
}

public void ShowHugMenu(int iClient)
{
	// Create menu
	Menu menu = new Menu(HugMenuHandler);
	menu.SetTitle("Hug Menu");
	menu.AddItem("0", "Top hugs", ITEMDRAW_DEFAULT);
	menu.AddItem("1", "Hug a player", ITEMDRAW_DEFAULT);
	menu.AddItem("2", "My hugs given", ITEMDRAW_DEFAULT);
	menu.Display(iClient, MENU_TIME_FOREVER);
}

public void HandleAction(int iClient, int iTarget, bool isHug)
{
	// are we trying to kiss ourselves?
	if (iClient == iTarget)
	{
		CPrintToChat(iClient, "%t", isHug ? PHRASE_HUG_YOURSELF : PHRASE_KISS_YOURSELF);
		return;
	}

	if (IsFakeClient(iTarget))
	{
		CPrintToChat(iClient, "%t", isHug ? PHRASE_HUG_BOT : PHRASE_KISS_BOT);
		return;
	}

	int coolDownClient = isHug ? Players[iClient].LAST_TIMED_HUGGED : Players[iClient].LAST_TIMED_KISSED;
	int cvarCoolDown = isHug ? g_cvarHugCooldown.IntValue : g_cvarKissCooldown.IntValue;
	// Player found, let's check if we can
	if (coolDownClient + cvarCoolDown > GetTime())
	{
		// Cooldown not over
		CPrintToChat(iClient, "%t", isHug ? PHRASE_HUG_COOLDOWN : PHRASE_KISS_COOLDOWN, cvarCoolDown - (GetTime() - coolDownClient));
		return;
	}
	else
	{
		// Cooldown is over
		if (isHug)
		{
			Players[iClient].LAST_TIMED_HUGGED = GetTime();
			Players[iClient].LAST_HUGGED = iTarget;
		}
		else
		{
			Players[iClient].LAST_TIMED_KISSED = GetTime();
			Players[iClient].LAST_KISSED = iTarget;
		}
		SQL_AddToDatabase(iClient, isHug);
		return;
	}
}

public void AllPlayersMenu(int iClient, bool isHug)
{
	// We want to create a menu with all players in it in game, except ourself
	// We can use the same menu for both hug and kiss
	Menu menu = new Menu(isHug ? HugAPlayerMenuHandler : KissAPlayerMenuHandler);
	menu.SetTitle(isHug ? "Hug a player" : "Kiss a player");
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && i != iClient && !IsFakeClient(i))
		{
			char name[MAX_NAME_LENGTH];
			GetClientName(i, name, sizeof(name));
			char menuline[256];
			Format(menuline, sizeof(menuline), "%s", name);
			AddMenuItem(menu, GetSteamId(i), menuline);
		}
	}
	menu.Display(iClient, MENU_TIME_FOREVER);
}

public void UpdateTargetReciever(int iTraget, bool isHug)
{
	// We need to do some logic here, which we need to make a query first to find
	// our target
	// if player doesn't exist we need to create a new row and update it
	char Query[255];
	Format(Query, sizeof(Query), "SELECT * FROM hugkiss WHERE steamid = '%s'", GetSteamId(iTraget));
	SQL_TQuery(db, isHug ? SQL_Callback_UpdateTargetHug : SQL_Callback_UpdateTargetKiss, Query, GetClientUserId(iTraget));
}


/**
 * SQL Database stuff..
 */

void StartDatabase()
{
	char error[255], Query[255];
	if (SQL_CheckConfig("hugkiss"))
	{
		db = SQL_Connect("hugkiss", true, error, sizeof(error));
	}
	else
	{
		LogError("Could not find database config!");
		return;
	}

	SQL_LockDatabase(db);
	// We want to make a table that contains: steamid, name, kisses, hugs, hugs_received, kisses_received
	Format(Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS hugkiss (steamid VARCHAR(32), name VARCHAR(32), hugs INT, kisses INT, hugs_received INT, kisses_received INT)");
	SQL_FastQuery(db, Query);
	SQL_UnlockDatabase(db);
}

// --------------------------------------------------------------------------- //
// ------------------------------ SQL Queries -------------------------------- //
// --------------------------------------------------------------------------- //
public void SQL_AddToDatabase(int iClient, bool isHug)
{
	char Query[255];
	char name[MAX_NAME_LENGTH];
	GetClientName(iClient, name, sizeof(name));
	Format(Query, sizeof(Query), "SELECT * FROM hugkiss WHERE steamid = '%s'", GetSteamId(iClient));
	SQL_TQuery(db, isHug ? SQL_Callback_UpdateHug : SQL_Callback_UpdateKiss, Query, GetClientUserId(iClient));
}

public void SQL_Callback_UpdateTargetHug(Handle owner, Handle query, const char[] error, any data)
{
		// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	} else {
		int iClient = GetClientOfUserId(data);
		if (SQL_GetAffectedRows(query) == 0)
		{
			// No player in database, let's add player
			char Query[255];
			char name[MAX_NAME_LENGTH];
			GetClientName(iClient, name, sizeof(name));
			Format(Query, sizeof(Query), "INSERT INTO hugkiss (steamid, name, hugs, kisses, hugs_received, kisses_received) VALUES ('%s', '%s', 0, 0, 1, 0)", GetSteamId(iClient), name);
			SQL_TQuery(db, SQL_ErrorCheckCallBack, Query, GetClientUserId(iClient));
			return;
		}
		char Query[255];
		char name[MAX_NAME_LENGTH];
		GetClientName(iClient, name, sizeof(name));
		Format(Query, sizeof(Query), "UPDATE hugkiss SET hugs_received = hugs_received + 1, name = '%s' WHERE steamid = '%s'", name, GetSteamId(iClient));
		SQL_TQuery(db, SQL_ErrorCheckCallBack, Query, GetClientUserId(iClient));
	}
}

public void SQL_Callback_UpdateHug(Handle owner, Handle query, const char[] error, any data)
{
	// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	} else {
		int iClient = GetClientOfUserId(data);
		if (SQL_GetAffectedRows(query) == 0)
		{
			// No player in database, let's add player
			char Query[255];
			char name[MAX_NAME_LENGTH];
			GetClientName(iClient, name, sizeof(name));
			Format(Query, sizeof(Query), "INSERT INTO hugkiss (steamid, name, hugs, kisses, hugs_received, kisses_received) VALUES ('%s', '%s', 1, 0, 0, 0)", GetSteamId(iClient), name);
			SQL_TQuery(db, SQL_Callback_Hugged, Query, GetClientUserId(iClient));
			// We should also update the player we hugged
			UpdateTargetReciever(Players[iClient].LAST_HUGGED, true);
			return;
		}
		char Query[255];
		char name[MAX_NAME_LENGTH];
		GetClientName(iClient, name, sizeof(name));
		Format(Query, sizeof(Query), "UPDATE hugkiss SET hugs = hugs + 1, name = '%s' WHERE steamid = '%s'", name, GetSteamId(iClient));
		SQL_TQuery(db, SQL_Callback_Hugged, Query, GetClientUserId(iClient));
		// We should also update the player we hugged
		UpdateTargetReciever(Players[iClient].LAST_HUGGED, true);
	}
}

public void SQL_Callback_UpdateTargetKiss(Handle owner, Handle query, const char[] error, any data)
{
		// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	} else {
		int iClient = GetClientOfUserId(data);
		if (SQL_GetAffectedRows(query) == 0)
		{
			// No player in database, let's add player
			char Query[255];
			char name[MAX_NAME_LENGTH];
			GetClientName(iClient, name, sizeof(name));
			Format(Query, sizeof(Query), "INSERT INTO hugkiss (steamid, name, hugs, kisses, hugs_received, kisses_received) VALUES ('%s', '%s', 0, 0, 0, 1)", GetSteamId(iClient), name);
			SQL_TQuery(db, SQL_ErrorCheckCallBack, Query, GetClientUserId(iClient));
			return;
		}
		char Query[255];
		char name[MAX_NAME_LENGTH];
		GetClientName(iClient, name, sizeof(name));
		Format(Query, sizeof(Query), "UPDATE hugkiss SET kisses_received = kisses_received + 1, name = '%s' WHERE steamid = '%s'", name, GetSteamId(iClient));
		SQL_TQuery(db, SQL_ErrorCheckCallBack, Query, GetClientUserId(iClient));
	}
}

public void SQL_Callback_UpdateKiss(Handle owner, Handle query, const char[] error, any data)
{
	// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	} else {
		int iClient = GetClientOfUserId(data);
		if (SQL_GetAffectedRows(query) == 0)
		{
			// No player in database, let's add player
			char Query[255];
			char name[MAX_NAME_LENGTH];
			GetClientName(iClient, name, sizeof(name));
			Format(Query, sizeof(Query), "INSERT INTO hugkiss (steamid, name, hugs, kisses, hugs_received, kisses_received) VALUES ('%s', '%s', 0, 1, 0, 0)", GetSteamId(iClient), name);
			SQL_TQuery(db, SQL_Callback_Kissed, Query, GetClientUserId(iClient));
			UpdateTargetReciever(Players[iClient].LAST_KISSED, false);
			return;
		}
		char Query[255];
		char name[MAX_NAME_LENGTH];
		GetClientName(iClient, name, sizeof(name));
		Format(Query, sizeof(Query), "UPDATE hugkiss SET kisses = kisses + 1, name = '%s' WHERE steamid = '%s'", name, GetSteamId(iClient));
		SQL_TQuery(db, SQL_Callback_Kissed, Query, GetClientUserId(iClient));
		UpdateTargetReciever(Players[iClient].LAST_KISSED, false);
	}
}

public void SQL_Callback_Kissed(Handle owner, Handle query, const char[] error, any data)
{
	// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	} else {
		int iClient = GetClientOfUserId(data);
		int iTarget = Players[iClient].LAST_KISSED;
		char clientName[MAX_NAME_LENGTH];
		GetClientName(iClient, clientName, sizeof(clientName));
		char targetName[MAX_NAME_LENGTH];
		GetClientName(iTarget, targetName, sizeof(targetName));
		CPrintToChatAll("%t", PHRASE_KISS_SAY, clientName, targetName);
	}
}

public void SQL_Callback_Hugged(Handle owner, Handle query, const char[] error, any data)
{
	// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	} else {
		int iClient = GetClientOfUserId(data);
		int iTarget = Players[iClient].LAST_HUGGED;
		char clientName[MAX_NAME_LENGTH];
		GetClientName(iClient, clientName, sizeof(clientName));
		char targetName[MAX_NAME_LENGTH];
		GetClientName(iTarget, targetName, sizeof(targetName));
		CPrintToChatAll("%t", PHRASE_HUG_SAY, clientName, targetName);
	}
}

public void SQL_Show_Top(Handle owner, Handle query, const char[] error, any data)
{
	// Check if query is null
	if (query == null)
	{
		LogError("Query is null!");
		return;
	}
	int iClient = GetClientOfUserId(data);
 	char PlayerName[40], menuline[40];
	Menu menu = CreateMenu(PanelHandlerNothing);
	char index[2] = "0";
	while (SQL_FetchRow(query))
	{
		SQL_FetchString(query, 0, PlayerName , 40);
		int score = SQL_FetchInt(query, 1);
		Format(menuline, sizeof(menuline), "%s - %i", PlayerName, score);
		AddMenuItem(menu, index, menuline);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, iClient, 60);
}

public void SQL_My_Kisses(Handle owner, Handle query, const char[] error, any data)
{
	if (query == null)
	{
		LogError("Query is null!");
		return;
	}

	int iClient = GetClientOfUserId(data);
	if(!SQL_MoreRows(query))
	{
		return;
	}

	Panel panel = CreatePanel();
	int iKisses = 0;
	int iKissesReceived = 0;

	while(SQL_FetchRow(query))
	{
		iKisses = SQL_FetchInt(query, 0);
		iKissesReceived = SQL_FetchInt(query, 1);
	}

	SetPanelTitle(panel, "Kisses");
	char buffer[255];
	Format(buffer, sizeof(buffer), "► Kisses given: %i", iKisses);
	DrawPanelItem(panel, buffer);
	Format(buffer, sizeof(buffer), "► Kisses received: %i", iKissesReceived);
	DrawPanelItem(panel, buffer);
	DrawPanelItem(panel, "Close");
	SendPanelToClient(panel, iClient, PanelHandlerNothing, 15);

	CloseHandle(panel);
}

public void SQL_My_Hugs(Handle owner, Handle query, const char[] error, any data)
{
	if (query == null)
	{
		LogError("Query is null!");
		return;
	}

	int iClient = GetClientOfUserId(data);
	if(!SQL_MoreRows(query))
	{
		return;
	}

	Panel panel = CreatePanel();
	int iHugs = 0;
	int iHugsReceived = 0;

	while(SQL_FetchRow(query))
	{
		iHugs = SQL_FetchInt(query, 0);
		iHugsReceived = SQL_FetchInt(query, 1);
	}

	SetPanelTitle(panel, "Hugs");
	char buffer[255];
	Format(buffer, sizeof(buffer), "► Hugs given: %i", iHugs);
	DrawPanelItem(panel, buffer);
	Format(buffer, sizeof(buffer), "► Hugs received: %i", iHugsReceived);
	DrawPanelItem(panel, buffer);
	DrawPanelItem(panel, "Close");
	SendPanelToClient(panel, iClient, PanelHandlerNothing, 15);

	CloseHandle(panel);
}

public void SQL_ShowTop(int iClient, bool isHug)
{
	char Query[255];
	if (isHug)
	{
		Format(Query, sizeof(Query), "SELECT name, hugs_received FROM hugkiss ORDER BY hugs_received DESC");
		SQL_TQuery(db, SQL_Show_Top, Query, GetClientUserId(iClient));
	} else {
		Format(Query, sizeof(Query), "SELECT name, kisses_received FROM hugkiss ORDER BY kisses_received DESC");
		SQL_TQuery(db, SQL_Show_Top, Query, GetClientUserId(iClient));
	}
}

public void SQL_ShowMe(int iClient, bool isHug)
{
	char Query[255];
	if (isHug)
	{
		Format(Query, sizeof(Query), "SELECT hugs, hugs_received FROM hugkiss WHERE steamid = '%s'", GetSteamId(iClient));
		SQL_TQuery(db, SQL_My_Hugs, Query, GetClientUserId(iClient));
	} else {
		Format(Query, sizeof(Query), "SELECT kisses, kisses_received FROM hugkiss WHERE steamid = '%s'", GetSteamId(iClient));
		SQL_TQuery(db, SQL_My_Kisses, Query, GetClientUserId(iClient));
	}
}

public void SQL_ErrorCheckCallBack(Handle owner, Handle query, const char[] error, any data)
{
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

public int HugAPlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		int iClient = param1;
		char targetSteamId[255];
		GetMenuItem(menu, param2, targetSteamId, sizeof(targetSteamId));

		int iTarget = SteamIdToClient(targetSteamId);
		if (iTarget == -1)
		{
			// Player not found
			char targetName[MAX_NAME_LENGTH];
			GetClientName(iTarget, targetName, sizeof(targetName));
			CPrintToChat(iClient, "%t", PHRASE_NOT_FOUND, targetName);
			return 0;
		}

		// Hug the player
		HandleAction(iClient, iTarget, true);
	}
}

public int KissAPlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		int iClient = param1;
		char targetSteamId[255];
		GetMenuItem(menu, param2, targetSteamId, sizeof(targetSteamId));

		int iTarget = SteamIdToClient(targetSteamId);
		if (iTarget == -1)
		{
			// Player not found
			char targetName[MAX_NAME_LENGTH];
			GetClientName(iTarget, targetName, sizeof(targetName));
			CPrintToChat(iClient, "%t", PHRASE_NOT_FOUND, targetName);
			return 0;
		}

		// Hug the player
		HandleAction(iClient, iTarget, false);
	}
}

public int HugMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char strOption[8];
			menu.GetItem(param2, strOption, sizeof(strOption));
			
			int iOption = StringToInt(strOption);

			switch (iOption)
			{
				case 0:
				{
					// Top
					SQL_ShowTop(param1, true);
				}

				case 1:
				{
					// hug a player, show a menu of all players
					AllPlayersMenu(param1, true);
				}

				case 2:
				{
					// How many hugs have you given?
					SQL_ShowMe(param1, true);
				}
			}
		}
	}
}

public int KissMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char strOption[8];
			menu.GetItem(param2, strOption, sizeof(strOption));
			
			int iOption = StringToInt(strOption);

			switch (iOption)
			{
				case 0:
				{
					// Top
					SQL_ShowTop(param1, false);
				}

				case 1:
				{
					// Kiss a player, show a menu of all players
					AllPlayersMenu(param1, false);
				}

				case 2:
				{
					// How many kisses have you given?
					SQL_ShowMe(param1, false);
				}
			}
		}
	}
}

public int PanelHandlerNothing(Handle menu, MenuAction action, int param1, int param2)
{
	// Do nothing
}

// --------------------------------------------------------------------------- //
// --------------------------- Stock Commands -------------------------------- //
// --------------------------------------------------------------------------- //
char[] GetSteamId(int client) {
	char SteamID[255];
	if (IsEntityConnectedClient(client)) {
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID), true);
	}
	return SteamID;
}

int SteamIdToClient(char steamid[255])
{
	char SteamID[255];
	for (int i = 1; i <= MaxClients; i++)
	{
		Format(SteamID, sizeof(SteamID), GetSteamId(i));
		if (StrEqual(SteamID, steamid))
			return i;
	}
	return -1;
}

stock bool IsEntityConnectedClient(int entity) {
	return 0 < entity <= MaxClients && IsClientInGame(entity);
}