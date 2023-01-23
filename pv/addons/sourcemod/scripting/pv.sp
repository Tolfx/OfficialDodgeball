#pragma semicolon 1
#include <sourcemod>
#include <multicolors>
#include <tf2attributes>
#pragma newdecls required

#define PYROVISION_ATTRIBUTE "vision opt in flags"

enum struct Players
{
  int hasPyroVision,
}

Players player[MaxClients];

public Plugin myinfo =
{
	name = "PyroVision",
	author = "Tolfx",
	description = "Enables / Disables the Pyrovision effect for Pyros",
	version = "0.0.1",
	url = "https://github.com/Tolfx/OfficialDodgeball"
};

public void OnPluginStart()
{
	LoadTranslations("pv.phrases.txt");
  
  RegConsoleCmd("pv", Command_PyroVision, "Enables / Disables the Pyrovision effect for Pyros");
}

public Action Command_PyroVision(int client, int args)
{
  // Any class can use this command
  // We just must validate that their are a real player and is in game
  SetPyroVision(client);
  return Plugin_Handled;
}

public void SetPyroVision(int client)
{
  if (player[client].hasPyroVision == 0)
  {
    player[client].hasPyroVision = 1;
    TF2Attrib_SetByName(client, PYROVISION_ATTRIBUTE, 1.0);
    CPrintToChat(client, "%t", "PyroVision_Enabled");
  }
  else
  {
    player[client].hasPyroVision = 0;
    TF2Attrib_RemoveByName(client, PYROVISION_ATTRIBUTE);
    CPrintToChat(client, "%t", "PyroVision_Disabled");
  }
}
