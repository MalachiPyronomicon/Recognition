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
* 0.5.22 - bug: didnt clear arrays
* 0.5.23 - include offsets, add error handling to kv file read
* 0.5.24 - fix offset math, better error handling, minor fixes
* 0.5.30 - use FNM to download files - some clients still crash?
*
*/


// INCLUDES
#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <donator>
#include <clientprefs>
#include <filenetmessages>					// FNM_SendFile

#pragma semicolon 1


// DEFINES
//uncomment to enable DEBUG messages
//#define DEBUG

// Plugin Info
#define PLUGIN_INFO_VERSION					"0.5.30"
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

#define COOKIENAME_SPRITE					"donator_spriteshow"
#define COOKIENAME_SPRITE_DESCRIPTION		"Which donator sprite to show."

// KeyValues
#define PATH_KVFILE_SPRITES					"configs/donator/donator.recognition.tf2.cfg"
#define KVFILE_SPRITES_ROOT_NAME			"Sprites"
#define KVFILE_SPRITES_SECTION_NAME			"Sprite"
#define KVFILE_SPRITES_SPRITE_NAME			"name"
#define KVFILE_SPRITES_PATH_NAME			"file"
#define KVFILE_SPRITES_XOFFSET_NAME			"xoffset"
#define KVFILE_SPRITES_YOFFSET_NAME			"yoffset"
#define KVFILE_SPRITES_ZOFFSET_NAME			"zoffset"


// GLOBALS
new gVelocityOffset;																// ?
new g_SpriteEntityReference[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};			// Array of players, sprite entity guaranteed reference
new g_bIsDonator[MAXPLAYERS + 1];													// Array of players, true if donator
new bool:g_bRoundEnded;																// Flag = true during after-round
new Handle:g_SpriteShowCookie = INVALID_HANDLE;										// Cookie to store sprite choice
new g_iShowSprite[MAXPLAYERS + 1];													// Which sprite to show
new gTotalSpriteFiles = 0;															// ?
new String:g_sSpritesPath[PLATFORM_MAX_PATH];
new Handle:g_SpriteNameList = INVALID_HANDLE;										// global, dynamic array
new Handle:g_SpritePathList = INVALID_HANDLE;										// global, dynamic array
new Handle:g_SpriteXOffset = INVALID_HANDLE;										// global, dynamic array
new Handle:g_SpriteYOffset = INVALID_HANDLE;										// global, dynamic array
new Handle:g_SpriteZOffset = INVALID_HANDLE;										// global, dynamic array


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
	
	
	g_SpriteXOffset = CreateArray(1);
	g_SpriteYOffset = CreateArray(1);
	g_SpriteZOffset = CreateArray(1);
}


public OnAllPluginsLoaded()
{
	if(!LibraryExists("donator.core"))
		SetFailState("Unable to find plugin: Basic Donator Interface");

	Donator_RegisterMenuItem(MENUTEXT_DONATOR_SPRITE, SpriteControlCallback);
}


public OnMapStart()
{
	new ErrorCount = 0;
	gTotalSpriteFiles = 0;

	// clear arrays
	ClearArray(g_SpriteNameList);
	ClearArray(g_SpritePathList);
	ClearArray(g_SpriteXOffset);
	ClearArray(g_SpriteYOffset);
	ClearArray(g_SpriteZOffset);

	// Index 0 (Disabled) should never be used - push dummy values
	PushArrayString(g_SpriteNameList, "");
	PushArrayString(g_SpritePathList, "");
	PushArrayCell(g_SpriteXOffset, 0.0);
	PushArrayCell(g_SpriteYOffset, 0.0);
	PushArrayCell(g_SpriteZOffset, 0.0);
	gTotalSpriteFiles++;

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
	decl Float:fSpriteXOffset;
	decl Float:fSpriteYOffset;
	decl Float:fSpriteZOffset;

	do
	{
		KvGetSectionName(kvSprites, sSectionName, sizeof(sSectionName));    
		if (strcmp(sSectionName, KVFILE_SPRITES_SECTION_NAME, true) == 0)
		{
			KvGetString(kvSprites, KVFILE_SPRITES_SPRITE_NAME, sSpriteName, sizeof(sSpriteName));
			KvGetString(kvSprites, KVFILE_SPRITES_PATH_NAME, sSpritePath, sizeof(sSpritePath));
			
			fSpriteXOffset = KvGetFloat(kvSprites, KVFILE_SPRITES_XOFFSET_NAME, -999.9);
			if ( fSpriteXOffset == -999.9 )
			{
				ErrorCount++;
				PrintToServer ("%s ERROR - Unable to get X Offset = %1.1f", PLUGIN_PRINT_NAME, fSpriteXOffset);
			}
			
			fSpriteYOffset = KvGetFloat(kvSprites, KVFILE_SPRITES_YOFFSET_NAME, -999.9);
			if ( fSpriteYOffset == -999.9 )
			{
				ErrorCount++;
				PrintToServer ("%s ERROR - Unable to get Y Offset = %1.1f", PLUGIN_PRINT_NAME, fSpriteYOffset);
			}
			
			fSpriteZOffset = KvGetFloat(kvSprites, KVFILE_SPRITES_ZOFFSET_NAME, -999.9);
			if ( fSpriteZOffset == -999.9 )
			{
				ErrorCount++;
				PrintToServer ("%s ERROR - Unable to get Z Offset = %1.1f", PLUGIN_PRINT_NAME, fSpriteZOffset);
			}
			
			#if defined DEBUG
				PrintToServer ("%s DEBUG - sprite: name = %s; path  = %s; offset = %1.1f, %1.1f, %1.1f", PLUGIN_PRINT_NAME, sSpriteName, sSpritePath, fSpriteXOffset, fSpriteYOffset, fSpriteZOffset);
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
			PushArrayCell(g_SpriteXOffset, fSpriteXOffset);
			PushArrayCell(g_SpriteYOffset, fSpriteYOffset);
			PushArrayCell(g_SpriteZOffset, fSpriteZOffset);
			
			gTotalSpriteFiles++;
		}
		else
		{
			#if defined DEBUG
				PrintToServer ("%s DEBUG - Unknown section name  = %s, skipping...", PLUGIN_PRINT_NAME, sSectionName);
			#endif
		}
    } while (KvGotoNextKey(kvSprites));
	
	#if defined DEBUG
		PrintToServer ("%s DEBUG - # of sprites found = %d, name array size = %d, path array size = %d", PLUGIN_PRINT_NAME, gTotalSpriteFiles, GetArraySize(g_SpriteNameList), GetArraySize(g_SpritePathList));
	#endif

	CloseHandle(kvSprites);

	if (ErrorCount > 0)
	{
		SetFailState("%s %d errors trying to load file: %s", PLUGIN_PRINT_NAME, ErrorCount, PATH_KVFILE_SPRITES);
	}
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
	new String:szBuffer[128];
	decl String:iClientName[MAX_NAME_LENGTH];
	new ErrorCount = 0;

	if ( !GetClientName(iClient, iClientName, sizeof(iClientName)) )
		Format(iClientName, sizeof(iClientName), "Console");

	// Add sprites to downloads
	decl String:sTemp[128];
	
	for(new i = 1; i < gTotalSpriteFiles; i++)
	{
		GetArrayString(g_SpritePathList, i, sTemp, sizeof(sTemp));
		FormatEx(szBuffer, sizeof(szBuffer), "%s.vmt", sTemp);
		if ( FNM_SendFile(iClient, szBuffer) )
		{
			PrintToServer("%s FNM_Send_File: Success, %s:%s", PLUGIN_PRINT_NAME, iClientName, szBuffer);
		}
		else
		{
			PrintToServer("%s FNM_Send_File: Failed, %s:%s", PLUGIN_PRINT_NAME, iClientName, szBuffer);
			ErrorCount++;
		}
		
		FormatEx(szBuffer, sizeof(szBuffer), "%s.vtf", sTemp);
		if ( FNM_SendFile(iClient, szBuffer) )
		{
			PrintToServer("%s FNM_Send_File: Success, %s:%s", PLUGIN_PRINT_NAME, iClientName, szBuffer);
		}
		else
		{
			PrintToServer("%s FNM_Send_File: Failed, %s:%s", PLUGIN_PRINT_NAME, iClientName, szBuffer);
			ErrorCount++;
		}
		
	}

	if (ErrorCount)
	{
		PrintToChat (iClient, "%s \x07FF0000CRASH WARNING", PLUGIN_PRINT_NAME);
		PrintToChat (iClient, "ERROR: A file failed to download.");
		PrintToChat (iClient, "Please change your options to allow downloads:");
		PrintToChat (iClient, "Options -> Multiplayer -> Custom Content -> Allow");
	}


	if (!IsPlayerDonator(iClient))
	{
		return;
	}
	else
	{	
		strcopy(szBuffer, sizeof(szBuffer), "");
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
	for(new i = 1; i <= MaxClients; i++)
	{
		// Weed out Observers and Not-In-Game
		if (!IsClientInGame(i) || IsClientObserver(i)) continue;
		
		// Weed out non-donators
		if (!g_bIsDonator[i]) continue;
		
		// Weed out dead donators
		if (!IsPlayerAlive(i)) continue;

		// Did donator choose disabled?
		if (g_iShowSprite[i] > 0)
		{
			if (g_iShowSprite[i] >= gTotalSpriteFiles)
			{
				LogError ("%s ERROR - Sprite index out of bounds: fixing.", PLUGIN_PRINT_NAME);
				g_iShowSprite[i] = 1;
			}
			else
			{
				CreateSprite(i);
				
				// Give player health boost
				SetEntityHealth(i, DONATOR_HEALTH_BOOST);

				// Show choice
				decl String:sTemp[128];
				GetArrayString(g_SpriteNameList, g_iShowSprite[i], sTemp, sizeof(sTemp));
				PrintToChat (i, "%s %s.", PLUGIN_PRINT_NAME, sTemp);
			}
		}
		else
		{
			PrintToChat (i, "%s Disabled.", PLUGIN_PRINT_NAME);
		}
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
	SetMenuTitle(menu,"Above-head Icon:");
	
	if (g_iShowSprite[iClient] > 0)
		AddMenuItem(menu, "0", "--Disabled--", ITEMDRAW_DEFAULT);
	else
		AddMenuItem(menu, "0", "--Disabled--", ITEMDRAW_DISABLED);
	
	decl String:szItem[16];
	for (new i = 1; i < gTotalSpriteFiles; i++)
	{
		//need to offset the menu items by one since we added the enable / disable outside of the loop
		IntToString(i, szItem, sizeof(szItem));

		GetArrayString(g_SpriteNameList, i, sTemp, sizeof(sTemp));

		if (g_iShowSprite[iClient] != i)
		{
			AddMenuItem(menu, szItem, sTemp, ITEMDRAW_DEFAULT);
		}
		else
		{
			AddMenuItem(menu, szItem, sTemp, ITEMDRAW_DISABLED);
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


stock CreateSprite(iClient)
{
	// Get sprite filename
	decl String:szBuffer[128];
	decl String:sTemp[128];
	GetArrayString(g_SpritePathList, g_iShowSprite[iClient], sTemp, sizeof(sTemp));
	FormatEx(szBuffer, sizeof(szBuffer), "%s.vmt", sTemp);

	// Set offset
	new Float:vOrigin[3];
	GetClientEyePosition(iClient, vOrigin);
	
	#if defined DEBUG
		PrintToServer ("%s DEBUG - created sprite #%d:%s", PLUGIN_PRINT_NAME, g_iShowSprite[iClient], szBuffer);
		PrintToServer ("%s DEBUG - at offset:   VOrigin(X%1.1f, Y%1.1f, Z%1.1f)", PLUGIN_PRINT_NAME, vOrigin[0], vOrigin[1], vOrigin[2]);
		PrintToServer ("%s DEBUG - at offset:   + Array(X%1.1f, Y%1.1f, Z%1.1f)", PLUGIN_PRINT_NAME, GetArrayCell(g_SpriteXOffset, g_iShowSprite[iClient]), GetArrayCell(g_SpriteYOffset, g_iShowSprite[iClient]), GetArrayCell(g_SpriteZOffset, g_iShowSprite[iClient]));
	#endif

	// Add in sprite offset
	vOrigin[0] += Float:GetArrayCell(g_SpriteXOffset, g_iShowSprite[iClient]);
	vOrigin[1] += Float:GetArrayCell(g_SpriteYOffset, g_iShowSprite[iClient]);
	vOrigin[2] += Float:GetArrayCell(g_SpriteZOffset, g_iShowSprite[iClient]);

	#if defined DEBUG
		PrintToServer ("%s DEBUG - at offset: = VOrigin(X%1.1f, Y%1.1f, Z%1.1f)", PLUGIN_PRINT_NAME, vOrigin[0], vOrigin[1], vOrigin[2]);
	#endif

	// Create sprite
	new ent = CreateEntityByName(SPRITE_ENTITYNAME);
	
	if (IsValidEntity(ent))
	{
		g_SpriteEntityReference[iClient] = EntIndexToEntRef(ent);

		if(GetEntityCount() < GetMaxEntities()-32)
		{
			DispatchKeyValue(ent, "model", szBuffer);
			DispatchKeyValue(ent, "classname", SPRITE_ENTITYNAME);
			DispatchKeyValue(ent, "spawnflags", "1");
			DispatchKeyValue(ent, "scale", "0.1");
			DispatchKeyValue(ent, "rendermode", "1");
			DispatchKeyValue(ent, "rendercolor", "255 255 255");
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
	
	new iEntity = INVALID_ENT_REFERENCE;
	new Float:vOrigin[3];
	new Float:vVelocity[3];
	
	// For each player slot
	// Start at 1 to skip console
	for(new iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient))
		{
			continue;
		}
		
		if (g_SpriteEntityReference[iClient] != INVALID_ENT_REFERENCE)
		{
			iEntity = INVALID_ENT_REFERENCE;
			iEntity = EntRefToEntIndex(g_SpriteEntityReference[iClient]);
			
			// get player position and add offset
			GetClientEyePosition(iClient, vOrigin);

			// Add in sprite offset
			vOrigin[0] += Float:GetArrayCell(g_SpriteXOffset, g_iShowSprite[iClient]);
			vOrigin[1] += Float:GetArrayCell(g_SpriteYOffset, g_iShowSprite[iClient]);
			vOrigin[2] += Float:GetArrayCell(g_SpriteZOffset, g_iShowSprite[iClient]);
			
			GetEntDataVector(iClient, gVelocityOffset, vVelocity);
			TeleportEntity(iEntity, vOrigin, NULL_VECTOR, vVelocity);				
			
			// Buff player speed
			SetEntPropFloat(iClient, Prop_Data, "m_flMaxspeed", 400.0);
		}
	}
}

