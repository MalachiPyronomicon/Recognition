/*
* Gives those donators the recognition they deserve :)
* 
* Changelog:
* 
* v0.3 - release
* v0.4 - Enable/ disable in donator > sprite menu/ proper error without interface
* v.05 - Expanded to support multiple sprites/ fixed SetParent error
* 0.5.3 - added extra custom sprites, changed to ngc subdirectory (Malachi)
* 0.5.4 - added menu item defines & changed them to more user friendly, more sprites (Malachi)
* 0.5.5 - added donator health boost on win
* 0.5.6 - added dead donator respawn on win, fixed heart sprite
* 0.5.7 - removed respawn - didnt work for some reason
* 0.5.8 - added speed boost
* 0.5.9 Debug - print msg to server
* 0.5.10 Fixed not remembering sprites over 9th
* 0.5.11 added sprites
* 0.5.12 removed nonfunctional SPRITE_VELOCITY_SCALE
* 0.5.13b added test invisibility func
* 0.5.14 removed test functions
* 0.5.15 - removed banner function, seperated to its own plugin
* 0.5.16 - cleanup g_EntList on map end
* 0.5.17 - move further stuff to seperate Banner plugin
*
*/

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <donator>
#include <clientprefs>

#pragma semicolon 1

#define PLUGIN_VERSION	"0.5.17"


// These define the text players see in the donator menu
#define MENUTEXT_DONATOR_SPRITE		"Above-Player Icon"


// Health boost amount given to donators on map win
#define DONATOR_HEALTH_BOOST 1800

//Supports multiple sprites
#define TOTAL_SPRITE_FILES 17

new gVelocityOffset;

new const String:szSpriteNames[TOTAL_SPRITE_FILES][] =
{
	"Money Sign",
	"Money Sign / Cloud",
	"Eyeball",
	"Banana",
	"Pirate Flag",
	"Royal Crown",
	"LOL Face",
	"Monkey w/ Banana",
	"Light Bulb",
	"Smiley Face",
	"Heart",
	"Doggy Snoozing",
	"Stop Sign",
	"Umbrella",
	"Whale",
	"!",
	"Nyan Cat"
};


//NOTE: Path to the filename ONLY (vtf/vmt added in plugin)
new const String:szSpriteFiles[TOTAL_SPRITE_FILES][] = 
{
	"materials/custom/ngc/ngc01",
	"materials/custom/ngc/ngc02",
	"materials/custom/ngc/ngc03",
	"materials/custom/ngc/ngc04",
	"materials/custom/ngc/ngc05",
	"materials/custom/ngc/ngc06",
	"materials/custom/ngc/ngc07",
	"materials/custom/ngc/ngc08",
//	"materials/custom/ngc/ngc09",
	"materials/custom/ngc/ngc18",
	"materials/custom/ngc/ngc10",
//	"materials/custom/ngc/ngc11",
	"materials/custom/ngc/ngc17",
	"materials/custom/ngc/ngc12",
	"materials/custom/ngc/ngc13",
//	"materials/custom/ngc/ngc14",
	"materials/custom/ngc/ngc19",
	"materials/custom/ngc/ngc15",
	"materials/custom/ngc/ngc16",
	"materials/custom/ngc/ngc20"
};


new g_EntList[MAXPLAYERS + 1];
new g_bIsDonator[MAXPLAYERS + 1];
new bool:g_bRoundEnded;
new Handle:g_SpriteShowCookie = INVALID_HANDLE;

new g_iShowSprite[MAXPLAYERS + 1];


public Plugin:myinfo = 
{
	name = "Donator Recognition",
	author = "Nut",
	description = "Give donators the recognition they deserve.",
	version = PLUGIN_VERSION,
	url = "http://www.lolsup.com/tf2"
}


public OnPluginStart()
{
	CreateConVar("basicdonator_recog_v", PLUGIN_VERSION, "Donator Recognition Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	HookEventEx("teamplay_round_start", hook_Start, EventHookMode_PostNoCopy);
	HookEventEx("arena_round_start", hook_Start, EventHookMode_PostNoCopy);
	HookEventEx("teamplay_round_win", hook_Win, EventHookMode_PostNoCopy);
	HookEventEx("arena_win_panel", hook_Win, EventHookMode_PostNoCopy);
	HookEventEx("player_death", event_player_death, EventHookMode_Post);
	
	g_SpriteShowCookie = RegClientCookie("donator_spriteshow", "Which donator sprite to show.", CookieAccess_Private);
	
	gVelocityOffset = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
}


public OnAllPluginsLoaded()
{
	if(!LibraryExists("donator.core"))
		SetFailState("Unabled to find plugin: Basic Donator Interface");

	Donator_RegisterMenuItem(MENUTEXT_DONATOR_SPRITE, SpriteControlCallback);
}


public OnMapStart()
{
	decl String:szBuffer[128];
	for (new i = 0; i < TOTAL_SPRITE_FILES; i++)
	{
		FormatEx(szBuffer, sizeof(szBuffer), "%s.vmt", szSpriteFiles[i]);
		PrecacheGeneric(szBuffer, true);
		AddFileToDownloadsTable(szBuffer);
		FormatEx(szBuffer, sizeof(szBuffer), "%s.vtf", szSpriteFiles[i]);
		PrecacheGeneric(szBuffer, true);
		AddFileToDownloadsTable(szBuffer);
	}
}


// Cleanup 
public OnMapEnd()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		g_EntList[i] = 0;
	}
}


public OnPostDonatorCheck(iClient)
{
	new String:szBuffer[256];

	if (!IsPlayerDonator(iClient)) return;
	
	g_bIsDonator[iClient] = true;
	g_iShowSprite[iClient] = 1;
	
	if (AreClientCookiesCached(iClient))
	{		
		GetClientCookie(iClient, g_SpriteShowCookie, szBuffer, sizeof(szBuffer));
		
		if (strlen(szBuffer) > 0)
			g_iShowSprite[iClient] = StringToInt(szBuffer);
	}
	
}


public OnClientDisconnect(iClient)
	g_bIsDonator[iClient] = false;


public hook_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		if (!g_bIsDonator[i]) continue;

		KillSprite(i);
	}
	g_bRoundEnded = false;
}


public hook_Win(Handle:event, const String:name[], bool:dontBroadcast)
{	
	decl String:szBuffer[128];
	for(new i = 1; i <= MaxClients; i++)
	{
		// Weed out Observers and Not-In-Game
		if (!IsClientInGame(i) || IsClientObserver(i)) continue;
		
		// Weed out non-donators
		if (!g_bIsDonator[i]) continue;
		
		// Respawn dead donators
		if (!IsPlayerAlive(i)) continue;

		if (g_iShowSprite[i] > 0)
		{
			if (g_iShowSprite[i] > TOTAL_SPRITE_FILES) g_iShowSprite[i] = TOTAL_SPRITE_FILES - 1;
			FormatEx(szBuffer, sizeof(szBuffer), "%s.vmt", szSpriteFiles[g_iShowSprite[i]-1]);
			CreateSprite(i, szBuffer, 25.0);
		}
		
		// Give player health boost
		SetEntityHealth(i, DONATOR_HEALTH_BOOST);
		
		// Give player speed boost
		SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", 400.0);
		
	}
	g_bRoundEnded = true;
}


public Action:event_player_death(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!g_bRoundEnded) return Plugin_Continue;
	KillSprite(GetClientOfUserId(GetEventInt(event, "userid")));

	return Plugin_Continue;
}


public DonatorMenu:SpriteControlCallback(iClient) Panel_SpriteControl(iClient);


public Action:Panel_SpriteControl(iClient)
{
	new Handle:menu = CreateMenu(SpriteControlSelected);
	SetMenuTitle(menu,"Donator: Sprite Control:");
	
	if (g_iShowSprite[iClient] > 0)
		AddMenuItem(menu, "0", "Disable Sprite", ITEMDRAW_DEFAULT);
	else
		AddMenuItem(menu, "0", "Disable Sprite", ITEMDRAW_DISABLED);
	
	decl String:szItem[4];
	for (new i = 0; i < TOTAL_SPRITE_FILES; i++)
	{
		FormatEx(szItem, sizeof(szItem), "%i", i+1);	//need to offset the menu items by one since we added the enable / disable outside of the loop
		if (g_iShowSprite[iClient]-1 != i)
			AddMenuItem(menu, szItem, szSpriteNames[i], ITEMDRAW_DEFAULT);
		else
			AddMenuItem(menu, szItem, szSpriteNames[i],ITEMDRAW_DISABLED);
	}
	DisplayMenu(menu, iClient, 20);
}


public SpriteControlSelected(Handle:menu, MenuAction:action, param1, param2)
{
	decl String:tmp[32], iSelected;
	GetMenuItem(menu, param2, tmp, sizeof(tmp));
	iSelected = StringToInt(tmp);
	

	switch (action)
	{
		case MenuAction_Select:
		{
			g_iShowSprite[param1] = iSelected;
			decl String:szSelected[3];
			Format(szSelected, sizeof(szSelected), "%i", iSelected);
			SetClientCookie(param1, g_SpriteShowCookie, szSelected);
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


stock CreateSprite(iClient, String:sprite[], Float:offset)
{
	new String:szTemp[64]; 
	Format(szTemp, sizeof(szTemp), "client%i", iClient);
	DispatchKeyValue(iClient, "targetname", szTemp);

	new Float:vOrigin[3];
	GetClientAbsOrigin(iClient, vOrigin);
	vOrigin[2] += offset;
	new ent = CreateEntityByName("env_sprite_oriented");
	if (ent)
	{
		DispatchKeyValue(ent, "model", sprite);
		DispatchKeyValue(ent, "classname", "env_sprite_oriented");
		DispatchKeyValue(ent, "spawnflags", "1");
		DispatchKeyValue(ent, "scale", "0.1");
		DispatchKeyValue(ent, "rendermode", "1");
		DispatchKeyValue(ent, "rendercolor", "255 255 255");
		DispatchKeyValue(ent, "targetname", "donator_spr");
		DispatchKeyValue(ent, "parentname", szTemp);
		DispatchSpawn(ent);
		
		TeleportEntity(ent, vOrigin, NULL_VECTOR, NULL_VECTOR);

		g_EntList[iClient] = ent;
	}
}


stock KillSprite(iClient)
{
	if (g_EntList[iClient] > 0 && IsValidEntity(g_EntList[iClient]))
	{
		AcceptEntityInput(g_EntList[iClient], "kill");
		g_EntList[iClient] = 0;
	}
}


public OnGameFrame()
{
	if (!g_bRoundEnded) return;
	new ent, Float:vOrigin[3], Float:vVelocity[3];
	
	for(new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		if ((ent = g_EntList[i]) > 0)
		{
			if (!IsValidEntity(ent))
				g_EntList[i] = 0;
			else
				if ((ent = EntRefToEntIndex(ent)) > 0)
				{
					GetClientEyePosition(i, vOrigin);
					vOrigin[2] += 25.0;
					GetEntDataVector(i, gVelocityOffset, vVelocity);
					TeleportEntity(ent, vOrigin, NULL_VECTOR, vVelocity);				
				}
		}
	}
}

