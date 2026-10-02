# Handoff – Las Vegas (Roblox) project

Read this first in a new Claude session. Working branch: `claude/roblox-cuffwalk-nav-fixes-3ngf7a`.

## Project layout
- `place/scripts/` – every script in the place, exported as files named `Name.Script.lua`, `Name.LocalScript.lua`, `Name.ModuleScript.lua` in folders matching the Explorer path.
- `tools/build.luau` – `lune run tools/build.luau <base.rbxl> <out.rbxl>` writes the scripts back into a place file (new files become new scripts).
- `tools/check.sh` – compiles every script with the official Luau compiler (-O0), catches the 200-local-register limit.
- `plugins/FacilityMapper/` – the Facility Mapper Studio plugin source; `lune run tools/build_plugin.luau` → `plugins/FacilityMapper.rbxmx`.
- `plugins/ROADMAP.md` – every planned feature, version by version (next: v240).
- `plugins/MAPPING_GUIDE.md` – what the user is mapping with the plugin.

## Big scripts
- `ServerScriptService/PoliceSystem.Script.lua` – police AI + the whole custody/justice pipeline, bundled as `__modules[...]`. The `Justice` module (~line 6961–13430) is near the 200-local limit: add new state as fields on `PrisonFlow` / `PL`, not new top-level locals.
- `PoliceSystem/PrisonExtras.ModuleScript.lua` – regimen, line-ups, CO sweep, solitary, executions, visits.
- `PoliceSystem/PrisonNavigation.ModuleScript.lua` – nav graph from the prison map (Zones / DoorMarkers / Routes).
- `PrisonSociety.Script.lua` – NPC inmates, gangs, fights, CO respect, riots, gang hits.
- `EconomyServer.Script.lua` – money + saving (DataStore `LasVegas_PlayerData_v1`).

## Conventions
- Some files use CRLF line endings – preserve them when editing.
- Every change: `bash tools/check.sh`, build the next `LasVegas_vNNN_Name.rbxl`, delete the previous .rbxl, commit, push.
- Custody debugging: every custody stage change logs `[Custody] STAGE <player> <old> -> <new>` (v239); older diagnostics log `[CustodyDiag]`.

## State (as of v239)
- v239: custody stage machine (`PrisonFlow.stageOf` / `CustodyStage` attribute); each stage owns where a new character spawns.
- Known leftover: resetting in solitary respawns in the home cell.
- Facility Mapper v6 (plugin): Pick building button, cyan hover preview, PoliceHQ finds `PoliceStation`,
  multi-part doors (hold Shift + click parts, release Shift → grouped into one door Model).
  Install: copy `plugins/FacilityMapper.rbxmx` to `%LOCALAPPDATA%\Roblox\Plugins\`, restart Studio.
- Mapping status (2026-09-30): only `CorrectionalFacility.PrisonMap` exists (144 restored zones, 156 doors, 3 routes, 0 points,
  no seat roles). Police HQ, prison additions, courthouse, jail, bank, law offices, city: not mapped yet.
  The user is mapping Police HQ (`Workspace.PoliceStation`) next; v240 waits on that.
- Allow HTTP Requests was OFF in the place; the user needs to turn it on.
- 2026-10-01: v240–v249 were built in Studio by another session and exported to the repo on this date
  (Facilities, Records, GuardTowers, Interrogation...). Studio "Test1" place = source; repo now matches it.
- v245b–f: City Jail gate (FacilityGates script), tower stun/lethal zones, 3 guards per tower,
  zone = crime (PrisonTrespass / PrisonFenceBreach), prison gates are station exits, off-road arrest pickup.
- v250 gang ranks live in PrisonSociety (`Ranks` table); v251 street gangs + saved gang standing in
  StreetGangs.Script (DataStore LasVegas_Gangs_v1). City territories need TerritoryEK/IS/DS/TL zones mapped.
- Studio sync trick: run a localhost file server and `HttpService:GetAsync` the repo file in Studio
  (HTTP is ON in the place); export goes the other way with PostAsync.
- v252/v253 drugs (Drugs.Script, DrugsClient), v254 bail (PoliceSystem.Bail + BailClient; court = HQ front desk until v263).
- Side build: GTA IV handling (ReplicatedStorage.GTAVehicle / GTAHandlingData = the user's real handling.dat), F enter/exit, Space handbrake.
- Next: v255 asset freeze & stashes. (old note: v240 multi-building (Police HQ etc. from the user's mapped place), v241 arrest scene. See ROADMAP.md.

## With the Studio MCP server connected
**User rule: do NOT start play tests unless the user explicitly asks** (they burn usage). The user plays and reports.
Use the connection for everything else:
- read the Output the user's own test left behind (`[Custody]`, `[CustodyDiag]`, `[PrisonNav]` lines) instead of asking them to paste it
- inspect the place in edit mode: mapped folders (`CorrectionalFacility.PrisonMap`, `<Building>.FacilityMap`, `Workspace.CityMap`),
  seats with `SeatRole`, models, attributes
- run small edit-mode Luau checks (counts, validation) and apply script changes straight into Studio
- keep the repo in sync: every script change still goes into `place/scripts/`, is compile-checked, committed and pushed

- GTA handling WIP (2026-10-01): after the last test drive the car HOVERS ~2-3 studs (no ray contacts) once wheels were made featherweight. Suspect the client impulse anti-gravity overshoots now that the wheels no longer pull down, or a double drive loop. Next: check GTADebug on the seat, compare seat.AssemblyMass vs actual, retest turn/handbrake with the server logger (_G.drivelog).
