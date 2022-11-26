#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
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

public void OnPluginStart()
{
	RegConsoleCmd("tfhelp", OnCommandHelp, "help!");
}

public Action OnCommandHelp(int iClient, int args)
{
	if (iClient == 0)
	{
		ReplyToCommand(iClient, "Command is in-game only.");
		return Plugin_Handled;
	}
	
	DisplayHelpMenu(iClient);

	return Plugin_Handled;
}

void DisplayHelpMenu(int iClient)
{
	
	Menu hMenu = new Menu(DodgeballMenuHandler);
	
	hMenu.SetTitle("Help");
	hMenu.AddItem("0", "Hell?", ITEMDRAW_DEFAULT);
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
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
					ReplyToCommand(iParam1, "You are in hell!");
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