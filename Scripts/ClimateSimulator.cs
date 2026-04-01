using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using Godot;

[GlobalClass]
public partial class ClimateSimulator : RefCounted
{
    private const float AnnualPrecipCmMax = 450.0f;
    public const int FaceCount = 6;

    private const float PlanetRadiusGameUnits = 335_000.0f;
    private const float MetersPerGameUnit = 10.0f;
    private const float StandardAtmosphereLapseCPerPlanetMeter = -6.5f / 1000.0f;
    private const float ZonalTempAmplitudeC = 50.0f;
    private const float ZonalTempOffsetC = -20.0f;
    private const float ZonalTempCosExponent = 1.2f;
    private const float LatitudeWobbleDegrees = 1.0f;
    private const float LatitudeWobbleNoiseFrequency = 2.0f;
    private static readonly FastNoiseLite LatitudeWobbleNoise = CreateLatitudeWobbleNoise();

    public static bool MaritimeEnabled { get; set; } = true;
    /// <summary>
    /// Power-law weight on the upwind geodesic: higher = more emphasis on ocean in the last part
    /// of the ~2.2 Mm fetch (air mass history nearer the target cell). 1 = linear along-ray; 2 ≈ Earth-like
    /// preference for recent maritime contact.
    /// </summary>
    public static float MoistureUpwindNearCellWeightPower { get; set; } = 2.0f;
    public static float MaritimeCoastPrecipFactor { get; set; } = 1.6f;
    public static float MaritimeInteriorPrecipFactor { get; set; } = 0.85f;
    public static float OrographicUpliftCmPerKm { get; set; } = 24.0f;
    public static float OrographicUpliftMaxCm { get; set; } = 150.0f;

    /// <summary>
    /// Rain-shadow strength: effective shadow = clamp(Scale * h_eff_m / max(geodesic_m, floor_m), 0, 1);
    /// land precip multiplier is (1 - shadow) before orographic uplift add.
    /// Calibrated to Earth-like leeward drying (e.g. Columbia Basin / eastern WA ~15–25 cm/yr behind ~2–3 km mean crests;
    /// Tibetan rain shadow; Atacama lee of Andes): prior defaults k=9 with 85 km floor under-dried typical ranges.
    /// </summary>
    public static float RainShadowHOverDScale { get; set; } = 14.0f;

    /// <summary>Minimum crest-to-cell geodesic (m) in shadow ratio — avoids blow-up; keep below ~50 km for Earth alignment.</summary>
    public static float RainShadowDistanceFloorM { get; set; } = 42_000.0f;

    /// <summary>Only terrain at or above this MSL elevation participates as an upwind barrier crest.</summary>
    public static float RainShadowBarrierElevMinM { get; set; } = 600.0f;

    /// <summary>Moisture-ray length (m) along geodesic toward upwind; ~2000–2500 km is typical maritime fetch to major ranges.</summary>
    public static float RainShadowUpwindRangeM { get; set; } = 2_200_000.0f;

    /// <summary>
    /// Blends zonal-flow hemisphere sign through the equator so <see cref="AtmosphericFlowComponents"/> is continuous.
    /// A hard step (latitude ≥ 0 → +1 else −1) flipped meridional wind and upwind moisture rays, causing a moisture seam at 0°.
    /// ~0.07 rad (~4°): behavior matches the old ±1 away from the ITCZ band.
    /// </summary>
    private const float EquatorWindHemisphereBlendRad = 0.07f;

    /// <summary>
    /// Extra mean-annual temperature (°C) on land in the subtropical high belt, where strong lapse cooling
    /// on plateaus otherwise leaves almost no cells in the warm-desert corner of the Whittaker diagram.
    /// Peaks near horse latitudes (~28°). Does not apply over ocean.
    /// </summary>
    public static float SubtropicalLandWarmBiasPeakC { get; set; } = 6.0f;
    public static float MidlatitudeLandWarmBiasPeakC { get; set; } = 2.2f;

    public static bool DebugLogBiomeHistogram { get; set; } = false;
    public static int MoistureUpwindSteps { get; set; } = 48;

    private static RiverGenerator _riverGenerator;
    private bool[] _generationOceanMaskCache = Array.Empty<bool>();
    private int _generationOceanMaskRes = -1;
    private int _generationOceanMaskCpf = -1;
    private int _generationOceanMaskCellCount = -1;
    private float _generationOceanMaskMsl = float.NaN;

    private static readonly Vector2I[] Neigh8Climate =
    [
        new Vector2I(1, 0),
        new Vector2I(-1, 0),
        new Vector2I(0, 1),
        new Vector2I(0, -1),
        new Vector2I(1, 1),
        new Vector2I(1, -1),
        new Vector2I(-1, 1),
        new Vector2I(-1, -1)
    ];

    private const float BarrierMaskNeg = -1.0e30f;
    private static readonly float PlanetRadiusM = PlanetRadiusGameUnits * MetersPerGameUnit;

    private static FastNoiseLite CreateLatitudeWobbleNoise()
    {
        FastNoiseLite noise = new FastNoiseLite();
        noise.Seed = 1337;
        noise.NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex;
        noise.FractalType = FastNoiseLite.FractalTypeEnum.None;
        noise.Set(FastNoiseLite.PropertyName.Frequency, LatitudeWobbleNoiseFrequency);
        return noise;
    }

    public enum BiomeID
    {
        TUNDRA,
        BOREAL_FOREST,
        TEMPERATE_GRASSLAND,
        TEMPERATE_SEASONAL_FOREST,
        TEMPERATE_RAINFOREST,
        SUBTROPICAL_DESERT,
        SAVANNAH,
        TROPICAL_SEASONAL_FOREST,
        TROPICAL_RAINFOREST,
        ICE,
        OCEAN,
    }

    private static Vector2[][] _whittakerPolys;
    private static Vector2[] _whittakerCentroids;
    private static readonly int[] WhittakerPolyTestOrder = [8, 7, 6, 5, 4, 3, 2, 1, 0];
    private static readonly object WhittakerLock = new();
    private const int OceanNeighborMajorityThreshold = 5;
    private const int OceanSpeckleNeighborThreshold = 3;
    public static float SeaLevelJitterEpsilonM { get; set; } = 2.0f;

    /// <summary>Runtime UI: added to every cell temperature (°C) after zonal + lapse.</summary>
    public static float GenerationTemperatureOffsetC { get; set; }

    /// <summary>Runtime UI: meters MSL shift for ocean mask, rivers, soil; positive = higher seas (more ocean).</summary>
    public static float GenerationSeaLevelOffsetM { get; set; }

    public void ApplyTuningPack(Godot.Collections.Dictionary p)
    {
        if (p == null)
        {
            return;
        }

        if (p.ContainsKey("maritime_enabled"))
            MaritimeEnabled = p["maritime_enabled"].AsBool();
        if (p.ContainsKey("moisture_upwind_near_cell_weight_power"))
            MoistureUpwindNearCellWeightPower = Mathf.Clamp(
                p["moisture_upwind_near_cell_weight_power"].AsSingle(),
                0.25f,
                8.0f
            );
        if (p.ContainsKey("maritime_coast_precip_factor"))
            MaritimeCoastPrecipFactor = p["maritime_coast_precip_factor"].AsSingle();
        if (p.ContainsKey("maritime_interior_precip_factor"))
            MaritimeInteriorPrecipFactor = p["maritime_interior_precip_factor"].AsSingle();
        if (p.ContainsKey("orographic_uplift_cm_per_km"))
            OrographicUpliftCmPerKm = p["orographic_uplift_cm_per_km"].AsSingle();
        if (p.ContainsKey("orographic_uplift_max_cm"))
            OrographicUpliftMaxCm = p["orographic_uplift_max_cm"].AsSingle();
        if (p.ContainsKey("rain_shadow_h_over_d_scale"))
            RainShadowHOverDScale = Mathf.Max(p["rain_shadow_h_over_d_scale"].AsSingle(), 0.01f);
        if (p.ContainsKey("rain_shadow_distance_floor_m"))
            RainShadowDistanceFloorM = Mathf.Max(p["rain_shadow_distance_floor_m"].AsSingle(), 1000.0f);
        if (p.ContainsKey("rain_shadow_barrier_elev_min_m"))
            RainShadowBarrierElevMinM = Mathf.Max(p["rain_shadow_barrier_elev_min_m"].AsSingle(), 0.0f);
        if (p.ContainsKey("rain_shadow_upwind_range_m"))
            RainShadowUpwindRangeM = Mathf.Max(p["rain_shadow_upwind_range_m"].AsSingle(), 50_000.0f);
        if (p.ContainsKey("subtropical_land_warm_bias_peak_c"))
            SubtropicalLandWarmBiasPeakC = Mathf.Clamp(
                p["subtropical_land_warm_bias_peak_c"].AsSingle(),
                0.0f,
                10.0f
            );
        if (p.ContainsKey("midlatitude_land_warm_bias_peak_c"))
            MidlatitudeLandWarmBiasPeakC = Mathf.Clamp(
                p["midlatitude_land_warm_bias_peak_c"].AsSingle(),
                0.0f,
                6.0f
            );
        if (p.ContainsKey("debug_log_biome_histogram"))
            DebugLogBiomeHistogram = p["debug_log_biome_histogram"].AsBool();
        if (p.ContainsKey("moisture_upwind_steps"))
            MoistureUpwindSteps = Mathf.Clamp(p["moisture_upwind_steps"].AsInt32(), 8, 256);
        if (p.ContainsKey("sea_level_jitter_epsilon_m"))
            SeaLevelJitterEpsilonM = Mathf.Max(p["sea_level_jitter_epsilon_m"].AsSingle(), 0.0f);
    }

    /// <summary>GDScript/UI: temperature offset and sea level for generation. Precip multiplier is ignored.</summary>
    public void SetRuntimeGenerationOverrides(float temperatureOffsetC, float precipitationMultiplier, float seaLevelOffsetM)
    {
        GenerationTemperatureOffsetC = temperatureOffsetC;
        GenerationSeaLevelOffsetM = seaLevelOffsetM;
        _generationOceanMaskRes = -1;
        _generationOceanMaskCache = Array.Empty<bool>();
        _generationOceanMaskMsl = float.NaN;
    }

    public void CalculateBaseTemperature(GodotObject grid, float tMax, float tMin, Callable progress = default)
    {
        if (!grid.Call("is_allocated").AsBool())
        {
            GD.PushError("ClimateSimulator.calculate_base_temperature: grid is not allocated");
            return;
        }
        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;
        bool[] oceanMask = GetOrBuildGenerationOceanMask(elevMap, res, cpf);
        CalculateBaseTemperature(grid, tMax, tMin, oceanMask, progress);
    }

    private void CalculateBaseTemperature(
        GodotObject grid,
        float tMax,
        float tMin,
        bool[] oceanMask,
        Callable progress = default
    )
    {
        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        float[] tempMap = grid.Get("temperature_map").AsFloat32Array();
        int res = grid.Get("face_resolution").AsInt32();
        float fRes = Mathf.Max(res, 1);
        int cpf = res * res;
        float msl = GenerationSeaLevelOffsetM;

        for (int face = 0; face < FaceCount; face++)
        {
            for (int y = 0; y < res; y++)
            {
                for (int x = 0; x < res; x++)
                {
                    Vector2 uv = new Vector2((x + 0.5f) / fRes, (y + 0.5f) / fRes);
                    Vector3 dir = CubeSphereMath.face_uv01_to_unit_direction(face, uv);
                    float latitudeRaw = (float)Mathf.Asin(Mathf.Clamp(dir.Y, -1.0f, 1.0f));
                    float latitude = WobbleLatitude(latitudeRaw, dir);
                    float t = AnalyticZonalTemperatureC(latitude);
                    int lin = face * cpf + y * res + x;
                    if (!oceanMask[lin])
                    {
                        float landModifier = 4.0f * Mathf.Cos(2.0f * latitude);
                        // cos(2λ) strongly cools continental polar cells; taper so highs match Earth better.
                        float absLatDeg = Mathf.Abs(Mathf.RadToDeg(latitude));
                        float poleTaper = Mathf.SmoothStep(44.0f, 78.0f, absLatDeg);
                        poleTaper = poleTaper * poleTaper * (3.0f - 2.0f * poleTaper);
                        landModifier *= Mathf.Lerp(1.0f, 0.54f, poleTaper);
                        t += landModifier;

                        float horseW = Mathf.Clamp(1.0f - Mathf.Abs(absLatDeg - 28.0f) / 12.0f, 0.0f, 1.0f);
                        horseW = horseW * horseW * (3.0f - 2.0f * horseW);
                        t += SubtropicalLandWarmBiasPeakC * horseW;

                        float midLatW = Mathf.Clamp(1.0f - Mathf.Abs(absLatDeg - 46.0f) / 14.0f, 0.0f, 1.0f);
                        midLatW = midLatW * midLatW * (3.0f - 2.0f * midLatW);
                        t += MidlatitudeLandWarmBiasPeakC * midLatW;

                        float itczLandW = Mathf.Clamp(1.0f - absLatDeg / 9.0f, 0.0f, 1.0f);
                        itczLandW = itczLandW * itczLandW * (3.0f - 2.0f * itczLandW);
                        t += 2.2f * itczLandW;
                    }
                    float elevM = elevMap[lin];
                    float elevAboveMslM = Mathf.Max(elevM - msl, 0.0f);
                    // Environmental lapse rate: -6.5 C per km above mean sea level.
                    t += elevAboveMslM * StandardAtmosphereLapseCPerPlanetMeter;
                    tempMap[lin] = t + GenerationTemperatureOffsetC;
                }
            }

            if (IsProgressCallable(progress))
                progress.CallDeferred(Variant.From((float)(face + 1) / FaceCount));
        }

        grid.Set("temperature_map", tempMap);
    }

    public static int GetWindDirection(float latitudeRad)
    {
        Vector2 flow = AtmosphericFlowComponents(latitudeRad);
        return flow.X < 0.0f ? -1 : 1;
    }

    private static void EnsureWhittakerPolygons()
    {
        lock (WhittakerLock)
        {
            if (_whittakerPolys != null)
                return;

            _whittakerPolys =
            [
                [new Vector2(-15, 0), new Vector2(-5, 0), new Vector2(-5, 120), new Vector2(-15, 40)],
                [new Vector2(-5, 20), new Vector2(5, 55), new Vector2(5, 250), new Vector2(-5, 120)],
                [new Vector2(-5, 10), new Vector2(20, 50), new Vector2(20, 100), new Vector2(-5, 20)],
                [new Vector2(5, 55), new Vector2(20, 100), new Vector2(20, 250), new Vector2(5, 150)],
                [new Vector2(5, 150), new Vector2(20, 250), new Vector2(20, 450), new Vector2(5, 250)],
                [new Vector2(-5, 0), new Vector2(40, 0), new Vector2(40, 50), new Vector2(20, 50), new Vector2(-5, 10)],
                [new Vector2(20, 50), new Vector2(40, 50), new Vector2(40, 100), new Vector2(20, 100)],
                [new Vector2(20, 100), new Vector2(20, 250), new Vector2(40, 250), new Vector2(40, 100)],
                [new Vector2(20, 250), new Vector2(40, 250), new Vector2(40, 450), new Vector2(20, 450)],
            ];
            _whittakerCentroids = new Vector2[_whittakerPolys.Length];
            for (int i = 0; i < _whittakerPolys.Length; i++)
            {
                Vector2 s = Vector2.Zero;
                foreach (Vector2 v in _whittakerPolys[i])
                    s += v;
                _whittakerCentroids[i] = s / _whittakerPolys[i].Length;
            }
        }
    }

    public static int WhittakerBiomeId(float tempC, float precipCm)
    {
        if (tempC < -15.0f)
            return (int)BiomeID.ICE;
        return WhittakerBiomeFromDiagram(tempC, precipCm);
    }

    private static int WhittakerBiomeFromDiagram(float tempC, float soilWetnessCm)
    {
        EnsureWhittakerPolygons();
        Vector2 pt = new Vector2(tempC, soilWetnessCm);
        int insideId = WhittakerPolygonAtPoint(pt);
        if (insideId >= 0)
            return insideId;

        // Uncovered Whittaker space in this model is expected at high precipitation.
        // Project vertically downward (constant temperature) to the highest polygon boundary hit.
        int projectedId = WhittakerVerticalDownProjectionBiome(tempC, soilWetnessCm);
        if (projectedId >= 0)
            return projectedId;

        // Secondary safety net: nearest centroid in 2D.
        int bestI = 0;
        float bestD = float.PositiveInfinity;
        for (int i = 0; i < _whittakerCentroids.Length; i++)
        {
            float d = (float)pt.DistanceSquaredTo(_whittakerCentroids[i]);
            if (d < bestD)
            {
                bestD = d;
                bestI = i;
            }
        }

        return bestI;
    }

    private static int WhittakerPolygonAtPoint(Vector2 pt)
    {
        foreach (int id in WhittakerPolyTestOrder)
        {
            if (Geometry2D.IsPointInPolygon(pt, _whittakerPolys[id]))
                return id;
        }

        return -1;
    }

    private static int WhittakerVerticalDownProjectionBiome(float tempC, float soilWetnessCm)
    {
        const float eps = 0.001f;
        float srcY = Mathf.Clamp(soilWetnessCm, 0.0f, AnnualPrecipCmMax);
        float bestY = float.NegativeInfinity;
        int bestI = 0;
        bool found = false;

        for (int i = 0; i < _whittakerPolys.Length; i++)
        {
            if (TryHighestVerticalIntersectionAtX(_whittakerPolys[i], tempC, srcY, out float yHit))
            {
                if (!found || yHit > bestY)
                {
                    bestY = yHit;
                    bestI = i;
                    found = true;
                }
            }
        }

        if (!found)
            return -1;

        // Probe just below the boundary to avoid edge-only ambiguities.
        float probeY = Mathf.Clamp(bestY - eps, 0.0f, AnnualPrecipCmMax);
        int insideId = WhittakerPolygonAtPoint(new Vector2(tempC, probeY));
        if (insideId >= 0)
            return insideId;

        return bestI;
    }

    private static bool TryHighestVerticalIntersectionAtX(Vector2[] poly, float x, float yLimit, out float yHit)
    {
        const float xEps = 0.0001f;
        yHit = float.NegativeInfinity;
        bool found = false;
        int n = poly.Length;
        for (int i = 0; i < n; i++)
        {
            Vector2 a = poly[i];
            Vector2 b = poly[(i + 1) % n];
            float ax = (float)a.X;
            float ay = (float)a.Y;
            float bx = (float)b.X;
            float by = (float)b.Y;

            float minX = MathF.Min(ax, bx) - xEps;
            float maxX = MathF.Max(ax, bx) + xEps;
            if (x < minX || x > maxX)
                continue;

            if (MathF.Abs(ax - bx) <= xEps)
            {
                if (MathF.Abs(x - ax) <= xEps)
                {
                    float edgeTop = MathF.Max(ay, by);
                    if (edgeTop <= yLimit && edgeTop > yHit)
                    {
                        yHit = edgeTop;
                        found = true;
                    }
                }
                continue;
            }

            float t = (x - ax) / (bx - ax);
            if (t < -xEps || t > 1.0f + xEps)
                continue;
            float y = ay + (by - ay) * t;
            if (y <= yLimit && y > yHit)
            {
                yHit = y;
                found = true;
            }
        }

        return found;
    }

    public void CalculateBiomes(GodotObject grid, Callable progress = default)
    {
        if (!grid.Call("is_allocated").AsBool())
        {
            GD.PushError("ClimateSimulator.calculate_biomes: grid is not allocated");
            return;
        }
        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;
        bool[] oceanMask = GetOrBuildGenerationOceanMask(elevMap, res, cpf);
        CalculateBiomes(grid, oceanMask, progress);
    }

    private void CalculateBiomes(GodotObject grid, bool[] oceanMask, Callable progress = default)
    {
        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        float[] tempMap = grid.Get("temperature_map").AsFloat32Array();
        float[] soilWetnessMap = grid.Get("soil_wetness_map").AsFloat32Array();
        float[] biomeMap = grid.Get("biome_index_map").AsFloat32Array();

        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;

        for (int face = 0; face < FaceCount; face++)
        {
            for (int y = 0; y < res; y++)
            {
                for (int x = 0; x < res; x++)
                {
                    int lin = face * cpf + y * res + x;
                    float bid = (float)BiomeID.OCEAN;
                    if (!oceanMask[lin])
                    {
                        float t0 = tempMap[lin];
                        float w0 = Mathf.Clamp(soilWetnessMap[lin], 0.0f, AnnualPrecipCmMax);
                        if (t0 < -15.0f)
                            bid = (float)BiomeID.ICE;
                        else
                            bid = WhittakerBiomeFromDiagram(t0, w0);
                    }

                    biomeMap[lin] = bid;
                }
            }

            if (IsProgressCallable(progress))
                progress.CallDeferred(Variant.From((float)(face + 1) / FaceCount));
        }

        grid.Set("biome_index_map", biomeMap);

        if (DebugLogBiomeHistogram)
            LogBiomeHistogram(grid);
    }

    public static long[] BiomeIdHistogram(GodotObject grid)
    {
        long[] hist = new long[16];
        if (!grid.Call("is_allocated").AsBool())
            return hist;

        float[] biomeMap = grid.Get("biome_index_map").AsFloat32Array();
        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;
        for (int face = 0; face < FaceCount; face++)
        {
            for (int y = 0; y < res; y++)
            {
                for (int x = 0; x < res; x++)
                {
                    int lin = face * cpf + y * res + x;
                    int bi = (int)Math.Floor(biomeMap[lin] + 0.5f);
                    bi = Mathf.Clamp(bi, 0, 15);
                    hist[bi]++;
                }
            }
        }

        return hist;
    }

    private static void LogBiomeHistogram(GodotObject grid)
    {
        long[] h = BiomeIdHistogram(grid);
        List<string> parts = [];
        int nIds = (int)BiomeID.OCEAN + 1;
        for (int i = 0; i < nIds; i++)
            parts.Add($"{i}={h[i]}");
        GD.Print("ClimateSimulator biome counts: ", string.Join(", ", parts));
    }

    public static float SampleElevationBilinearWorld(GodotObject grid, Vector3 dirUnit)
    {
        Vector3 p = dirUnit.Normalized();
        CubeSphereMath.FaceUV r = CubeSphereMath.unit_direction_to_face_uv01(p);
        int face = Mathf.Clamp(r.Face, 0, FaceCount - 1);
        Vector2 uv = r.Uv;
        uv.X = Mathf.Clamp(uv.X, 0.0f, 1.0f);
        uv.Y = Mathf.Clamp(uv.Y, 0.0f, 1.0f);
        int res = grid.Get("face_resolution").AsInt32();
        float[] elev = grid.Get("elevation_map").AsFloat32Array();
        int cpf = res * res;
        float d = Mathf.Max(res - 1, 1);
        float fx = (float)(uv.X * d);
        float fy = (float)(uv.Y * d);
        int x0 = Mathf.Clamp((int)Math.Floor(fx), 0, res - 2);
        int y0 = Mathf.Clamp((int)Math.Floor(fy), 0, res - 2);
        float tx = fx - x0;
        float ty = fy - y0;
        int stride = res;
        float e00 = elev[face * cpf + y0 * stride + x0];
        float e10 = elev[face * cpf + y0 * stride + (x0 + 1)];
        float e01 = elev[face * cpf + (y0 + 1) * stride + x0];
        float e11 = elev[face * cpf + (y0 + 1) * stride + (x0 + 1)];
        float e0 = Mathf.Lerp(e00, e10, tx);
        float e1 = Mathf.Lerp(e01, e11, tx);
        return Mathf.Lerp(e0, e1, ty);
    }

    public static float SampleElevationNearestWorld(GodotObject grid, Vector3 dirUnit)
    {
        int res = grid.Get("face_resolution").AsInt32();
        float[] elev = grid.Get("elevation_map").AsFloat32Array();
        int cpf = res * res;
        Vector3I c = CubeSphereMath.unit_direction_to_nearest_cell(res, dirUnit);
        int lin = c.X * cpf + c.Z * res + c.Y;
        return elev[lin];
    }

    private static float GreatCircleArcM(Vector3 dirA, Vector3 dirB)
    {
        Vector3 da = dirA.Normalized();
        Vector3 db = dirB.Normalized();
        float c = (float)Mathf.Clamp(da.Dot(db), -1.0f, 1.0f);
        return PlanetRadiusM * Mathf.Acos(c);
    }

    private static float MaskedBarrierElev(float elevM, float mountainElevMinM)
    {
        float aboveMslM = Mathf.Max(elevM, 0.0f);
        if (aboveMslM >= mountainElevMinM)
            return aboveMslM;
        return BarrierMaskNeg;
    }

    private static bool BarrierPreferred(int idxA, float elevA, int idxB, float elevB)
    {
        if (elevA > elevB)
            return true;
        if (elevA < elevB)
            return false;
        return idxA > idxB;
    }

    /// <summary>
    /// Zonal mean annual precipitation baseline vs latitude (ocean and land before land-only modifiers).
    /// Hadley peak at φ=0 set to <see cref="ZonalPrecipEquatorialPeakCmYear"/> cm/yr (cos^32 term + 0.1 mm/day offset; other Gaussians ≈ 0).
    /// P(φ) = A * cos^32(φ) + 3.8 * exp(-0.5 * ((|φ|-49)/10.5)^2) - 0.1 * exp(-0.5 * ((|φ|-28)/4.5)^2) + 0.1, A = peak_cm/36.5 - 0.1 mm/day.
    /// with φ in degrees; P is mm/day.
    /// Mean annual cm/yr = mm/day × 365 d/yr ÷ 10 mm/cm = ×36.5 for <see cref="WhittakerBiomeId"/> / grid storage.
    /// </summary>
    private const float ZonalPrecipEquatorialPeakCmYear = 350.0f;

    private static float AnalyticZonalPrecipBaseCm(float latitudeRad)
    {
        const float MmPerDayToAnnualCm = 36.5f;
        float hadleyCos32MmPerDay = ZonalPrecipEquatorialPeakCmYear / MmPerDayToAnnualCm - 0.1f;
        float absLatDeg = Mathf.Abs(Mathf.RadToDeg(latitudeRad));
        float cosLat = Mathf.Max(Mathf.Cos(latitudeRad), 0.0f);
        float cos32 = Mathf.Pow(cosLat, 32.0f);
        float temperateZ = (absLatDeg - 49.0f) / 10.5f;
        float temperate = 3.8f * Mathf.Exp(-0.5f * temperateZ * temperateZ);
        float subtropicDryZ = (absLatDeg - 28.0f) / 4.5f;
        float subtropicDryDip = 0.1f * Mathf.Exp(-0.5f * subtropicDryZ * subtropicDryZ);
        float pMmPerDay = hadleyCos32MmPerDay * cos32 + temperate - subtropicDryDip + 0.1f;
        return pMmPerDay * MmPerDayToAnnualCm;
    }

    private static float AnalyticZonalTemperatureC(float latitudeRad)
    {
        float cosLat = Mathf.Max(Mathf.Cos(latitudeRad), 0.0f);
        float cosPow = Mathf.Pow(cosLat, ZonalTempCosExponent);
        return ZonalTempAmplitudeC * cosPow + ZonalTempOffsetC;
    }

    private static float WobbleLatitude(float latitudeRad, Vector3 dirUnit)
    {
        float wobble = (float)LatitudeWobbleNoise.GetNoise3Dv(dirUnit) * LatitudeWobbleDegrees;
        float latDeg = Mathf.RadToDeg(latitudeRad) + wobble;
        latDeg = Mathf.Clamp(latDeg, -90.0f, 90.0f);
        return Mathf.DegToRad(latDeg);
    }

    /// <summary>
    /// Base zonal precipitation (cm/year) by latitude in degrees, before upwind-ocean maritime factor and rain-shadow terms.
    /// </summary>
    public static float SampleBasePrecipCmByLatitudeDeg(float latitudeDeg)
    {
        float latRad = Mathf.DegToRad(Mathf.Clamp(latitudeDeg, -90.0f, 90.0f));
        return AnalyticZonalPrecipBaseCm(latRad);
    }

    /// <summary>
    /// Base zonal temperature (deg C) by latitude in degrees, excluding land modifiers and lapse cooling.
    /// Includes the runtime generation temperature offset.
    /// </summary>
    public static float SampleBaseTemperatureCByLatitudeDeg(float latitudeDeg, float tMax, float tMin)
    {
        float latRad = Mathf.DegToRad(Mathf.Clamp(latitudeDeg, -90.0f, 90.0f));
        float t = AnalyticZonalTemperatureC(latRad);
        return t + GenerationTemperatureOffsetC;
    }

    private static bool[] BuildStableOceanMask(float[] elevMap, int res, int cpf, float msl)
    {
        int n = elevMap.Length;
        bool[] ocean = new bool[n];
        float eps = Mathf.Max(SeaLevelJitterEpsilonM, 0.0f);
        for (int i = 0; i < n; i++)
            ocean[i] = elevMap[i] < msl - eps;

        bool[] next = new bool[n];
        for (int face = 0; face < FaceCount; face++)
        {
            for (int y = 0; y < res; y++)
            {
                for (int x = 0; x < res; x++)
                {
                    int lin = face * cpf + y * res + x;
                    float h = elevMap[lin];
                    if (h >= msl + eps)
                    {
                        next[lin] = false;
                        continue;
                    }
                    if (h < msl - eps)
                    {
                        int oceanNbrDeep = 0;
                        foreach (Vector2I d in Neigh8Climate)
                        {
                            Vector3I nb = CubeSphereMath.climate_grid_neighbor(res, face, x, y, d.X, d.Y);
                            int nLin = nb.X * cpf + nb.Z * res + nb.Y;
                            if (ocean[nLin])
                                oceanNbrDeep++;
                        }

                        next[lin] = oceanNbrDeep >= OceanSpeckleNeighborThreshold;
                        continue;
                    }

                    int oceanNbr = 0;
                    foreach (Vector2I d in Neigh8Climate)
                    {
                        Vector3I nb = CubeSphereMath.climate_grid_neighbor(res, face, x, y, d.X, d.Y);
                        int nLin = nb.X * cpf + nb.Z * res + nb.Y;
                        if (elevMap[nLin] < msl)
                            oceanNbr++;
                    }

                    // Near sea level jitter band: require strong local ocean support.
                    next[lin] = oceanNbr >= OceanNeighborMajorityThreshold;
                }
            }
        }

        return next;
    }

    private bool[] GetOrBuildGenerationOceanMask(float[] elevMap, int res, int cpf)
    {
        int n = elevMap.Length;
        float msl = GenerationSeaLevelOffsetM;
        if (
            _generationOceanMaskCache.Length == n
            && _generationOceanMaskRes == res
            && _generationOceanMaskCpf == cpf
            && _generationOceanMaskCellCount == n
            && Mathf.IsEqualApprox(_generationOceanMaskMsl, msl)
        )
        {
            return _generationOceanMaskCache;
        }

        _generationOceanMaskCache = BuildStableOceanMask(elevMap, res, cpf, msl);
        _generationOceanMaskRes = res;
        _generationOceanMaskCpf = cpf;
        _generationOceanMaskCellCount = n;
        _generationOceanMaskMsl = msl;
        return _generationOceanMaskCache;
    }

    /// <summary>
    /// Maps land dryness from 0 (wet: strong upwind ocean on the wind ray) to 1 (dry: continental air path).
    /// </summary>
    private static float MaritimePrecipMultiplier(float landDrynessFromUpwind01)
    {
        if (!MaritimeEnabled)
            return 1.0f;
        float u = Mathf.Clamp(landDrynessFromUpwind01, 0.0f, 1.0f);
        u = u * u * (3.0f - 2.0f * u);
        return Mathf.Lerp(MaritimeCoastPrecipFactor, MaritimeInteriorPrecipFactor, u);
    }

    private static void WritePrecipCell(
        float[] precipitationMap,
        int face,
        int x,
        int y,
        bool isOceanHere,
        float upwindOceanFetch01,
        float crestElevM,
        Vector3 crestPos,
        Vector3 cellPos,
        float mountainElevMinM,
        float distanceFloorM,
        float shadowHOverD,
        float upliftDhM,
        int res,
        int cpf
    )
    {
        int lin = face * cpf + y * res + x;
        float fRes = Mathf.Max(res, 1);
        Vector2 uv = new Vector2((x + 0.5f) / fRes, (y + 0.5f) / fRes);
        Vector3 pVec = CubeSphereMath.face_uv01_to_unit_direction(face, uv);
        float latRaw = (float)Mathf.Asin(Mathf.Clamp(pVec.Y, -1.0f, 1.0f));
        float lat = WobbleLatitude(latRaw, pVec);
        float precipCm;
        if (isOceanHere)
        {
            precipCm = AnalyticZonalPrecipBaseCm(lat);
        }
        else
        {
            float shadow = 0.0f;
            float crestAboveMslM = Mathf.Max(crestElevM, 0.0f);
            if (crestAboveMslM >= mountainElevMinM)
            {
                float hEff = crestAboveMslM - mountainElevMinM;
                float dM = GreatCircleArcM(cellPos, crestPos);
                dM = Mathf.Max(dM, distanceFloorM);
                shadow = Mathf.Clamp(shadowHOverD * hEff / dM, 0.0f, 1.0f);
            }

            float landDryness = 1.0f - Mathf.Clamp(upwindOceanFetch01, 0.0f, 1.0f);
            float maritime = MaritimePrecipMultiplier(landDryness);
            float upliftCm = 0.0f;
            if (upliftDhM > 0.0f)
            {
                upliftCm = Mathf.Min(
                    OrographicUpliftCmPerKm * upliftDhM / 1000.0f,
                    OrographicUpliftMaxCm
                );
            }

            precipCm = AnalyticZonalPrecipBaseCm(lat) * maritime * (1.0f - shadow) + upliftCm;
        }

        precipitationMap[lin] = Mathf.Clamp(precipCm, 0.0f, AnnualPrecipCmMax);
    }

    private static Vector3 EastTangent(Vector3 p0)
    {
        Vector3 e = Vector3.Up.Cross(p0);
        if (e.LengthSquared() < 1e-24f)
            e = Vector3.Forward.Cross(p0);
        if (e.LengthSquared() < 1e-24f)
            return new Vector3(1, 0, 0);
        return e.Normalized();
    }

    private enum AtmosphericCell
    {
        Hadley,
        Ferrel,
        Polar,
    }

    private static AtmosphericCell CellForLatitudeDeg(float absLatDeg)
    {
        if (absLatDeg < 30.0f)
            return AtmosphericCell.Hadley;
        if (absLatDeg < 60.0f)
            return AtmosphericCell.Ferrel;
        return AtmosphericCell.Polar;
    }

    /// <summary>Smooth [-1, 1] hemisphere factor for wind; continuous at φ = 0 (unlike a raw sign bit).</summary>
    private static float HemisphereWindFactor(float latitudeRad)
    {
        float w = Mathf.Max(EquatorWindHemisphereBlendRad, 1e-8f);
        return Mathf.Clamp(latitudeRad / w, -1.0f, 1.0f);
    }

    // Returns (zonal-eastward, meridional-northward) lower-troposphere wind components.
    // Coriolis adds hemisphere-aware diagonal deflection within each circulation cell.
    private static Vector2 AtmosphericFlowComponents(float latitudeRad)
    {
        float absLatDeg = Mathf.Abs(Mathf.RadToDeg(latitudeRad));
        float hemi = HemisphereWindFactor(latitudeRad);
        AtmosphericCell cell = CellForLatitudeDeg(absLatDeg);

        float meridional = cell == AtmosphericCell.Ferrel ? hemi : -hemi;
        float easterlyBias = cell == AtmosphericCell.Ferrel ? 1.0f : -1.0f;
        float coriolis = Mathf.Clamp(absLatDeg / 90.0f, 0.0f, 1.0f);

        float zonal = easterlyBias * (0.45f + 0.55f * coriolis);
        zonal += 0.65f * hemi * meridional * coriolis;
        return new Vector2(zonal, meridional).Normalized();
    }

    private static Vector3 ZonalUpwindUnit(Vector3 p0, float latitudeRad)
    {
        Vector3 east = EastTangent(p0);
        Vector3 north = (Vector3.Up - p0 * p0.Dot(Vector3.Up)).Normalized();
        if (north.LengthSquared() < 1e-24f)
            north = Vector3.Zero;

        Vector2 flow = AtmosphericFlowComponents(latitudeRad);
        Vector3 downwind = (flow.X * east + flow.Y * north).Normalized();
        return -downwind;
    }

    private static void PrecipOneCellGeodesicZonal(
        int face,
        int x,
        int y,
        int kUse,
        float mMountain,
        float dFloorM,
        float kHOverD,
        float[] elevPath,
        float[] maskPath,
        Vector3[] posPath,
        int[] dqBuffer,
        float[] cosPath,
        float[] sinPath,
        float[] elevMap,
        int cpf,
        float[] precipitationMap,
        int res,
        bool[] oceanMask
    )
    {
        float fRes = Mathf.Max(res, 1);
        Vector2 uv = new Vector2((x + 0.5f) / fRes, (y + 0.5f) / fRes);
        Vector3 pCell = CubeSphereMath.face_uv01_to_unit_direction(face, uv);
        float lat = (float)Mathf.Asin(Mathf.Clamp(pCell.Y, -1.0f, 1.0f));
        Vector3 upDir = ZonalUpwindUnit(pCell, lat);
        int n = kUse + 1;
        float wOcean = 0.0f;
        float wSum = 0.0f;
        float pPow = Mathf.Max(MoistureUpwindNearCellWeightPower, 0.01f);
        int upwindSteps = Mathf.Max(n - 1, 1);
        for (int i = 0; i < n; i++)
        {
            Vector3 p = cosPath[i] * pCell + sinPath[i] * upDir;
            p = p.Normalized();
            posPath[i] = p;
            Vector3I c = CubeSphereMath.unit_direction_to_nearest_cell(res, p);
            int pathLin = c.X * cpf + c.Z * res + c.Y;
            float h = elevMap[pathLin];
            elevPath[i] = h;
            maskPath[i] = MaskedBarrierElev(h, mMountain);
            if (i < n - 1)
            {
                float t = (float)(i + 1) / upwindSteps;
                float w = Mathf.Pow(t, pPow);
                wSum += w;
                if (oceanMask[pathLin])
                    wOcean += w;
            }
        }

        float upwindOceanFetch01 = wSum > 1e-8f ? Mathf.Clamp(wOcean / wSum, 0.0f, 1.0f) : 0.0f;

        int dqHead = 0;
        int dqTail = 0;
        int iLast = n - 1;
        for (int i = 0; i < n; i++)
        {
            int winLo = Math.Max(i - kUse, 0);
            if (i > 0)
            {
                int newIdx = i - 1;
                float ne = maskPath[newIdx];
                while (dqTail > dqHead)
                {
                    int backI = dqBuffer[dqTail - 1];
                    if (BarrierPreferred(newIdx, ne, backI, maskPath[backI]))
                        dqTail -= 1;
                    else
                        break;
                }

                dqBuffer[dqTail] = newIdx;
                dqTail += 1;
            }

            while (dqTail > dqHead && dqBuffer[dqHead] < winLo)
                dqHead += 1;
            if (i != iLast)
                continue;

            Vector3 pos0 = posPath[iLast];
            int lin = face * cpf + y * res + x;
            bool isOceanHere = oceanMask[lin];
            float upliftOpen = 0.0f;
            if (iLast > 0)
                upliftOpen = elevPath[iLast] - elevPath[iLast - 1];
            float hCrest = mMountain - 1.0f;
            Vector3 pCrest = pos0;
            if (iLast > 0 && dqTail > dqHead)
            {
                int jc = dqBuffer[dqHead];
                hCrest = elevPath[jc];
                pCrest = posPath[jc];
            }

            WritePrecipCell(
                precipitationMap,
                face,
                x,
                y,
                isOceanHere,
                upwindOceanFetch01,
                hCrest,
                pCrest,
                pos0,
                mMountain,
                dFloorM,
                kHOverD,
                upliftOpen,
                res,
                cpf
            );
        }
    }

    public void CalculatePrecipitation(GodotObject grid, Callable progress = default)
    {
        if (!grid.Call("is_allocated").AsBool())
        {
            GD.PushError("ClimateSimulator.calculate_precipitation: grid is not allocated");
            return;
        }
        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;
        bool[] oceanMask = GetOrBuildGenerationOceanMask(elevMap, res, cpf);
        CalculatePrecipitation(grid, oceanMask, progress);
    }

    private void CalculatePrecipitation(GodotObject grid, bool[] oceanMask, Callable progress = default)
    {
        float mMountain = RainShadowBarrierElevMinM;
        float upwindRangeM = RainShadowUpwindRangeM;
        float distanceFloorM = RainShadowDistanceFloorM;
        float shadowHOverD = RainShadowHOverDScale;

        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        float[] precipitationMap = grid.Get("precipitation_map").AsFloat32Array();

        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;
        float cellWidthM = (float)((Mathf.Pi * PlanetRadiusM * 0.5f) / Mathf.Max(res, 1));
        int k = (int)Math.Ceiling(upwindRangeM / cellWidthM);
        k = Math.Clamp(k, 8, 512); // Prevent memory explosion, but allow smooth sampling
        float dAlpha = upwindRangeM / (k * Mathf.Max(PlanetRadiusM, 1.0f));

        Array.Fill(precipitationMap, 0.0f);

        int nBuf = k + 1;
        float[] cosPath = new float[nBuf];
        float[] sinPath = new float[nBuf];
        for (int i = 0; i < nBuf; i++)
        {
            float ang = (nBuf - 1 - i) * dAlpha;
            cosPath[i] = Mathf.Cos(ang);
            sinPath[i] = Mathf.Sin(ang);
        }

        for (int face = 0; face < FaceCount; face++)
        {
            int faceCopy = face;
            Parallel.For(0, res, y =>
            {
                float[] elevPath = new float[nBuf];
                Vector3[] posPath = new Vector3[nBuf];
                float[] maskPath = new float[nBuf];
                int[] dqBuffer = new int[nBuf];
                for (int x = 0; x < res; x++)
                {
                    PrecipOneCellGeodesicZonal(
                        faceCopy,
                        x,
                        y,
                        k,
                        mMountain,
                        distanceFloorM,
                        shadowHOverD,
                        elevPath,
                        maskPath,
                        posPath,
                        dqBuffer,
                        cosPath,
                        sinPath,
                        elevMap,
                        cpf,
                        precipitationMap,
                        res,
                        oceanMask
                    );
                }
            });

            if (IsProgressCallable(progress))
                progress.CallDeferred(Variant.From((float)(face + 1) / FaceCount));
        }

        grid.Set("precipitation_map", precipitationMap);
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static Vector3I ClimateCellNeighbor(int res, int face, int x, int y, int dx, int dy) =>
        CubeSphereMath.climate_grid_neighbor(res, face, x, y, dx, dy);

    private static bool IsProgressCallable(Callable progress) =>
        !(progress.Target == null && progress.Delegate == null);

    private sealed class RiverThreadScratch
    {
        public int[] QueueCells = Array.Empty<int>();
        public int[] QueueDist = Array.Empty<int>();
        public bool[] Visited = Array.Empty<bool>();

        public void EnsureCapacity(int n)
        {
            if (QueueCells.Length != n)
                QueueCells = new int[n];
            if (QueueDist.Length != n)
                QueueDist = new int[n];
            if (Visited.Length != n)
                Visited = new bool[n];
        }
    }

    private static void AtomicMax(float[] target, int idx, float value)
    {
        float current = target[idx];
        while (value > current)
        {
            float observed = Interlocked.CompareExchange(ref target[idx], value, current);
            if (observed == current)
                return;
            current = observed;
        }
    }

    public void CalculateSoilWetness(GodotObject grid, Godot.Collections.Dictionary p = null, Callable progress = default)
    {
        if (!grid.Call("is_allocated").AsBool())
        {
            GD.PushError("ClimateSimulator.calculate_soil_wetness: grid is not allocated");
            return;
        }

        p ??= new Godot.Collections.Dictionary();
        bool enabled = !p.ContainsKey("enabled") || p["enabled"].AsBool();
        if (!enabled)
        {
            if (IsProgressCallable(progress))
                progress.CallDeferred(Variant.From(1.0f));
            return;
        }

        float seaLevelM = GenerationSeaLevelOffsetM;
        float flowThreshold = Mathf.Max(p.ContainsKey("flow_threshold") ? p["flow_threshold"].AsSingle() : 1200.0f, 0.0f);
        float flowSaturation = Mathf.Max(p.ContainsKey("flow_saturation") ? p["flow_saturation"].AsSingle() : 6000.0f, flowThreshold + 1.0f);
        float bankBonusCm = Mathf.Max(p.ContainsKey("bank_bonus_cm") ? p["bank_bonus_cm"].AsSingle() : 15.0f, 0.0f);
        int radiusCells = Mathf.Clamp(p.ContainsKey("radius_cells") ? p["radius_cells"].AsInt32() : 2, 0, 8);
        float decayPerCell = Mathf.Clamp(p.ContainsKey("decay_per_cell") ? p["decay_per_cell"].AsSingle() : 0.55f, 0.0f, 1.0f);
        float aridPrecipCm = Mathf.Max(p.ContainsKey("arid_precip_cm") ? p["arid_precip_cm"].AsSingle() : 40.0f, 0.0f);
        float aridBonusScale = Mathf.Clamp(p.ContainsKey("arid_bonus_scale") ? p["arid_bonus_scale"].AsSingle() : 0.5f, 0.0f, 1.0f);
        float freezeStartC = p.ContainsKey("freeze_start_c") ? p["freeze_start_c"].AsSingle() : 0.0f;
        float freezeFullC = p.ContainsKey("freeze_full_c") ? p["freeze_full_c"].AsSingle() : -8.0f;
        float bankBlend = Mathf.Clamp(p.ContainsKey("bank_bonus_neighbor_blend") ? p["bank_bonus_neighbor_blend"].AsSingle() : 0.32f, 0.0f, 1.0f);

        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        float[] tempMap = grid.Get("temperature_map").AsFloat32Array();
        float[] precipitationMap = grid.Get("precipitation_map").AsFloat32Array();
        float[] soilWetnessMap = grid.Get("soil_wetness_map").AsFloat32Array();
        float[] flowAcc = grid.Get("flow_accumulation_map").AsFloat32Array();

        int n = grid.Call("total_cell_count").AsInt32();
        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;

        Array.Copy(precipitationMap, soilWetnessMap, n);

        int ringMax = radiusCells + 1;
        float[] ringBonus = new float[ringMax];
        ringBonus[0] = 1.0f;
        for (int d = 1; d < ringMax; d++)
            ringBonus[d] = ringBonus[d - 1] * decayPerCell;

        float[] bonusCm = new float[n];
        int reportStride = Math.Max((int)Math.Floor(n / 96.0), 4096);
        int progressCounter = 0;
        using ThreadLocal<RiverThreadScratch> scratchByThread = new ThreadLocal<RiverThreadScratch>(() => new RiverThreadScratch());
        Parallel.For(
            0,
            n,
            lin =>
            {
                if (elevMap[lin] < seaLevelM)
                    return;
                float q = flowAcc[lin];
                if (q < flowThreshold)
                    return;

                RiverThreadScratch scratch = scratchByThread.Value;
                scratch.EnsureCapacity(n);
                int[] qCells = scratch.QueueCells;
                int[] qDist = scratch.QueueDist;
                bool[] visited = scratch.Visited;

                float qn = Mathf.Clamp((q - flowThreshold) / (flowSaturation - flowThreshold), 0.0f, 1.0f);
                float seedW = 0.4f + 0.6f * Mathf.Sqrt(qn);
                float seedBonus = bankBonusCm * seedW;
                AtomicMax(bonusCm, lin, seedBonus);

                if (radiusCells > 0)
                {
                    int qt = 0;
                    int qh = 0;
                    qCells[qt] = lin;
                    qDist[qt] = 0;
                    qt += 1;
                    visited[lin] = true;

                    while (qh < qt)
                    {
                        int cLin = qCells[qh];
                        int cD = qDist[qh];
                        qh += 1;
                        if (cD >= radiusCells)
                            continue;
                        int cFace = (int)Math.Floor((float)cLin / cpf);
                        int cRem = cLin % cpf;
                        int cY = (int)Math.Floor((float)cRem / res);
                        int cX = cRem % res;
                        foreach (Vector2I dir in Neigh8Climate)
                        {
                            Vector3I nb = ClimateCellNeighbor(res, cFace, cX, cY, dir.X, dir.Y);
                            if (nb.X == cFace && nb.Y == cX && nb.Z == cY)
                                continue;
                            int nLin = nb.X * cpf + nb.Z * res + nb.Y;
                            if (nLin < 0 || nLin >= n)
                                continue;
                            if (elevMap[nLin] < seaLevelM || visited[nLin])
                                continue;
                            visited[nLin] = true;
                            int nd = cD + 1;
                            qCells[qt] = nLin;
                            qDist[qt] = nd;
                            qt += 1;
                            float b = seedBonus * ringBonus[nd];
                            AtomicMax(bonusCm, nLin, b);
                        }
                    }

                    for (int i = 0; i < qt; i++)
                        visited[qCells[i]] = false;
                }

                if (IsProgressCallable(progress))
                {
                    int done = Interlocked.Increment(ref progressCounter);
                    if (done % reportStride == 0)
                        progress.CallDeferred(Variant.From(0.5f * done / Mathf.Max(n, 1)));
                }
            }
        );

        if (bankBlend > 1e-5f)
        {
            float[] bonusSm = new float[n];
            for (int ls = 0; ls < n; ls++)
            {
                if (elevMap[ls] < seaLevelM)
                {
                    bonusSm[ls] = 0.0f;
                    continue;
                }

                int fS = (int)Math.Floor((float)ls / cpf);
                int remS = ls % cpf;
                int ys = (int)Math.Floor((float)remS / res);
                int xs = remS % res;
                float acc = bonusCm[ls];
                int cnts = 1;
                foreach (Vector2I dirs in Neigh8Climate)
                {
                    Vector3I nbs = ClimateCellNeighbor(res, fS, xs, ys, dirs.X, dirs.Y);
                    if (nbs.X == fS && nbs.Y == xs && nbs.Z == ys)
                        continue;
                    int nls = nbs.X * cpf + nbs.Z * res + nbs.Y;
                    if (nls < 0 || nls >= n || elevMap[nls] < seaLevelM)
                        continue;
                    acc += bonusCm[nls];
                    cnts += 1;
                }

                bonusSm[ls] = Mathf.Lerp(bonusCm[ls], acc / cnts, bankBlend);
            }

            bonusCm = bonusSm;
        }

        for (int lin2 = 0; lin2 < n; lin2++)
        {
            if (elevMap[lin2] < seaLevelM)
                continue;
            float b2 = bonusCm[lin2];
            if (b2 <= 0.0f)
                continue;
            float tempC = tempMap[lin2];
            float thawF = 1.0f;
            if (freezeStartC <= freezeFullC)
                thawF = tempC > freezeFullC ? 1.0f : 0.0f;
            else
                thawF = Mathf.Clamp((tempC - freezeFullC) / (freezeStartC - freezeFullC), 0.0f, 1.0f);
            if (thawF <= 0.0f)
                continue;
            float dryF = 1.0f;
            if (precipitationMap[lin2] < aridPrecipCm)
                dryF = aridBonusScale;
            float liftCm = b2 * thawF * dryF;
            soilWetnessMap[lin2] = Mathf.Clamp(soilWetnessMap[lin2] + liftCm, 0.0f, AnnualPrecipCmMax);
            if (IsProgressCallable(progress) && lin2 % reportStride == 0)
                progress.CallDeferred(Variant.From(0.5f + 0.5f * (lin2 + 1) / Mathf.Max(n, 1)));
        }

        if (IsProgressCallable(progress))
            progress.CallDeferred(Variant.From(1.0f));

        grid.Set("soil_wetness_map", soilWetnessMap);
    }

    public void CalculateFlowAccumulation(GodotObject grid, Callable progress = default)
    {
        _riverGenerator ??= new RiverGenerator();
        if (!grid.Call("is_allocated").AsBool())
        {
            GD.PushError("ClimateSimulator.calculate_flow_accumulation: grid is not allocated");
            return;
        }
        float[] elevMap = grid.Get("elevation_map").AsFloat32Array();
        int res = grid.Get("face_resolution").AsInt32();
        int cpf = res * res;
        bool[] oceanMask = GetOrBuildGenerationOceanMask(elevMap, res, cpf);
        _riverGenerator.CalculateFlowAccumulation(grid, oceanMask, progress);
    }
}
