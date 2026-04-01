Attempt 3.26

### **Phase 1: Foundation & Geometry (The "Unit Cell")**

*Goal: Establish the engine parameters and prove the core mathematical model.*

**World scale:** One **game unit** (one Godot/engine unit of distance) equals **10 real-world meters** (10 m). Interpret all physical distances in this document—grid spacing, planet diameter, export scale—in SI meters, then convert for the engine by **÷ 10** (engine to meters: **× 10**). Example: a 6,700 km diameter planet is 6.7×10⁶ m across, or **670,000** game units between antipodal surface points along a diameter.

1. **Godot 4.7 Environment Setup:**  
   * Download or compile a **Double Precision (64-bit)** build of Godot 4.7. This is non-negotiable for planetary-scale coordinates to prevent floating-point jitter.  
   * Initialize a new project and set up a Git repository.  
2. **The Cube-Sphere Prototype:**  
   * Write a GDScript utility that generates a basic 3D cube and normalizes its vertices to form a sphere.  
   * Implement the coordinate conversion math: Translate a global 3D Vector3 position on that sphere into a specific (Face ID, X, Y) coordinate.
   * 10 m to 1 m planet to engine scale.

| Property | Specification | Rationale |
| :---- | :---- | :---- |
| **World scale** | **1 game unit = 10 m** | Single conversion between engine coordinates and physical meters for simulation, UI labels, and VTT export. |
| **Coordinate Space** | **Model Space (MODEL\_ Constants)** | Ensures 3D assets and character controllers align with Godot's imported asset conventions. |
| **Winding Order** | **Counter-Clockwise (CCW)** | Godot’s default for front-face rendering. Indices must be ordered to point "outward" from the sphere's center to avoid backface culling. |
| **Normal Direction** | **Outward Radial** | For a sphere, the normal vector at any vertex is equal to the normalized position of that vertex ($Normal \= \\frac{Position}{ |
| **Precision** | **64-bit Double Precision** | Required to prevent floating-point jitter at the 6,700 km scale (Phase 2). |

3. **The Custom Camera Director (V1):**  
   * Create the "God Camera" that always looks at (0,0,0).  
   * Implement the basic altitude-driven zoom controls.

### **Phase 2: The Macro-Simulation (Server-Side Logic)**

*Goal: Generate the low-resolution "base truth" of the planet.*  
*6,700 km diameter (planet radius `335_000` game units at **1 unit = 10 m**, shared via `project_scale.gd` / `ClimateSimulator`).*

**Resolution (implemented vs. headline).** Level 0 in code defaults to **512 × 512 cells per cube face** (`PlanetBaseTruthBaker.FACE_RES`), i.e. **6 × 512²** macro cells on the cube-sphere—not a single global 65,536-point field. Linear spacing is **roughly ~100 m** at this radius (exact size varies with face UV mapping and latitude). Treat earlier “2¹⁶ / ~80 m” figures as conceptual; the authoritative bake resolution is the face resolution on `ClimateGrid` / baker.

**Code layout.** **C#:** `TectonicPlates` (resource: plate Voronoi, domain warp, boundary kinematics, Earth-ish hypsometry, target land fraction), `PlanetBaseTruthBaker` (tool node: stitches elevation into `ClimateGrid`, optional worker thread, progress signals, EXR height export under `user://planet_data/`), `ClimateSimulator` (temperature, precipitation, biomes, soil wetness, orchestrates `RiverGenerator`), `RiverGenerator` / `CubeSphereMath`. **GDScript:** `ClimateGrid` (packed maps + EXR I/O), `ClimateSimTuning` (editor-facing named parameters pushed into `ClimateSimulator.ApplyTuningPack`).

**One full macro pass (order used in `debug_side_panel` / headless reports).**  
1. **Bake elevation** — `PlanetBaseTruthBaker.GenerateBaseTruth` → `ClimateGrid.update_elevation_from_buffers` (tectonics + fractal detail noise; toggles for warp / boundary / detail).  
2. **`CalculateBaseTemperature`** — zonal insolation proxy (cos-latitude shaping, amplitude/offset), **lapse** ~6.5 °C per km (ISA-style), latitude wobble noise, optional **subtropical / mid-latitude land warm biases** (keeps Whittaker land corners plausible vs. cold plateaus).  
3. **`CalculatePrecipitation`** — **prevailing-wind–aligned moisture rays** on the sphere (geodesic upwind integration, configurable step count), **maritime** weighting (coast/interior multipliers, power emphasizing recent ocean fetch), **orographic uplift** along the ray (cm/km, capped), **rain shadow** (barrier crest height vs. leeward geodesic distance, distance floor, min barrier MSL, upwind fetch length). Equator-crossing wind uses a **blended hemisphere sign** to avoid moisture seams.  
4. **`CalculateFlowAccumulation`** — **priority flood** fill to ocean, **D8** downslope graph, **basin ids** and coastal pour points; populates `flow_accumulation_map` / `flow_downstream_cell` / `basin_id_map` for rivers and for soil wetness.  
5. **`CalculateSoilWetness`** — starts from annual precip, then adds **river-corridor wetness** from high **flow accumulation** (configurable thresholds, radial decay into neighbors, arid-region caps, freeze taper); optional `enabled` flag and parameters via dictionary from `debug_side_panel`.  
6. **`CalculateBiomes`** — ocean / ice from elevation and temperature; land Whittaker classification in (T, **P**) space using **soil wetness** as the moisture axis when classifying (precip-only zonal validators may call earlier steps without soil/biomes—see `climate_latitude_validator.gd`).

**Runtime overrides & tuning.** `ClimateSimulator.SetRuntimeGenerationOverrides(temperatureOffsetC, precipitationMultiplierIgnored, seaLevelOffsetM)` shifts generation MSL and temperature; **`ClimateSimTuning`** exports document Earth-default calibration (e.g. `generation_sea_level_offset_m` for Whittaker balance at 512²). Prefer changing **named physical parameters** (maritime, orography, rain shadow, biases) over ad hoc global multipliers; see workspace rule *Earth as source of truth*.

**Storage / export.** Authoritative runtime state is the **`ClimateGrid` channels** (elevation, temperature, precipitation capped at 450 cm/yr, soil wetness, biome index, flow accumulation, downstream index, basin id). **EXR:** per-face height from baker; `export_packed_climate_exrs` (R=elevation m, G=°C, B=precip cm/yr, A=biome id) or `export_separate_climate_exrs` (including soil wetness and flow).

**Regression / Earth checks.** Headless **Godot** scripts under `tools/` validate zonal means and distributions vs. coarse Earth reference bands (e.g. `climate_latitude_validator.gd`, `earth_climate_alignment_report.gd`, `climate_soil_moisture_latitude_report.gd`, `biome_id_histogram_run.gd`). Run with `--headless` per `godot.path` / `GODOT` / PATH (see `.cursor/rules/godot-headless-path.mdc`). Editor aids: `whittaker_diagram_window.gd`, `latitude_curve_window.gd`, `debug_side_panel.gd` for live inspection.

**Player deltas (SQLite) vs. macro truth.** Procedural **base truth** still lives in **`ClimateGrid`** and optional **EXR** under `user://planet_data/`. **Per-cell overrides** for terraforming and future multiplayer sync are stored in a local **SQLite** file at **`user://planet_deltas.db`** (resolved via `ProjectSettings.GlobalizePath`), implemented in **C#** with **`Microsoft.Data.Sqlite`** (not GDScript addons or GDExtension). The static **`DatabaseManager`** exposes upserts, face-scoped reads, and apply helpers; **`PlanetBaseTruthBaker`** calls **`DatabaseManager.Initialize()`** in **`_Ready()`** and applies stored terrain edits after the detail-noise pass with **`ApplyTerrainDeltas`** so baked elevation reflects saved modifications. Climate overrides can be merged into packed maps via **`ApplyClimateDeltas`** when the pipeline needs them; entity rows in **`World_Entities`** are reserved for cities/structures.

1. **Low-Res Tectonic Generation:**  
   * Create a script to generate the Level 0 data (e.g., a $512 \\times 512$ grid per face).  
   * Implement basic noise to define base elevation (continents vs. oceans).  
   * **Implemented elaboration:** plate-based Voronoi with domain warp, optional convergent/rift kinematics, hypsometric exponents, and detail `FastNoiseLite` pass (`TectonicPlates`, `PlanetBaseTruthBaker`).  
2. **Climate & Biome Ticks:**  
   * Write the simulation logic for a single "Turn."  
   * Calculate rudimentary temperature (based on equator proximity) and moisture (simple wind rays interacting with elevation).  
   * **Implemented elaboration:** full pipeline above (lapse, maritime rays, orography, rain shadow, soil wetness, river routing); Whittaker biomes; export via `ClimateGrid` EXR helpers or packed arrays.  

#### Biome Parameter Boundaries (Moisture vs Temperature)

*Axes: **T** = mean annual temperature (°C), **P** = moisture in cm/year on the same numeric scale as precipitation. **Implemented:** `CalculateBiomes` feeds Whittaker with **`soil_wetness_map`** (post–flow-accumulation bonuses), not raw `precipitation_map`, so major rivers and bank-radius bonuses can shift a cell’s biome vs. precip-only diagrams. Land biomes **0…8** are quads in (T, P); `ClimateSimulator.WhittakerBiomeId()` uses Godot `Geometry2D.IsPointInPolygon` with test order **id 8 → 0** on shared edges, then **nearest centroid** if no polygon contains the point. **Ocean**: `h < 0`. **Ice** (id 9): `T < -15` °C (outside the diagram’s tundra left edge).*

| ID | Biome | Hex | Vertex 1 (BL) | Vertex 2 (BR) | Vertex 3 (TR) | Vertex 4 (TL) |
| :-- | :---- | :---- | :---- | :---- | :---- | :---- |
| 0 | Tundra | `#B8C7D1` | (−15, 0) | (−5, 0) | (−5, 120) | (−15, 40) |
| 1 | Boreal forest | `#2E6147` | (−5, 20) | (5, 55) | (5, 250) | (−5, 120) |
| 2 | Temperate grassland | `#AD9461` | (−5, 0) | (18, 0) | (18, 50) | (−5, 10) |
| 3 | Woodland / shrubland | `#B06B3D` | (−5, 10) | (18, 50) | (18, 100) | (−5, 20) |
| 4 | Seasonal forest | `#598C38` | (5, 55) | (18, 100) | (18, 250) | (5, 150) |
| 5 | Temp rainforest | `#1F7A6B` | (5, 150) | (18, 250) | (18, 450) | (5, 250) |
| 6 | Subtropical desert | `#D9B861` | (18, 0) | (30, 0) | (30, 50) | (18, 50) |
| 7 | Savannah | `#B89E47` | (18, 50) | (30, 50) | (30, 250) | (18, 250) |
| 8 | Tropical rainforest | `#0D6B38` | (18, 250) | (30, 250) | (30, 450) | (18, 450) |
| 9 | Ice | `#E0EBF5` | — | — | — | `T < -15` |
| 10 | Ocean (stored id) | `#14387A` | — | — | — | `h < 0` |

*Rendered ocean color on the globe is shader override `#0F2461`, not id 10.*

*Vertices are cached by the simulator's internal Whittaker polygon initialization.*

3. **The Delta Database Setup:**  
   * **Implemented:** **SQLite** via **`Microsoft.Data.Sqlite`** in **`DatabaseManager.cs`** (package reference on **`attempt-326.csproj`**).  
   * **Tables** (all `CREATE TABLE IF NOT EXISTS` at init): **`Modified_Terrain`** — `Face`, `X`, `Y`, `NewElevation`, **PK (Face, X, Y)**. **`Climate_Overrides`** — same key, **`TempOverride` / `PrecipOverride` / `BiomeOverride`** nullable for **partial** edits; upsert uses **`ON CONFLICT DO UPDATE`** with **`COALESCE`** so omitted fields keep prior values (older DBs with NOT NULL override columns are migrated once). **`World_Entities`** — `EntityID` (TEXT PK), `EntityType`, `Face`, `X`, `Y`, `EntityName`.  
   * **API (high level):** **`UpsertTerrainElevation`** / **`UpsertClimateOverride`** (`INSERT OR REPLACE` for terrain; parameterized **`$Face`**, **`$X`**, …). **`ApplyTerrainDeltas`** / **`ApplyClimateDeltas`** (`float[]` maps, **`index = y * res + x`**, **`WHERE Face = $Face`**). Read/write paths call **`Initialize()`** if needed and log failures with **`GD.PushError`**.  
   * **Bake wiring:** **`PlanetBaseTruthBaker`** initializes the DB in **`_Ready()`** and, after **`AddDetailNoiseToFaceWithProgress`** (or the no-detail path), applies **`ApplyTerrainDeltas`** per face at **`FACE_RES`**. Macro output still round-trips **without** relying on the DB when no rows exist; headless validators and `ClimateGrid` + EXR workflows are unchanged.

### **Phase 3: Micro-Interpolation & LOD (Client-Side Rendering)**

*Goal: Dynamically render the 100m high-resolution mesh only where the camera is looking.*

1. **The QuadTree Data Structure:**  
   * Implement the QuadTree logic in GDScript to divide the cube faces into smaller chunks based on the camera's altitude.  
2. **Horizon Culling & Screen-Space Optimization:**  
   * Integrate the dynamic bounding-sphere dot-product math to aggressively cull chunks that are over the horizon.  
3. **The Compute Shader Pipeline:**  
   * Write the GLSL Compute Shader.  
   * Pass the Macro-Simulation data and camera position to the GPU.  
   * Use FastNoiseLite on the GPU to upsample the low-res data into a detailed 100m vertex mesh.

### **Phase 4: Terraforming & The Turn-Based Loop**

*Goal: Allow players to change the world and synchronize those changes.*

1. **The Interaction Raycast:**  
   * Translate a mouse click on the screen to a specific 100m grid coordinate on the spherical mesh.  
2. **Local "Pending Actions":**  
   * Build the UI for players to select actions (Raise Mountains, Dry Climate, Build City).  
   * Store these actions in a local queue without immediately updating the global terrain.  
3. **The Resolution Phase:**  
   * Write the function that commits the Pending Actions to the SQLite database.  
   * Trigger a recalculation of the Phase 2 Climate macro-simulation to account for the new player-made geography.  
   * Force the Phase 3 Compute Shader to redraw the visible chunks using the updated database.

### **Phase 5: Aesthetics & The Export Pipeline**

*Goal: Turn the raw geometric data into a usable asset for tabletop campaigns.*

1. **Stylized Shaders:**  
   * Develop a custom Spatial Shader for the terrain. Replace realistic textures with stylized, map-like aesthetics (e.g., parchment overlays, contour lines, clear biome color coding) that fit seamlessly into a custom setting like CLASH.  
2. **The Orthographic Snap:**  
   * Add a camera toggle that moves from the perspective orbital view to a strict top-down Orthographic projection over a selected chunk.  
3. **High-Resolution 2D Export:**  
   * Implement a Godot Viewport capture script.  
   * Overlay a customizable square or hex grid on the orthographic view.  
   * Export the bounded view as a high-resolution .png or .webp file, perfectly scaled and ready to drop directly into Foundry VTT.

