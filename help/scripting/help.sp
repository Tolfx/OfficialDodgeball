#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <loghelper>
#include <tf2>
#include <multicolors>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name = "help",
	author = "Tolfx",
	description = "",
	version = "1.0.0",
	url = "https://github.com/Tolfx/help"
};

char DISCORD_URL[255] = "https://discord.gg/dodgeball";
char DONATION_URL[255] = "https://donations.dodgeball.tf";

public void OnPluginStart()
{
	LogMessage("help plugin loaded!");
	RegConsoleCmd("sm_help", OnCommandHelp, "Show help menu");
	RegConsoleCmd("sm_helpmenu", OnCommandHelp, "Show help menu");
	RegConsoleCmd("sm_discord", OnCommandDiscord, "Show help menu");
	RegConsoleCmd("sm_donate", OnCommandDonate, "Show help menu");
}

public Action OnCommandDiscord(int iClient, int args)
{
	ShowMOTDPanel(iClient, "Discord", DISCORD_URL, MOTDPANEL_TYPE_URL);
	return Plugin_Handled;
}

public Action OnCommandHelp(int iClient, int args)
{
	DisplayHelpMenu(iClient);
	return Plugin_Handled;
}

public Action OnCommandDonate(int iClient, int args)
{
	SayDonateText(iClient);
	return Plugin_Handled;
}

public void SayDonateText(int client)
{
	CPrintToChat(client, "[{#95F3E3}O{#08C4CD}D{#27939D}B{default}] You can donate by going to: %s", DONATION_URL);
}

public Action OnClientSayCommand(int iClient, const char[] command, const char[] args)
{
	if(StrEqual(command, "say", false))
	{
		if(StrEqual(args, "help", false))
		{
			DisplayHelpMenu(iClient);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public void make_player_command(int client, char player_command[192]) 
{
	LogPlayerEvent(client, "say", player_command);
}

void DisplayHelpMenu(int iClient)
{
	
	Menu hMenu = new Menu(DodgeballMenuHandler);
	
	hMenu.SetTitle("Help");
	hMenu.AddItem("0", "Rank", ITEMDRAW_DEFAULT);
	hMenu.AddItem("1", "I'm stuck in spectate!", ITEMDRAW_DEFAULT);
	hMenu.AddItem("2", "Rules", ITEMDRAW_DEFAULT);
	hMenu.AddItem("3", "Top Speed", ITEMDRAW_DEFAULT);
	hMenu.AddItem("4", "Top Players", ITEMDRAW_DEFAULT);
	hMenu.AddItem("5", "Discord", ITEMDRAW_DEFAULT);
	hMenu.AddItem("6", "Donate", ITEMDRAW_DEFAULT);
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

public void ChangeClientToRandomTeam(int client)
{
	int team = GetRandomInt(2, 3);
	LogMessage("Changing client %N to team %d", client, team);
	// Change the client to the random team
	ChangeClientTeam(client, team);
}

public int DodgeballMenuHandler(Menu hMenu, MenuAction iMenuActions, int iParam1, int iParam2)
{
	switch (iMenuActions)
	{
		case MenuAction_Select :
		{
			char strOption[8];
			hMenu.GetItem(iParam2, strOption, sizeof(strOption));
			
			int iOption = StringToInt(strOption);

			switch (iOption)
			{
				case 0:
				{
					// This is for stats
					// We shall type for them by doing /stats
					make_player_command(iParam1, "/rank");
				}

				case 1:
				{
					// Check if player is spec
					if(GetClientTeam(iParam1) == 1)
					{
						LogMessage("Player is spec, changing to random team");
						// Change the player to a random team
						ChangeClientToRandomTeam(iParam1);
					}
					else
					{
						// Tell the player they are not a spectator
						ReplyToCommand(iParam1, "You are not a spectator!");
					}
				}

				case 2:
				{
					int userid = GetClientUserId(iParam1);
					ServerCommand("sm_motd #%d", userid);
				}

				case 3:
				{
					make_player_command(iParam1, "/ts");
				}

				case 4:
				{
					make_player_command(iParam1, "/top10");
				}

				case 5:
				{
					make_player_command(iParam1, "/discord");
					// Send private message to the player
					ReplyToCommand(iParam1, "Discord: %s", DISCORD_URL);
				}

				case 6:
				{
					SayDonateText(iParam1);
				}
			}
		}

		case MenuAction_End :
		{
			delete hMenu;
		}
	}

	return 0;
}