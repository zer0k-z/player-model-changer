// =========================================================== //

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <regex>
#include <clientprefs>

// ====================== DEFINITIONS ======================== //

#define MAX_MODELS 128
#define CONFIG_FILE "cfg/sourcemod/modelchooser.cfg"

// ====================== FORMATTING ========================= //

#pragma newdecls required

// ====================== VARIABLES ========================== //

enum PMData
{
	PMData_Name = 0,
	PMData_Model,
	PMData_Arms,
	PMData_Count
};

int gI_ModelCount = 0;
bool gB_AllModelsPrecached = false;

Cookie gH_Cookie;
int gI_SelectedModel[MAXPLAYERS + 1] = { -1, ... };
char gSZ_ModelData[MAX_MODELS][PMData_Count][PLATFORM_MAX_PATH];

// ====================== PLUGIN INFO ======================== //

public Plugin myinfo = 
{
	name = "ModelChooser", 
	author = "GameChaos, Sikari", 
	description = "ModelChooser with clientprefs support", 
	version = "4.1k", 
	url = "https://github.com/zer0k-z/player-model-changer"
};

// ======================= MAIN CODE ========================= //

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegConsoleCmd("sm_pm", Command_Models);
	RegConsoleCmd("sm_playermodel", Command_Models);
}

public void OnPluginStart()
{
	HookEvent("player_team", Event_OnPlayerTeam);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	gH_Cookie = new Cookie("ModelChooser-cookie", "ModelChooser cookie", CookieAccess_Private);
}

public void OnMapStart()
{
	gB_AllModelsPrecached = false;
	LoadModelsFromFile();
}

public void OnClientConnected(int client)
{
	gI_SelectedModel[client] = 0;
}

public void OnClientCookiesCached(int client)
{
	char buffer[3];
	gH_Cookie.Get(client, buffer, sizeof(buffer));
	gI_SelectedModel[client] = StringToInt(buffer);
	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		ChangeModel(client, gI_SelectedModel[client]);
	}
}


public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ChangeModel(client, gI_SelectedModel[client]);
}

public void Event_OnPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ChangeModel(client, gI_SelectedModel[client]);
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ChangeModel(client, gI_SelectedModel[client]);
}

public Action Command_Models(int client, int args)
{
	ShowModelsMenu(client);
	return Plugin_Handled;
}

void LoadModelsFromFile()
{	
	if (!FileExists(CONFIG_FILE))
	{
		SetFailState("%s does not exist!", CONFIG_FILE);
	}
	
	KeyValues config = new KeyValues("ModelChooser");
	config.ImportFromFile(CONFIG_FILE);
	
	if (config == null)
	{
		SetFailState("Failed reading %s as KeyValues, make sure it is in KeyValues format!", CONFIG_FILE);
	}

	gI_ModelCount = 1;
	
	while (config.GotoFirstSubKey() || config.GotoNextKey())
	{
		config.GetSectionName(gSZ_ModelData[gI_ModelCount][PMData_Name], sizeof(gSZ_ModelData[][]));
		config.GetString("model", gSZ_ModelData[gI_ModelCount][PMData_Model], sizeof(gSZ_ModelData[][]));
		config.GetString("arms", gSZ_ModelData[gI_ModelCount][PMData_Arms], sizeof(gSZ_ModelData[][]));
		
		bool modelSet = (!StrEqual(gSZ_ModelData[gI_ModelCount][PMData_Model], ""));
		bool armsSet = (!StrEqual(gSZ_ModelData[gI_ModelCount][PMData_Arms], ""));
		
		if (modelSet)
		{
			PrecacheModelEx(gSZ_ModelData[gI_ModelCount][PMData_Model]);
			AddFileToDownloadsTable(gSZ_ModelData[gI_ModelCount][PMData_Model]);
		}
		
		if (armsSet)
		{
			PrecacheModelEx(gSZ_ModelData[gI_ModelCount][PMData_Arms]);
			AddFileToDownloadsTable(gSZ_ModelData[gI_ModelCount][PMData_Arms]);
		}
		
		gI_ModelCount++;
	}
	
	delete config;
	gB_AllModelsPrecached = true;
}

void ChangeModel(int client, int modelIndex)
{
	if (!gB_AllModelsPrecached)
	{
		return;
	}

	if (modelIndex < 0)
	{
		return;
	}

	if (gI_SelectedModel[client] <= 0)
	{
		return;
	}
	DataPack dp = new DataPack();
	dp.WriteCell(client);
	dp.WriteCell(modelIndex);
	CreateTimer(0.2, Timer_SetModel, dp);
}

public Action Timer_SetModel(Handle timer, DataPack dp)
{
	dp.Reset();
	int client = dp.ReadCell();
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) 
	{
		delete dp;
		return;
	}
	int modelIndex = dp.ReadCell();
	SetEntityModel(client, gSZ_ModelData[modelIndex][PMData_Model]);
	SetEntPropString(client, Prop_Send, "m_szArmsModel", gSZ_ModelData[modelIndex][PMData_Arms]);
	delete dp;
}

void ShowModelsMenu(int client, int atItem = 0)
{
	Menu menu = new Menu(MenuModels, MENU_ACTIONS_ALL);
	menu.SetTitle("Player Models");
	menu.AddItem("0", "Default");
	for (int i = 1; i < gI_ModelCount; i++)
	{
		char index[12];
		IntToString(i, index, sizeof(index));
		menu.AddItem(index, gSZ_ModelData[i][PMData_Name]);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, atItem, MENU_TIME_FOREVER);
}

public int MenuModels(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[12];
		menu.GetItem(param2, info, sizeof(info));
		
		int modelSelection = StringToInt(info);
		gI_SelectedModel[param1] = modelSelection;
		if (modelSelection != 0)
		{
			ChangeModel(param1, modelSelection);
		}
		else
		{
			PrintToChat(param1, "Your model will be changed to the default model upon respawning.");
		}

		if (AreClientCookiesCached(param1))
		{
			char buffer[3];
			IntToString(modelSelection, buffer, sizeof(buffer));
			gH_Cookie.Set(param1, buffer);
		}
		ShowModelsMenu(param1, (param2 / menu.Pagination * menu.Pagination));
	}

	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

stock void PrecacheModelEx(char[] modelPath)
{
	if (!IsModelPrecached(modelPath))
	{
		PrecacheModel(modelPath, true);
	}
}

stock bool IsValidClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsValidEntity(client) && IsClientConnected(client) && IsClientInGame(client));
}