# Las Vegas (Roblox) — script sources

`place/scripts/` mirrors every uniquely-pathed script in the place file, laid out by
Instance path (`ServerScriptService/PoliceSystem/PrisonNavigation.ModuleScript.lua` is
`game.ServerScriptService.PoliceSystem.PrisonNavigation`). Scripts that share a full
path with a sibling are listed in `DUPLICATE_PATHS.txt` and are not exported.

Baseline: `LasVegas_v190_DeathRowGasModuleFix_BOOKING_FIXED.rbxl` (first commit).

## Tools ([Lune](https://github.com/lune-org/lune) 0.10.5+)

```sh
lune run tools/export.luau  MyPlace.rbxl                 # place -> place/scripts
lune run tools/check.luau                                # compile-check every script
lune run tools/build.luau   MyPlace.rbxl Patched.rbxl    # place/scripts -> new place
```

`build` only rewrites scripts whose text changed; parts, maps and attributes are
carried through (verified: identical instance count, attributes and tags; only
rotation matrices snap by <1e-6, the same thing Studio does on save).

To apply these changes to another version (e.g. v189): run `build` with that
place as the base. Only the four scripts below differ from the v190 baseline; if
v189's copies of them differ, re-export v189 on a branch and merge instead.

## v191 changes

### Cuff-walk (PrisonNavigation + PoliceSystem/PrisonFlow)

Root cause of `body sweep: ...IntakeCell.Part` at Booking Cell 5 (and the
`Model.Part` failure at Intake Cell Door): mapped cell openings are 4.2 studs wide
and the prisoner sweep box is 3 wide, leaving 0.6 studs of lateral tolerance. The
escort leg-1 staging point accepts arrival within 1.25 studs, so the prisoner stops
off the door's centre line and the diagonal leg-2 sweep clips the jamb. The officer
uses precise arrival on its leg 1 and passes. Each retry reproduced the same stop.

Hierarchy now:

1. **Normal cuff-walk (unchanged path).** Mapped graph + local pathfinding as before.
   - *Door threshold resync:* when a doorway sweep fails, the lead picks a validated
     point on the same side of the door on its centre line (lateral offsets up to
     0.6, several depths) and walks there, then straight through. Tries the 3-stud
     corridor box, then a 2.4-stud torso box. Collision is never disabled.
   - Doorway sweep box is anchored to the mapped door floor, so tall player avatars
     sweep the same height band as the NPC officer.
   - Pair watchdog: re-plans when neither body moves for 1.5s or the prisoner drifts
     past the formation gap for 3s (max 4 re-plans per leg).
2. **Soft recovery (per doorway leg).** Stage 1: walk the pair back to a validated
   threshold point near the prisoner. Stage 2: validated micro-reposition of at most
   3.5 studs on the same side of the door. Then the leg is retried.
3. **Alternate route.** Existing graph REPATH with blocked-edge penalties; a new
   transfer attempt resumes from the current position.
4. **Destination fallback (last resort).** After 3 failed physical transfers or 300s,
   `PrisonFlow.fallbackDeliver` places the prisoner in the assigned cell and finalizes
   exactly like a walked delivery: dress-out still applied, reservation cleared,
   cuffs released, parked officer despawned (its NoCollision links go with it), cell
   locked, final custody state set, `EscortFailure` cleared.

Log lines to look for: `DOOR THRESHOLD RESYNC`, `ESCORT REPLAN`,
`CUFF WALK RECOVERY stage=...`, `CUFF WALK RECOVERED`, `CUFF WALK EXHAUSTED`,
`DESTINATION FALLBACK`.

### Resident traffic (CivilianTrafficServer + RoadDriving)

- **Parked police stopped the city.** Cruisers keep `Emergency=true` after parking.
  Traffic braked to 0 for any "emergency" model within 30 studs ahead (any lane),
  and stuck recovery only ran when the car wanted to move, so those cars waited
  forever. Now the index measures each unit's speed: moving units get a corridor
  (pull to the kerb, keep rolling); a stationary unit only matters if it is in the
  car's own lane, where the car queues, changes lane, or eases around it.
- **Stationary watchdog:** a car that hasn't moved for 25s picks a new trip (may
  U-turn); after 90s out of sight (180s otherwise) it is recycled and respawned
  elsewhere by the refill loop.
- **Stale four-way-stop queue entries** from cars that left or despawned no longer
  hold the junction for 12s (entries must be refreshed every 1.5s).
- **Destinations spread across the city:** prefer far destinations, avoid the car's
  last 3, and avoid roads many other cars are already heading to.
