#pragma semicolon 1
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <sdktools>
#include <multicolors>

#define PLUGIN_VERSION "1.5.1"

ConVar cvarEnable;
ConVar g_hCvarServerChatTagSolo;
ConVar g_hCvarMainChatColorSolo;
ConVar g_hCvarKeywordChatColorSolo;
ConVar g_hCvarClientChatColorSolo;
ConVar gCV_Cooldown = null;

// External Plugins
ConVar g_hCvar_FewGoodMenEnable;

char g_strServerChatTagSolo[256];
char g_strMainChatColorSolo[256];
char g_strKeywordChatColorSolo[256];
char g_strClientChatColorSolo[256];

Handle redQueue = INVALID_HANDLE;
Handle blueQueue = INVALID_HANDLE;

int soloMode[MAXPLAYERS+1] = {0, ...};
bool canSoloCmd[MAXPLAYERS+1] = {true, ...};
bool hasRespawned[MAXPLAYERS+1] =  { false, ...};
bool noDamage[MAXPLAYERS+1] =  { false, ...};
int lastRespawnTime;
int lastRespawnedClient;
int lastUsed[MAXPLAYERS+1];
bool MapChanged;
bool soloRoundStart;

int deaths[MAXPLAYERS+1] = {0, ...};

public Plugin myinfo =
{
	name = "TFDB Solo",
	author = "Nanochip & soul & Tolfx",
	description = "Take on the enemy team or last remaining team on your own.",
	version = PLUGIN_VERSION,
	url = "N/A"
};

public void OnPluginStart()
{
	CreateConVar("tfdb_solo_version", PLUGIN_VERSION, "TFDB Solo Version", FCVAR_SPONLY|FCVAR_UNLOGGED|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hCvarServerChatTagSolo = CreateConVar("tf_dodgeball_servertag", "[{#95F3E3}O{#08C4CD}D{#27939D}B{#ffffff}]", "Tag that appears at the start of each chat announcement.", FCVAR_PROTECTED);
	g_hCvarMainChatColorSolo = CreateConVar("tf_dodgeball_maincolor", "{WHITE}", "Color assigned to the majority of the words in chat announcements.");
	g_hCvarKeywordChatColorSolo = CreateConVar("tf_dodgeball_keywordcolor", "{DARKOLIVEGREEN}", "Color assigned to the most important words in chat announcements.", FCVAR_PROTECTED);
	g_hCvarClientChatColorSolo = CreateConVar("tf_dodgeball_clientwordcolor", "{ORANGE}", "Color assigned to the client in chat announcements.", FCVAR_PROTECTED);
	cvarEnable = CreateConVar("tfdb_solo_enable", "1", "Enable the plugin? 1 = Yes, 0 = No.", 0, true, 0.0, true, 1.0);
	gCV_Cooldown = CreateConVar("tfdb_solo_cooldown", "160", "[DPA-Discord] Cooldown time between messages in seconds", FCVAR_PROTECTED | FCVAR_DONTRECORD);
	
	RegConsoleCmd("sm_solo", Cmd_Solo, "Enable/disable solo modes via a menu.");
	
	redQueue = CreateArray();
	blueQueue = CreateArray();
	
	HookConVarChange(g_hCvarServerChatTagSolo, tf2solo_hooks);
	HookConVarChange(g_hCvarMainChatColorSolo, tf2solo_hooks);
	HookConVarChange(g_hCvarKeywordChatColorSolo, tf2solo_hooks);
	HookConVarChange(g_hCvarClientChatColorSolo, tf2solo_hooks);

	g_hCvar_FewGoodMenEnable = FindConVar("sm_fgm_enabled");
	if(g_hCvar_FewGoodMenEnable != null)
	{
		HookConVarChange(g_hCvar_FewGoodMenEnable, ConVar_ListenToChange);
	}
	
	GetConVarString(g_hCvarServerChatTagSolo, g_strServerChatTagSolo, sizeof(g_strServerChatTagSolo));
	GetConVarString(g_hCvarMainChatColorSolo, g_strMainChatColorSolo, sizeof(g_strMainChatColorSolo));
	GetConVarString(g_hCvarKeywordChatColorSolo, g_strKeywordChatColorSolo, sizeof(g_strKeywordChatColorSolo));
	GetConVarString(g_hCvarClientChatColorSolo, g_strClientChatColorSolo, sizeof(g_strClientChatColorSolo));
	
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("arena_round_start", Event_RoundStart, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("arena_win_panel", Event_RoundEnd);
	HookEvent("teamplay_round_start", Event_RoundSetup, EventHookMode_Pre);
}

public void tf2solo_hooks(Handle convar, const char[] oldValue, const char[] newValue)
{
	if(convar == g_hCvarServerChatTagSolo)
		strcopy(g_strServerChatTagSolo, sizeof(g_strServerChatTagSolo), newValue);
	if(convar == g_hCvarMainChatColorSolo)
		strcopy(g_strMainChatColorSolo, sizeof(g_strMainChatColorSolo), newValue);
	if(convar == g_hCvarKeywordChatColorSolo)
		strcopy(g_strKeywordChatColorSolo, sizeof(g_strKeywordChatColorSolo), newValue);
}

public void ConVar_ListenToChange(Handle convar, const char[] oldValue, const char[] newValue)
{
	if(g_hCvar_FewGoodMenEnable != null && g_hCvar_FewGoodMenEnable.BoolValue == true)
	{
		cvarEnable.BoolValue = false;
		return;
	}

	cvarEnable.BoolValue = true;
}


public Action Cmd_Solo(int client, int args)
{
	//0 = Unassigned, 1 = Spec, 2 = Red, 3 = Blue.
	if (!IsClientInGame(client)) return Plugin_Handled;
	int currentTime = GetTime();
	if(currentTime - lastUsed[client] < GetConVarInt(gCV_Cooldown)) {
		CReplyToCommand(client, "%s %sPlease wait %s%i %sseconds before using the command again. ", g_strServerChatTagSolo, g_strMainChatColorSolo, g_strKeywordChatColorSolo, GetConVarInt(gCV_Cooldown) - (currentTime - lastUsed[client]), g_strMainChatColorSolo);
		return Plugin_Handled;
	}

	lastUsed[client] = currentTime;
	int team = GetClientTeam(client);
	if (team == 1 || team == 0)
	{
		CReplyToCommand(client, "%s %sYou must join RED or BLU before you can use this command.", g_strServerChatTagSolo, g_strMainChatColorSolo);
		return Plugin_Handled;
	}
	
	if (soloMode[client] == 0)
	{
		if (!canSoloCmd[client] || IsClientObserver(client))
		{
			CReplyToCommand(client, "%s %sSorry, you may not use this command right now.", g_strServerChatTagSolo, g_strMainChatColorSolo);
			return Plugin_Handled;
		}
		
		Menu menu = new Menu(Cmd_Solo_Handler, MENU_ACTIONS_ALL);
		
		menu.SetTitle("TFDB Solo Menu");
		
		menu.AddItem("0", "Solo vs. Enemy Team");
		menu.AddItem("1", "Solo vs. All");
		
		menu.ExitButton = true;
		menu.Display(client, 3);
		
		// Check if all of the other players on the team have solo mode activated.
		if (team == 2 && GetTeamClientCount(2)-1 == GetArraySize(redQueue))
		{
			CReplyToCommand(client, "%s %sThe rest of your team already has solo mode activated, therefore you may not activate it.", g_strServerChatTagSolo, g_strMainChatColorSolo);
			return Plugin_Handled;
		}
		if (team == 3 && GetTeamClientCount(3)-1 == GetArraySize(blueQueue))
		{
			CReplyToCommand(client, "%s %sThe rest of your team already has solo mode activated, therefore you may not activate it.", g_strServerChatTagSolo, g_strMainChatColorSolo);
			return Plugin_Handled;
		}
	}
	else
	{
		// Remove the client from the queue
		if (team == 2)
		{
			int index = FindValueInArray(redQueue, GetClientUserId(client));
			if (index != -1) RemoveFromArray(redQueue, index);
		}
		if (team == 3)
		{
			int index = FindValueInArray(blueQueue, GetClientUserId(client));
			if (index != -1) RemoveFromArray(blueQueue, index);
		}
		
		// Deactivated Solo Mode
		soloMode[client] = 0;
		canSoloCmd[client] = true;
		
		CPrintToChatAll("%s %sDeactivated Solo Mode on %s%N.", g_strServerChatTagSolo, g_strMainChatColorSolo, g_strClientChatColorSolo, client, g_strMainChatColorSolo);
	}
	
	return Plugin_Handled;
}

public int Cmd_Solo_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Start:
		{
			// It's important to log anything in any way, the best is printtoserver, but if you just want to log to client to make it easier to get progress done, feel free.
			PrintToServer("Displaying menu"); // Log it
		}
		
		case MenuAction_Display:
		{
			PrintToServer("Client %d was sent menu with panel %x", param1, param2); // Log so you can check if it gets sent.
		}
		
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));
			
			int team = GetClientTeam(param1);
			
			switch (param2)
			{
				case 0:
				{
					
					// Add the client's USERID to the team queue
					if (team == 2) PushArrayCell(redQueue, GetClientUserId(param1));
					if (team == 3) PushArrayCell(blueQueue, GetClientUserId(param1));
					
				
					// Activated Solo Mode
					soloMode[param1] = 1;
					
					
					CPrintToChatAll("%s %s%N %swill fight the enemy team solo.", g_strServerChatTagSolo, g_strClientChatColorSolo, param1, g_strMainChatColorSolo);
				}
				case 1:
				{
					
					// Add the client's USERID to the team queue
					if (team == 2) PushArrayCell(redQueue, GetClientUserId(param1));
					if (team == 3) PushArrayCell(blueQueue, GetClientUserId(param1));
					
					
					// Activated Solo Mode
					soloMode[param1] = 2;
					
					CPrintToChatAll("%s %s%N %swill fight the enemy team solo.", g_strServerChatTagSolo, g_strClientChatColorSolo, param1, g_strMainChatColorSolo);
				}
			}
		}
		
		case MenuAction_Cancel:
		{
			PrintToServer("Client %d's menu was cancelled for reason %d", param1, param2); // Logging once again.
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
		
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			menu.GetItem(param2, info, sizeof(info), style);
		}
		
		case MenuAction_DisplayItem:
		{
			char info[32];
			menu.GetItem(param2, info, sizeof(info));
		}
	}
}

public void OnClientDisconnect(int client)
{
	if (!GetConVarBool(cvarEnable)) return;
	if (IsClientConnected(client) && IsFakeClient(client)) return;
	if (!IsClientInGame(client)) return;
	
	// If the client was in RED or BLU queue, remove them from it.
	int team = GetClientTeam(client);
	if (team == 2)
	{
		int index = FindValueInArray(redQueue, GetClientUserId(client));
		if (index != -1) RemoveFromArray(redQueue, index);
	}
	if (team == 3)
	{
		int index = FindValueInArray(blueQueue, GetClientUserId(client));
		if (index != -1) RemoveFromArray(blueQueue, index);
	}
}

public void OnMapEnd()
{
	if (!GetConVarBool(cvarEnable)) return;
	MapChanged = true;
}

public void OnMapStart()
{
	if (!GetConVarBool(cvarEnable)) return;
	
	// Clear the queues OnMapStart
	ClearArray(redQueue);
	ClearArray(blueQueue);
	
	CreateTimer(10.0, Timer_MapStart);
	
	soloRoundStart = false;
}

public Action Timer_MapStart(Handle timer)
{
	MapChanged = false;
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if (!GetConVarBool(cvarEnable)) return;
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	//if (IsFakeClient(client)) return;
	
	// Return 0 if there is no one in the queues.
	int team = GetClientTeam(client);
	if (team == 2 && GetArraySize(redQueue) == 0 && GetSoloVsLastTeamPlayerCount() == 0) return;
	if (team == 3 && GetArraySize(blueQueue) == 0 && GetSoloVsLastTeamPlayerCount() == 0) return;
	
	// When the last player alive dies on red, commence the red solo queue.
	if (team == 2 && GetRedAlivePlayerCount() == 1)
	{
		//PrintToServer("Last player alive on red has died.");
		
		SwapSoloPlayersTeam(team);
		
		// If the last player who died was not in the queue then do:
		if (FindValueInArray(redQueue, GetClientUserId(client)) == -1)
		{
			//PrintToServer("Respawning first solo player for red.");
			int firstClient = GetClientOfUserId(GetArrayCell(redQueue, 0));
			// Respawn the first client.
			if (!hasRespawned[firstClient])
			{
				TF2_RespawnPlayer(firstClient);
				hasRespawned[firstClient] = true;
				lastRespawnTime = GetGameTickCount();
				lastRespawnedClient = firstClient;
				// Make sure they don't take any pre-existing damage on spawn.
				SDKHook(firstClient, SDKHook_OnTakeDamage, OnTakeDamage);
				noDamage[firstClient] = true;
				// Alert the client that it is their turn.
				ClientCommand(firstClient, "playgamesound \"%s\"", "ambient\\alarms\\doomsday_lift_alarm.wav");
			}
		}
		// If the last player who died was in the queue, then do:
		else
		{
			int nextIndex = FindValueInArray(redQueue, GetClientUserId(client)) + 1;
			// If there are no more people in the queue, return 0.
			if (nextIndex >= GetArraySize(redQueue)) return;
			else
			{
				//PrintToServer("Respawning next solo player for red.");
				int nextClient = GetClientOfUserId(GetArrayCell(redQueue, nextIndex));
				// Respawn the next player in the queue
				if (!hasRespawned[nextClient])
				{
					TF2_RespawnPlayer(nextClient);
					hasRespawned[nextClient] = true;
					lastRespawnTime = GetGameTickCount();
					lastRespawnedClient = nextClient;
					// Make sure they don't take any pre-existing damage on spawn.
					SDKHook(nextClient, SDKHook_OnTakeDamage, OnTakeDamage);
					noDamage[nextClient] = true;
					// Alert the client who was just respawned
					ClientCommand(nextClient, "playgamesound \"%s\"", "ambient\\alarms\\doomsday_lift_alarm.wav");
				}
			}
		}
	}
	// Same function as red queue above ^, except for blue queue.
	if (team == 3 && GetBlueAlivePlayerCount() == 1)
	{
		//PrintToServer("Last player alive on blue has died.");
		
		SwapSoloPlayersTeam(team);
		
		if (FindValueInArray(blueQueue, GetClientUserId(client)) == -1)
		{
			//PrintToServer("Respawning first solo player for blue.");
			int firstClient = GetClientOfUserId(GetArrayCell(blueQueue, 0));
			if (!hasRespawned[firstClient])
			{
				TF2_RespawnPlayer(firstClient);
				hasRespawned[firstClient] = true;
				lastRespawnTime = GetGameTickCount();
				lastRespawnedClient = firstClient;
				SDKHook(firstClient, SDKHook_OnTakeDamage, OnTakeDamage);
				noDamage[firstClient] = true;
				ClientCommand(firstClient, "playgamesound \"%s\"", "ambient\\alarms\\doomsday_lift_alarm.wav");
			}
		}
		else
		{
			int nextIndex = FindValueInArray(blueQueue, GetClientUserId(client)) + 1;
			if (nextIndex >= GetArraySize(blueQueue)) return;
			else
			{
				//PrintToServer("Respawning next solo player for blue.");
				int nextClient = GetClientOfUserId(GetArrayCell(blueQueue, nextIndex));
				if (!hasRespawned[nextClient])
				{
					TF2_RespawnPlayer(nextClient);
					hasRespawned[nextClient] = true;
					lastRespawnTime = GetGameTickCount();
					lastRespawnedClient = nextClient;
					SDKHook(nextClient, SDKHook_OnTakeDamage, OnTakeDamage);
					noDamage[nextClient] = true;
					ClientCommand(nextClient, "playgamesound \"%s\"", "ambient\\alarms\\doomsday_lift_alarm.wav");
				}
			}
		}
	}
	
	if (soloRoundStart)
	{
		if (team == 2)
		{
			for (int i = 0; i < GetArraySize(redQueue); i++)
			{
				int queuedClient = GetClientOfUserId(GetArrayCell(redQueue, i));
				if (deaths[queuedClient] > 0 && deaths[queuedClient] <= 5)
				{
					ClientCommand(queuedClient, "playgamesound \"vo\\announcer_begins_%dsec.mp3\"", deaths[queuedClient]);
					deaths[queuedClient]--;
				}
			}
		}
		
		if (team == 3)
		{
			for (int i = 0; i < GetArraySize(blueQueue); i++)
			{
				int queuedClient = GetClientOfUserId(GetArrayCell(blueQueue, i));
				if (deaths[queuedClient] > 0 && deaths[queuedClient] <= 5)
				{
					ClientCommand(queuedClient, "playgamesound \"vo\\announcer_begins_%dsec.mp3\"", deaths[queuedClient]);
					deaths[queuedClient]--;
				}
			}
		}
	}
}

public void Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	soloRoundStart = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		canSoloCmd[i] = false;
		hasRespawned[i] = false;
	}
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.3, T_RoundStart);
}

public void Event_RoundSetup(Handle event, const char[] name, bool dontBroadcast)
{
	soloRoundStart = true;
	for (int i = 1; i <= MaxClients; i++)
	{
		canSoloCmd[i] = true;
		hasRespawned[i] = false;
	}
}

public Action T_RoundStart(Handle timer)
{
	if (!GetConVarBool(cvarEnable)) return;
	if (GetTeamClientCount(2) <= 1 && GetTeamClientCount(3) <= 1) return;
	// Activate the use of enabling solo when the round starts. This helps to prevent any exploits whenever a player is dead.
	bool hasNames = false;
	char names[1024];
	for (int i = 1; i < MaxClients; i++)
	{
		canSoloCmd[i] = false;
		char name[32];
		if ((soloMode[i] == 1 || soloMode[i] == 2) && IsClientInGame(i))
		{
			SDKHooks_TakeDamage(i, i, i, 450.0);
			GetClientName(i, name, sizeof(name));
			Format(names, sizeof(names), "%s %s,", names, name);
			hasNames = true;
		}
	}
	if (hasNames)
	{
		CPrintToChatAll("%s %sLonely Players%s: %s%s", g_strServerChatTagSolo, g_strKeywordChatColorSolo, g_strMainChatColorSolo, g_strClientChatColorSolo, names);
	}
	
	soloRoundStart = true;
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (soloMode[i] == 1 || soloMode[i] == 2)
		{
			if (GetClientTeam(i) == 2)
			{
				deaths[i] = GetRedAlivePlayerCount() + FindValueInArray(redQueue, GetClientUserId(i))-1;
			}
			if (GetClientTeam(i) == 3)
			{
				deaths[i] = GetBlueAlivePlayerCount() + FindValueInArray(blueQueue, GetClientUserId(i))-1;
			}
		}
	}
}

public void Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
	//PrintToServer("Event_PlayerTeam called.");
	
	if (!GetConVarBool(cvarEnable)) return;
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsClientConnected(client) && IsFakeClient(client)) return;
	if (soloMode[client] == 1 || soloMode[client] == 2)
	{
		int team = GetEventInt(event, "team");
		int oldTeam = GetEventInt(event, "oldteam");
		// If the player switched to spectator, remove them from the queue.
		if (team == 0)
		{
			if (oldTeam == 2)
			{
				int index = FindValueInArray(redQueue, GetClientUserId(client));
				if (index != -1) RemoveFromArray(redQueue, index);
				soloMode[client] = 0;
			}
			if (oldTeam == 3)
			{
				int index = FindValueInArray(blueQueue, GetClientUserId(client));
				if (index != -1) RemoveFromArray(blueQueue, index);
				soloMode[client] = 0;
			}
		}
		// If the player switched from BLU to RED, transfer their userid from blueQueue to redQueue.
		if (team == 2 && oldTeam == 3)
		{
			int index = FindValueInArray(blueQueue, GetClientUserId(client));
			if (index != -1) RemoveFromArray(blueQueue, index);
			
			PushArrayCell(redQueue, GetClientUserId(client));
		}
		// If the player switched from RED to BLUE, transfer their userid from redQueue to blueQueue.
		if (team == 3 && oldTeam == 2)
		{
			int index = FindValueInArray(redQueue, GetClientUserId(client));
			if (index != -1) RemoveFromArray(redQueue, index);
			
			PushArrayCell(blueQueue, GetClientUserId(client));
		}
	}
}

public void OnGameFrame()
{
	if (!GetConVarBool(cvarEnable)) return;
	
	// Make sure the last respawned player only has godmode for 1 tick.
	if (lastRespawnedClient != 0 && IsClientConnected(lastRespawnedClient) && IsPlayerAlive(lastRespawnedClient) && noDamage[lastRespawnedClient] && GetGameTickCount() > lastRespawnTime)
	{
		SDKUnhook(lastRespawnedClient, SDKHook_OnTakeDamage, OnTakeDamage);
	}
	
	// If there are is less than or equal to one person on each team, clear the solo queues and disable solo command.
	if (!MapChanged && GetTeamClientCountWithBots(2) <= 1 && GetTeamClientCountWithBots(3) <= 1)
	{
		if (GetArraySize(redQueue) != 0) ClearArray(redQueue);
		if (GetArraySize(blueQueue) != 0) ClearArray(blueQueue);
		for (int i = 1; i < MaxClients; i++)
		{
			if (soloMode[i] == 1 || soloMode[i] == 2) soloMode[i] = 0;
			if (canSoloCmd[i]) canSoloCmd[i] = false;
		}
	}
	if (!MapChanged && GetTeamClientCountWithBots(2) > 0 && GetTeamClientCountWithBots(2) == GetArraySize(redQueue))
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (soloMode[i] == 1 || soloMode[i] == 2) soloMode[i] = 0;
			if (canSoloCmd[i]) canSoloCmd[i] = false;
		}
		
		ClearArray(redQueue);
		//PrintToServer("redQueue cleared.");
		PrintToChatAll("[SOLO] Cleared red team's solo queue because somehow everyone had solomode enabled.");
	}
	if (!MapChanged && GetTeamClientCountWithBots(3) > 0 && GetTeamClientCountWithBots(3) == GetArraySize(blueQueue))
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (soloMode[i] == 1 || soloMode[i] == 2) soloMode[i] = 0;
			if (canSoloCmd[i]) canSoloCmd[i] = false;
		}
		
		ClearArray(blueQueue);
		//PrintToServer("blueQueue cleared.");
		PrintToChatAll("[SOLO] Cleared blue team's solo queue because somehow everyone had solomode enabled.");
	}
}

// For cases where a solo player spawns and takes splash damage meant for an already dead player.
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
  if (IsPlayerAlive(victim) && (soloMode[victim] == 1 || soloMode[victim] == 2))
  {
    damage = 0.0;
  }
  
  SDKUnhook(victim, SDKHook_OnTakeDamage, OnTakeDamage);
  noDamage[victim] = false;
  return Plugin_Changed;
}

// Really basic stocks...
stock int GetRedAlivePlayerCount()
{
	int alive = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) /*&& !IsFakeClient(i)*/ && IsPlayerAlive(i) && GetClientTeam(i) == 2) 
		{
			alive++;
		}
	}
	return alive;
}

stock int GetBlueAlivePlayerCount()
{
	int alive = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) /*&& !IsFakeClient(i)*/ && IsPlayerAlive(i) && GetClientTeam(i) == 3) 
		{
			alive++;
		}
	}
	return alive;
}

stock int SwapSoloPlayersTeam(int last_team_index)
{
	if (last_team_index == 2)
	{
		for (int i = 0; i < GetArraySize(blueQueue); i++)
		{
			int queuedClient = GetClientOfUserId(GetArrayCell(blueQueue, i));
			
			if (soloMode[queuedClient] == 2 && !IsPlayerAlive(queuedClient))
			{
				//int index = FindValueInArray(blueQueue, GetClientUserId(queuedClient));
				//if (index != -1) RemoveFromArray(blueQueue, index);
				
				//PrintToServer("Removed solo player from blue queue.");
				
				//PushArrayCell(redQueue, GetClientUserId(queuedClient));
				
				TF2_ChangeClientTeam(queuedClient, TFTeam_Red);
				//char clientname[256];
				//GetClientName(queuedClient, clientname, sizeof(clientname));
				//SendPlayer_TeamMessage(queuedClient, 2, 3, false, false, true, clientname);
			}
		}
	}
	
	if (last_team_index == 3)
	{
		for (int i = 0; i < GetArraySize(redQueue); i++)
		{
			int queuedClient = GetClientOfUserId(GetArrayCell(redQueue, i));
			
			if (soloMode[queuedClient] == 2 && !IsPlayerAlive(queuedClient))
			{
				//int index = FindValueInArray(redQueue, GetClientUserId(queuedClient));
				//if (index != -1) RemoveFromArray(redQueue, index);
				
				//PrintToServer("Removed solo player from red queue.");
				
				//PushArrayCell(blueQueue, GetClientUserId(queuedClient));
				
				TF2_ChangeClientTeam(queuedClient, TFTeam_Blue);
				//char clientname[256];
				//GetClientName(queuedClient, clientname, sizeof(clientname));
				//SendPlayer_TeamMessage(queuedClient, 3, 2, false, false, true, clientname);
			}
		}
	}
}

stock int GetSoloVsLastTeamPlayerCount()
{
	int count = 0;
	
	for (int i = 0; i < GetArraySize(blueQueue); i++)
	{
		int queuedClient = GetClientOfUserId(GetArrayCell(blueQueue, i));
		
		if (soloMode[queuedClient] == 2)
		{
			count++;
		}
	}
	
	for (int i = 0; i < GetArraySize(redQueue); i++)
	{
		int queuedClient = GetClientOfUserId(GetArrayCell(redQueue, i));
		
		if (soloMode[queuedClient] == 2)
		{
			count++;
		}
	}
	
	return count;
}

stock int GetTeamClientCountWithBots(int team)
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			count++;
		}
	}
	
	return count;
}