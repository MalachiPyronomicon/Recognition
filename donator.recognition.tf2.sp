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
* 0.5.18 - cleanup on client disconnect
* 0.5.19 - improve cleanup on round start, reset sprite index even if entity is no longer valid, check for class and target names before killing sprite, add debug info
* 0.5.20 - convert entity indexes to use guaranteed references
* 0.5.21 - use config (keyvalues) file to load sprite info
*
*/


// INCLUDES
#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <donator>
#include <clientprefs>

#pragma semicolon 1


// DEFINES
//uncomment to enable DEBUG messages
//#define DEBUG

// Plugin Info
#define PLUGIN_INFO_VERSION					"0.5.21"
#define PLUGIN_INFO_NAME					"Donator Recognition"
#define PLUGIN_INFO_AUTHOR					"Nut / Malachi"
#define PLUGIN_INFO_DESCRIPTION				"Give donators after-round above-head icons (sprites)."
#define PLUGIN_INFO_URL_OLD					"http://www.lolsup.com/tf2"
#define PLUGIN_INFO_URL						"http://www.necrophix.com/"
#define PLUGIN_PRINT_NAME					"[Recognition]"							// Used for self-identification in chat/logging

// These define the text players see in the donator menu
#define MENUTEXT_DONATOR_SPRITE				"Above-Player Icon"

// Health boost amount given to donators on map win
#define DONATOR_HEALTH_BOOST 				1800

// entity info
#define SPRITE_ENTITYNAME					"env_sprite_oriented"
#define SPRITE_TARGETNAME					"donator_spr"

#define COOKIENAME_SPRITE					"donator_spriteshow"
#define COOKIENAME_SPRITE_DESCRIPTION		"Which donator sprite to show."

// KeyValues
#define PATH_KVFILE_SPRITES					"configs/donator/donator.recognition.tf2.cfg"
#define KVFILE_SPRITES_ROOT_NAME			"Sprites"
#define KVFILE_SPRITES_SPRITE_NAME			"name"
#define KVFILE_SPRITES_PATH_NAME			"file"


// GLOBALS
new gVelocityOffset;																// ?
new g_SpriteEntityReference[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};			// Array of players, sprite entity guaranteed reference
new g_bIsDonator[MAXPLAYERS + 1];													// Array of players, true if donator
new bool:g_bRoundEnded;																// Flag = true during after-round
new Handle:g_SpriteShowCookie = INVALID_HANDLE;										// Cookie to store sprite choice
new g_iShowSprite[MAXPLAYERS + 1];													// Which sprite to show
new gTotalSpriteFiles = 0;															// ?
new String:g_sSpritesPath[PLATFORM_MAX_PATH];
new Handle:g_SpriteNameList = INVALID_HANDLE;
new Handle:g_SpritePathList = INVALID_HANDLE;


// Info
public Plugin:myinfo = 
{
	name = PLUGIN_INFO_NAME,
	author = PLUGIN_INFO_AUTHOR,
	description = PLUGIN_INFO_DESCRIPTION,
	version = PLUGIN_INFO_VERSION,
	url = PLUGIN_INFO_URL
}


public OnPluginStart()
{
	// Advertise our presence...
	PrintToServer("%s v%s Plugin start...", PLUGIN_PRINT_NAME, PLUGIN_INFO_VERSION);

	CreateConVar("basicdonator_recog_v", PLUGIN_INFO_VERSION, "Donator Recognition Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	HookEventEx("teamplay_round_start", hook_Start, EventHookMode_PostNoCopy);
	HookEventEx("arena_round_start", hook_Start, EventHookMode_PostNoCopy);
	HookEventEx("teamplay_round_win", hook_Win, EventHookMode_PostNoCopy);
	HookEventEx("arena_win_panel", hook_Win, EventHookMode_PostNoCopy);
	HookEventEx("player_death", event_player_death, EventHookMode_Post);
	
	g_SpriteShowCookie = RegClientCookie(COOKIENAME_SPRITE, COOKIENAME_SPRITE_DESCRIPTION, CookieAccess_Private);
	
	gVelocityOffset = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");

	//Build SM Path 
	BuildPath(Path_SM, g_sSpritesPath, sizeof(g_sSpritesPath), PATH_KVFILE_SPRITES); 

	// Create global-dynamic arrays
	new arraySize = ByteCountToCells(PLATFORM_MAX_PATH);
	g_SpriteNameList = CreateArray(arraySize);
	g_SpritePathList = CreateArray(arraySize);
}


public OnAllPluginsLoaded()
{
	if(!LibraryExists("donator.core"))
		SetFailState("Unabled to find plugin: Basic Donator Interface");

	Donator_RegisterMenuItem(MENUTEXT_DONATOR_SPRITE, SpriteControlCallback);
}


public OnMapStart()
{
	gTotalSpriteFiles = 0;

	new Handle:kvSprites = CreateKeyValues(KVFILE_SPRITES_ROOT_NAME);
	FileToKeyValues(kvSprites, g_sSpritesPath);

	if (!KvGotoFirstSubKey(kvSprites))
	{
		SetFailState("%s Unable to load file: %s", PLUGIN_PRINT_NAME, PATH_KVFILE_SPRITES);
	}

	decl String:szBuffer[128];
	decl String:sSectionName[64];
	decl String:sSpriteName[255];
	decl String:sSpritePath[255];

	do
	{
		KvGetSectionName(kvSprites, sSectionName, sizeof(sSectionName));    
		KvGetString(kvSprites, KVFILE_SPRITES_SPRITE_NAME, sSpriteName, sizeof(sSpriteName));
		KvGetString(kvSprites, KVFILE_SPRITES_PATH_NAME, sSpritePath, sizeof(sSpritePath));

		#if defined DEBUG
			PrintToServer ("%s DEBUG - sprite name = %s; sprite path name = %s", PLUGIN_PRINT_NAME, sSpriteName, sSpritePath);
		#endif
		
         // Add each path to the download table/precache.
		FormatEx(szBuffer, sizeof(szBuffer), "%s.vmt", sSpritePath);
		PrecacheGeneric(szBuffer, true);
		AddFileToDownloadsTable(szBuffer);
		FormatEx(szBuffer, sizeof(szBuffer), "%s.vtf", sSpritePath);
		PrecacheGeneric(szBuffer, true);
		AddFileToDownloadsTable(szBuffer);

		PushArrayString(g_SpriteNameList, sSpriteName);
		PushArrayString(g_SpritePathList, sSpritePath);
		
		gTotalSpriteFiles++;
    } while (KvGotoNextKey(kvSprites));
	
	#if defined DEBUG
		PrintToServer ("%s DEBUG - # of sprites found = %d", PLUGIN_PRINT_NAME, gTotalSpriteFiles);
		PrintToServer ("%s DEBUG - name array size = %d, path array size = %d", PLUGIN_PRINT_NAME, GetArraySize(g_SpriteNameList), GetArraySize(g_SpritePathList));
	#endif

    CloseHandle(kvSprites);  
}


// Cleanup 
public OnMapEnd()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		g_SpriteEntityReference[i] = INVALID_ENT_REFERENCE;
	}
}


public OnPostDonatorCheck(iClient)
{
	new String:szBuffer[256];

	if (!IsPlayerDonator(iClient))
	{
		return;
	}
	else
	{	
		g_bIsDonator[iClient] = true;
		
		// Only used if cookie not already set
		g_iShowSprite[iClient] = 1;
		
		if (AreClientCookiesCached(iClient))
		{		
			GetClientCookie(iClient, g_SpriteShowCookie, szBuffer, sizeof(szBuffer));
			
			if (strlen(szBuffer) > 0)
			{
				g_iShowSprite[iClient] = StringToInt(szBuffer);
			}
		}
	}
	
}


public OnClientDisconnect(iClient)
{
	KillSprite(iClient);
	g_bIsDonator[iClient] = false;
}


public hook_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	for(new i = 0; i <= MaxClients; i++)
	{
		KillSprite(i);
	}
	g_bRoundEnded = false;
}


public hook_Win(Handle:event, const String:name[], bool:dontBroadcast)
{	
	decl String:szBuffer[128];
	decl String:sTemp[128];
	for(new i = 1; i <= MaxClients; i++)
	{
		// Weed out Observers and Not-In-Game
		if (!IsClientInGame(i) || IsClientObserver(i)) continue;
		
		// Weed out non-donators
		if (!g_bIsDonator[i]) continue;
		
		// Weed out dead donators
		if (!IsPlayerAlive(i)) continue;

		if (g_iShowSprite[i] > 0)
		{
			if (g_iShowSprite[i] > gTotalSpriteFiles)
			{
				LogError ("%s ERROR - Sprite index out of bounds.", PLUGIN_PRINT_NAME);
			}
			else
			{
				GetArrayString(g_SpritePathList, g_iShowSprite[i]-1, sTemp, sizeof(sTemp));
				FormatEx(szBuffer, sizeof(szBuffer), "%s.vmt", sTemp);
				CreateSprite(i, szBuffer, 25.0);

				#if defined DEBUG
					PrintToServer ("%s DEBUG - created sprite #%d:%s", PLUGIN_PRINT_NAME, g_iShowSprite[i]-1, szBuffer);
				#endif
			}
		}
		
		// Give player health boost
		SetEntityHealth(i, DONATOR_HEALTH_BOOST);
		
	}
	g_bRoundEnded = true;
}


public Action:event_player_death(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!g_bRoundEnded) 
	{
		return Plugin_Continue;
	}
	
	KillSprite(GetClientOfUserId(GetEventInt(event, "userid")));

	return Plugin_Continue;
}


public DonatorMenu:SpriteControlCallback(iClient) Panel_SpriteControl(iClient);


public Action:Panel_SpriteControl(iClient)
{
	decl String:sTemp[128];
	new Handle:menu = CreateMenu(SpriteControlSelected);
	SetMenuTitle(menu,"Donator: Sprite Control:");
	
	if (g_iShowSprite[iClient] > 0)
		AddMenuItem(menu, "0", "Disable Sprite", ITEMDRAW_DEFAULT);
	else
		AddMenuItem(menu, "0", "Disable Sprite", ITEMDRAW_DISABLED);
	
	decl String:szItem[16];
	for (new i = 0; i < gTotalSpriteFiles; i++)
	{
//		Format(szItem, sizeof(szItem), "%i", i+1);	//need to offset the menu items by one since we added the enable / disable outside of the loop
		IntToString(i+1, szItem, sizeof(szItem));

		GetArrayString(g_SpriteNameList, i, sTemp, sizeof(sTemp));

		if (g_iShowSprite[iClient]-1 != i)
		{
			AddMenuItem(menu, szItem, sTemp, ITEMDRAW_DEFAULT);
		}
		else
		{
			AddMenuItem(menu, szItem, sTemp,ITEMDRAW_DISABLED);
		}
		
		#if defined DEBUG
			PrintToServer ("%s DEBUG - created menu item #%s:%s", PLUGIN_PRINT_NAME, szItem, sTemp);
		#endif
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
	new ent = CreateEntityByName(SPRITE_ENTITYNAME);
	
	if (IsValidEntity(ent))
	{
		g_SpriteEntityReference[iClient] = EntIndexToEntRef(ent);

		if(GetEntityCount() < GetMaxEntities()-32)
		{
			DispatchKeyValue(ent, "model", sprite);
			DispatchKeyValue(ent, "classname", SPRITE_ENTITYNAME);
			DispatchKeyValue(ent, "spawnflags", "1");
			DispatchKeyValue(ent, "scale", "0.1");
			DispatchKeyValue(ent, "rendermode", "1");
			DispatchKeyValue(ent, "rendercolor", "255 255 255");
//			DispatchKeyValue(ent, "targetname", SPRITE_TARGETNAME);
//			DispatchKeyValue(ent, "parentname", szTemp);
			DispatchSpawn(ent);
			
			TeleportEntity(ent, vOrigin, NULL_VECTOR, NULL_VECTOR);
		}
		else
		{
			LogError ("%s ERROR - Unable to create sprite, maxEntities reached.", PLUGIN_PRINT_NAME);
		}

	}
	else
	{
		LogError ("%s ERROR - Unable to create sprite, entity not valid.", PLUGIN_PRINT_NAME);
	}
}


stock KillSprite(iClient)
{
	new index = EntRefToEntIndex(g_SpriteEntityReference[iClient]);
	 
	if (index == INVALID_ENT_REFERENCE)
	{
		PrintToServer ("%s CATCH - Entity no longer exists.", PLUGIN_PRINT_NAME);
	}
	else
	{
		if (IsValidEntity(index))
		{
			PrintToServer ("%s Entity deleted.", PLUGIN_PRINT_NAME);
			AcceptEntityInput(index, "kill");
		}
		else
		{
			PrintToServer ("%s CATCH - Entity exists but not valid.", PLUGIN_PRINT_NAME);
		}
	}

	// Invalidate 
	g_SpriteEntityReference[iClient] = INVALID_ENT_REFERENCE;
}


public OnGameFrame()
{
	if (!g_bRoundEnded) 
	{
		return;
	}
	
	new ent = INVALID_ENT_REFERENCE;
	new Float:vOrigin[3];
	new Float:vVelocity[3];
	
	// For each player slot
	// Start at 1 to skip console
	for(new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		
		if (g_SpriteEntityReference[i] != INVALID_ENT_REFERENCE)
		{
			ent = EntRefToEntIndex(g_SpriteEntityReference[i]);
			
			GetClientEyePosition(i, vOrigin);
			vOrigin[2] += 25.0;
			GetEntDataVector(i, gVelocityOffset, vVelocity);
			TeleportEntity(ent, vOrigin, NULL_VECTOR, vVelocity);				
			
			// Buff player speed
			SetEntPropFloat(i, Prop_Data, "m_flMaxspeed", 400.0);
		}
	}
}

