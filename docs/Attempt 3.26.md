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
*6,700 km diameter. Uses a 2^16 grid (65,536 points). Resolution: approx 80 m real (~8 game units on this scale).*

1. **Low-Res Tectonic Generation:**  
   * Create a script to generate the Level 0 data (e.g., a $512 \\times 512$ grid per face).  
   * Implement basic noise to define base elevation (continents vs. oceans).  
2. **Climate & Biome Ticks:**  
   * Write the simulation logic for a single "Turn."  
   * Calculate rudimentary temperature (based on equator proximity) and moisture (simple wind rays interacting with elevation).  
   * Export these macro-states as highly compressed 2D arrays or image files.  

#### Biome Parameter Boundaries (Moisture vs Temperature)

*Axes: **T** = mean annual temperature (°C), **P** = mean annual precipitation (cm/year). Land biomes **0…8** are quads in (T, P); `ClimateSimulator.WhittakerBiomeId()` uses Godot `Geometry2D.IsPointInPolygon` with test order **id 8 → 0** on shared edges, then **nearest centroid** if no polygon contains the point. **Ocean**: `h < 0`. **Ice** (id 9): `T < -15` °C (outside the diagram’s tundra left edge).*

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
   * Integrate an **SQLite** database via GDExtension or a Godot addon.  
   * Create the initial tables: Modified\_Terrain, Climate\_Overrides, and World\_Entities (for cities/structures).

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

