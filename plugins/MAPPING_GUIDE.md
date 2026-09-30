# Facility Mapper – mapping guide

**Install:** Studio → Plugins tab → Plugins Folder → drop `FacilityMapper.rbxmx` in → restart Studio → click **Facility Mapper**.
**Settings:** Game Settings → Security → Studio Access to API Services **ON**, Allow HTTP Requests **ON**.

## Tools
| Tool | How |
|---|---|
| **Zone** | Click floor corners → Enter (or click the first corner). Backspace = undo corner, Esc = cancel |
| **Door** | Click the door. Set Door type / Access first |
| **Route** | Click points along a path → Enter. `Stairs` for staircases, `BusUnloadLine` for the bus walk |
| **Point** | Click a spot. SniperPost / Spotlight / CourtCam / PressPodium face where the camera looks (or **Point at camera**) |
| **Seat** | Click a Seat to give it the role. JurorSeat numbers itself 1–12 |
| **Select** | Click something → Delete, or change fields → Apply edits |

Blue = rooms (need a door on their edge), green = areas, red = sniper zones, orange = doors,
purple = routes, yellow = points, pink = seats. **Check this facility** = green/red checklist.

## What to map (Z zone, D door, R route, P point, S seat)
**Prison** (already has 144 zones – you're adding to it)
- Z: Interrogation, Courtroom, JuryRoom, GuardTower, KillZone (between fences), Perimeter (just outside); optional CourtHolding, JudgeChambers, ProtectiveCustody
- D: every new room's door
- P: BusBay, PrisonPhone ×2+, SniperPost + Spotlight per tower, BailiffSpot; optional CourtCam, DrugTestStation, CommissaryWindow
- S: JudgeSeat, DefendantSeat, DefenseSeat, ProsecutorSeat, WitnessSeat, JurorSeat ×12, GallerySeat
- R: BusUnloadLine (bus bay → intake), **Stairs** up every staircase

**Courthouse** (city court)
- Z: Courtroom (each one), CourtHolding, JuryRoom, JudgeChambers, SecurityCheckpoint, CourtLobby, SallyPort; optional LegalVisit, PressArea
- D: every door
- P: BailiffSpot (per courtroom), ClerkWindow, MetalDetector, VehicleDropoff, CourthouseSteps; optional CourtCam
- S: full court seat set per courtroom

**Police HQ**
- Z: SallyPort, BookingArea, HoldingCell, Interrogation, LegalVisit, Lobby; optional MunicipalCourt, Office, Evidence, LockerRoom, Garage
- D: every door
- P: BookingDesk, TurnInPoint, VehicleDropoff; optional MugshotSpot, MDTTerminal, EvidenceLocker, PressPodium, PoliceSpawn, HoldingPhone
- S: SuspectSeat + DetectiveSeat (interrogation), InmateVisitSeat + LawyerVisitSeat (legal visit)

**City jail**
- Z: SallyPort, BookingArea, JailCell ×4+, TransferHolding, DayRoom, ReleaseArea; optional Yard, LegalVisit
- D: every cell / room door
- P: BookingDesk, VehicleDropoff, ReleasePoint, BusDeparture; optional JailPhone

**Law offices** (one per firm) – Use selected model → type firm name → Save firm name
- P: Reception; S: LawyerSeat, ClientSeat; optional ConferenceSeat, Lobby/Office zones

**Bank** (Workspace.Bank; select GNC separately if it's its own model)
- Z: DepositVault; D: vault door; P: DepositTerminal, BoxWall; optional TellerDesk, BankerDesk

**City**
- P: NewsStation, BullionDealer, BailBondsOffice, ChopShop, ShadyDealer, PlateMakerSpot ×3+, FixerSpot ×2+,
  PrivateVaultSpot ×2+, StashSpot ×3+, DrugCorner ×3+, Bar, Hospital, ImpoundLot, DealershipDesk;
  optional PawnShop, UndergroundMetalBuyer, LiquorStore, Safehouse
- Z (optional): TerritoryEK / IS / DS / TL – each street gang's neighbourhood

## Order
1. Police HQ + prison additions → send the place (I start the arrest rework)
2. Courthouse, prison phones, law offices, bank vault
3. City jail
4. City points

Save the place and send the `.rbxl` after each batch.
