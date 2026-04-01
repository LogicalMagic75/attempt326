using System;
using System.Collections.Generic;
using Godot;

[GlobalClass]
public partial class TectonicPlates : Godot.Resource
{
    private const float EARTH_MIN_ELEVATION_METERS = -11000.0f;
    private const float EARTH_MAX_ELEVATION_METERS = 8850.0f;

    [Export]
    public int GenerationSeed { get; set; } = 1;

    [ExportGroup("Domain warp")]
    [Export(PropertyHint.Range, "0.5,48.0,0.5,or_greater")]
    public float DomainWarpCoordScale { get; set; } = 3.0f;

    [Export(PropertyHint.Range, "0.0,0.55,0.005,or_greater")]
    public float DomainWarpStrength { get; set; } = 0.2f;

    [Export(PropertyHint.Range, "0.15,16.0,0.05,or_greater")]
    public float DomainWarpNoiseFrequency { get; set; } = 1.3f;

    [Export(PropertyHint.Range, "1,5,1")]
    public int DomainWarpFractalOctaves { get; set; } = 5;

    [Export(PropertyHint.Range, "0.0,1.25,0.01,or_greater")]
    public float DomainWarpMinSeedSeparationRad { get; set; } = 0.0f;

    [Export(PropertyHint.Range, "2,128,1,or_greater")]
    public int PlateCount { get; set; } = 30;

    [Export(PropertyHint.Range, "0.1,1.5,0.05,or_greater")]
    public float PlateSizeSigma { get; set; } = 0.45f;

    [ExportGroup("Relief Shaping")]
    [Export(PropertyHint.Range, "0.0,1.5,0.05,or_greater")]
    public float RoughnessStressInfluence { get; set; } = 0.75f;

    [Export(PropertyHint.Range, "0.5,4.0,0.05,or_greater")]
    public float RidgeSharpness { get; set; } = 2.0f;

    [Export(PropertyHint.Range, "0.0,0.35,0.005,or_greater")]
    public float OceanContinentUpliftInlandShift { get; set; } = 0.1f;

    [Export(PropertyHint.Range, "1.0,14.0,0.25,or_greater")]
    public float OldRangeFoldNoiseStretch { get; set; } = 6.0f;

    [Export(PropertyHint.Range, "0.0,1.0,0.01,or_greater")]
    public float LowlandSmoothing { get; set; } = 0.4f;

    [Export(PropertyHint.Range, "0.02,0.8,0.01,or_greater")]
    public float PlateBoundaryWidth { get; set; } = 0.18f;

    [Export(PropertyHint.Range, "0.0,1.0,0.02")]
    public float ReliefPeakOffsetFraction { get; set; } = 0.0f;

    [Export(PropertyHint.Range, "0.0,1.0,0.02")]
    public float RidgeInteriorAntiGutter { get; set; } = 0.0f;

    [ExportGroup("Boundary noise (pre-stress)")]
    [Export(PropertyHint.Range, "0.0,0.5,0.005,or_greater")]
    public float BoundaryNoiseStrength { get; set; } = 0.0f;

    [Export(PropertyHint.Range, "1.0,250.0,1.0,or_greater")]
    public float BoundaryNoiseCoordScale { get; set; } = 80.0f;

    [Export(PropertyHint.Range, "0.005,0.5,0.005,or_greater")]
    public float BoundaryNoiseFrequency { get; set; } = 0.12f;

    [ExportGroup("Plate kinematics (rift / convergence)")]
    [Export(PropertyHint.Range, "0.0,2.0,0.05,or_greater")]
    public float PlateKinematicStrength { get; set; } = 0.0f;

    [Export(PropertyHint.Range, "0.0,8000.0,50.0,or_greater")]
    public float ConvergentBoundaryUpliftM { get; set; } = 2800.0f;

    [Export(PropertyHint.Range, "0.0,6000.0,50.0,or_greater")]
    public float RiftBoundaryDepthM { get; set; } = 2200.0f;

    [Export(PropertyHint.Range, "0.15,1.5,0.05,or_greater")]
    public float BoundaryKinematicOceanScale { get; set; } = 0.18f;

    [Export(PropertyHint.Range, "0.5,2.5,0.05,or_greater")]
    public float BoundaryKinematicLandScale { get; set; } = 1.35f;

    [Export(PropertyHint.Range, "0.0,1.0,0.005,or_greater")]
    public float TargetLandAreaFraction { get; set; } = 0.25f;

    [Export(PropertyHint.Range, "0.0,1.2,0.05,or_greater")]
    public float PlateHeightVariance { get; set; } = 0.6f;

    [ExportGroup("Crust baselines")]
    [Export]
    public bool BinaryOceanLandCrust { get; set; } = true;

    [Export(PropertyHint.Range, "1500.0,14000.0,100.0,or_greater")]
    public float BinaryTectonicMetersPerNorm { get; set; } = 6200.0f;

    [Export(PropertyHint.Range, "-1.0,1.0,0.01")]
    public float OceanicBaseHeightNorm { get; set; } = -0.275f;

    [Export(PropertyHint.Range, "-1.0,1.0,0.01")]
    public float ContinentalBaseHeightNorm { get; set; } = 0.135f;

    [ExportGroup("Earth-like Hypsometry")]
    [Export(PropertyHint.Range, "0.4,2.0,0.05,or_greater")]
    public float OceanDepthExponent { get; set; } = 0.72f;

    [Export(PropertyHint.Range, "0.8,3.0,0.05,or_greater")]
    public float LandHeightExponent { get; set; } = 1.45f;

    [Export(PropertyHint.Range, "-0.4,0.4,0.01")]
    public float SeaLevelBias { get; set; } = -0.12f;

    private List<Godot.Vector3> _plateCenters = [];
    private List<float> _plateRadii = [];
    private List<float> _plateBaseHeights = [];
    private List<Godot.Vector3> _plateReliefPeaks = [];
    private Godot.FastNoiseLite _boundaryNoise;
    private Godot.FastNoiseLite _domainWarpNoise;
    /// <summary>Full 3D velocity per plate (magnitude = speed, direction = motion in embedding space).</summary>
    private List<Godot.Vector3> _plateVelocity = [];
    private List<float> _plateDensity = [];
    private List<float> _pairOpening = [];
    private float _kinematicOpeningDenom = 1.0f;

    private struct PlateMatch
    {
        public float BestMetric;
        public float SecondMetric;
        public int BestIndex;
        public int SecondIndex;
    }

    private struct BoundaryKinematics
    {
        public float Divergence;
        public float Shear;
    }

    public TectonicPlates()
    {
        _boundaryNoise = new Godot.FastNoiseLite();
        _domainWarpNoise = new Godot.FastNoiseLite();
    }

    private void ConfigureBoundaryNoise()
    {
        _boundaryNoise.Seed = GenerationSeed * 4729 + 31;
        _boundaryNoise.NoiseType = Godot.FastNoiseLite.NoiseTypeEnum.Simplex;
        _boundaryNoise.Set(Godot.FastNoiseLite.PropertyName.Frequency, BoundaryNoiseFrequency);
    }

    /// <summary>Deterministic symmetric hash for an unordered plate pair (boundary identity).</summary>
    private static uint HashBoundaryPair(int plateA, int plateB)
    {
        int lo = plateA < plateB ? plateA : plateB;
        int hi = plateA < plateB ? plateB : plateA;
        unchecked
        {
            uint x = (uint)(lo * 73856093 ^ hi * 19349663 ^ (lo + hi) * 83492791);
            x ^= x >> 16;
            x *= 2246822519u;
            x ^= x >> 13;
            x *= 3266489917u;
            x ^= x >> 16;
            return x;
        }
    }

    /// <summary>Simulated geological age of the range at this boundary, 0 = young, 1 = old.</summary>
    private static float RangeAgeFromPairHash(uint pairHash)
    {
        return (pairHash & 0xFFFFFFu) / 16777216.0f;
    }

    private float RawBoundaryNoiseAt(Godot.Vector3 noiseCoord)
    {
        return (float)_boundaryNoise.GetNoise3Dv(noiseCoord);
    }

    private float RawBoundaryNoise(Godot.Vector3 dir)
    {
        return RawBoundaryNoiseAt(dir * BoundaryNoiseCoordScale);
    }

    private void ConfigureDomainWarpNoise()
    {
        _domainWarpNoise.Seed = GenerationSeed * 4999 + 83;
        _domainWarpNoise.NoiseType = Godot.FastNoiseLite.NoiseTypeEnum.Simplex;
        _domainWarpNoise.Set(Godot.FastNoiseLite.PropertyName.Frequency, DomainWarpNoiseFrequency);
        int oct = Godot.Mathf.Clamp(DomainWarpFractalOctaves, 1, 5);
        if (oct <= 1)
        {
            _domainWarpNoise.FractalType = Godot.FastNoiseLite.FractalTypeEnum.None;
        }
        else
        {
            _domainWarpNoise.FractalType = Godot.FastNoiseLite.FractalTypeEnum.Fbm;
            _domainWarpNoise.FractalOctaves = oct;
            _domainWarpNoise.Set(Godot.FastNoiseLite.PropertyName.FractalGain, 0.5);
        }
    }

    private Godot.Vector3 DomainWarpUnitDirection(Godot.Vector3 p, float domainWarpStrength)
    {
        Godot.Vector3 u = p.Normalized();
        if (domainWarpStrength <= 0.0f)
        {
            return u;
        }

        float sc = DomainWarpCoordScale;
        float k = domainWarpStrength;
        Godot.Vector3 w = new Godot.Vector3(
            (float)_domainWarpNoise.GetNoise3Dv(u * sc),
            (float)_domainWarpNoise.GetNoise3Dv(u * sc + new Godot.Vector3(37.17f, 11.7f, 3.03f)),
            (float)_domainWarpNoise.GetNoise3Dv(u * sc + new Godot.Vector3(2.71f, 23.14f, 1.41f))
        ) * k;
        return (u + w).Normalized();
    }

    private Godot.Vector3 RejectSampleUnitDirection(Godot.RandomNumberGenerator rng, List<Godot.Vector3> existing, float minAngleRad)
    {
        float cMin = Godot.Mathf.Cos(minAngleRad);
        for (int attemptIdx = 0; attemptIdx < 2800; attemptIdx++)
        {
            Godot.Vector3 c = RandomUnitVector(rng);
            bool ok = true;
            for (int j = 0; j < existing.Count; j++)
            {
                if (existing[j].Dot(c) > cMin)
                {
                    ok = false;
                    break;
                }
            }

            if (ok)
            {
                return c;
            }
        }

        return RandomUnitVector(rng);
    }

    private List<bool> PlatesLandMaskForTargetArea(List<float> areas, float landTarget)
    {
        int n = areas.Count;
        List<int> order = new List<int>(n);
        for (int i = 0; i < n; i++)
        {
            order.Add(i);
        }

        order.Sort((a, b) => areas[b].CompareTo(areas[a]));
        float target = Godot.Mathf.Clamp(landTarget, 0.0f, 1.0f);
        float acc = 0.0f;
        List<bool> isLand = new List<bool>(n);
        for (int i = 0; i < n; i++)
        {
            isLand.Add(false);
        }

        for (int k = 0; k < n; k++)
        {
            int idx = order[k];
            if (acc >= target - 1e-9f)
            {
                break;
            }

            isLand[idx] = true;
            acc += areas[idx];
        }

        return isLand;
    }

    public void Regenerate()
    {
        Godot.RandomNumberGenerator rng = new Godot.RandomNumberGenerator();
        rng.Seed = (ulong)(GenerationSeed * 7919 + PlateCount * 37);

        List<float> weights = new List<float>(new float[PlateCount]);
        float weightSum = 0.0f;
        for (int i = 0; i < PlateCount; i++)
        {
            float w = Godot.Mathf.Exp(RandNormal(rng, 0.0f, PlateSizeSigma));
            w = Godot.Mathf.Clamp(w, 0.25f, 3.5f);
            weights[i] = w;
            weightSum += w;
        }

        if (weightSum <= 0.0f)
        {
            weightSum = 1.0f;
        }

        List<float> areas = new List<float>(new float[PlateCount]);
        for (int i = 0; i < PlateCount; i++)
        {
            areas[i] = weights[i] / weightSum;
        }

        List<bool> landPlate = PlatesLandMaskForTargetArea(areas, TargetLandAreaFraction);

        _plateCenters = [];
        _plateRadii = [];
        _plateBaseHeights = [];
        _plateReliefPeaks = [];
        _plateDensity = [];

        for (int i = 0; i < PlateCount; i++)
        {
            float areaFraction = weights[i] / weightSum;
            float radiusAngle = Godot.Mathf.Acos(1.0f - 2.0f * Godot.Mathf.Clamp(areaFraction, 0.0001f, 0.9999f));
            radiusAngle = Godot.Mathf.Clamp(radiusAngle, 0.35f, 2.6f);
            Godot.Vector3 center = DomainWarpMinSeedSeparationRad > 0.0f
                ? RejectSampleUnitDirection(rng, _plateCenters, DomainWarpMinSeedSeparationRad)
                : RandomUnitVector(rng);
            _plateCenters.Add(center);
            _plateRadii.Add(radiusAngle);

            Godot.Vector3 peakDir = center;
            if (ReliefPeakOffsetFraction > 0.0f)
            {
                Godot.Vector3 aux = RandomUnitVector(rng);
                Godot.Vector3 tang = aux - center * aux.Dot(center);
                if (tang.LengthSquared() > 1e-20f)
                {
                    tang = tang.Normalized();
                    float peakSlant = ReliefPeakOffsetFraction * Godot.Mathf.Clamp(radiusAngle * 0.55f, 0.08f, 0.95f);
                    peakDir = (center * Godot.Mathf.Cos(peakSlant) + tang * Godot.Mathf.Sin(peakSlant)).Normalized();
                }
            }

            _plateReliefPeaks.Add(peakDir);

            bool isOcean = !landPlate[i];
            float baseCenter = isOcean ? OceanicBaseHeightNorm : ContinentalBaseHeightNorm;
            // Oceanic crust is always denser than continental (g/cm³ scale); ranges do not overlap.
            float density = isOcean
                ? (float)rng.RandfRange(3.02f, 3.38f)
                : (float)rng.RandfRange(2.5f, 2.88f);
            _plateDensity.Add(density);
            if (BinaryOceanLandCrust)
            {
                _plateBaseHeights.Add(Godot.Mathf.Clamp(baseCenter, -0.9f, 0.9f));
            }
            else
            {
                float baseVariation = RandNormal(rng, 0.0f, 0.35f) * PlateHeightVariance;
                _plateBaseHeights.Add(Godot.Mathf.Clamp(baseCenter + baseVariation, -0.9f, 0.9f));
            }
        }

        _plateVelocity.Clear();
        float maxSpeed = 0.0f;
        for (int i = 0; i < PlateCount; i++)
        {
            if (PlateKinematicStrength <= 0.0f)
            {
                _plateVelocity.Add(Godot.Vector3.Zero);
            }
            else
            {
                Godot.Vector3 dir = RandomUnitVector(rng);
                if (dir.LengthSquared() > 1e-20f)
                {
                    dir = dir.Normalized();
                }
                else
                {
                    dir = Godot.Vector3.Right;
                }

                float speed = (float)rng.RandfRange(0.35f, 1.0f) * PlateKinematicStrength;
                Godot.Vector3 vel = dir * speed;
                _plateVelocity.Add(vel);
                maxSpeed = Godot.Mathf.Max(maxSpeed, speed);
            }
        }

        _kinematicOpeningDenom = Godot.Mathf.Max(
            Godot.Mathf.Max(maxSpeed * 0.9f, PlateKinematicStrength * 0.45f),
            0.0001f);

        BuildPairOpeningTable();
        ConfigureBoundaryNoise();
        ConfigureDomainWarpNoise();
    }

    private void BuildPairOpeningTable()
    {
        int n = PlateCount;
        if (PlateKinematicStrength <= 0.0f || n <= 1)
        {
            _pairOpening.Clear();
            return;
        }

        if (_plateCenters.Count != n || _plateVelocity.Count != n)
        {
            _pairOpening.Clear();
            return;
        }

        _pairOpening = new List<float>(new float[n * n]);
        for (int i = 0; i < n; i++)
        {
            _pairOpening[i * n + i] = 0.0f;
        }

        for (int i = 0; i < n; i++)
        {
            Godot.Vector3 cI = _plateCenters[i];
            for (int j = i + 1; j < n; j++)
            {
                Godot.Vector3 mid = cI + _plateCenters[j];
                float o = 0.0f;
                if (mid.LengthSquared() > 1e-24f)
                {
                    Godot.Vector3 pMid = mid.Normalized();
                    o = BoundaryOpeningRate(pMid, i, j);
                }

                _pairOpening[i * n + j] = o;
                _pairOpening[j * n + i] = o;
            }
        }
    }

    public Godot.Vector4 Sample(Godot.Vector3 direction)
    {
        return Sample(direction, true, true);
    }

    public Godot.Vector4 Sample(Godot.Vector3 direction, bool enableDomainWarpNoise, bool enableBoundaryNoise)
    {
        Godot.Vector3 dir = direction.Normalized();
        float effectiveDomainWarpStrength = enableDomainWarpNoise ? DomainWarpStrength : 0.0f;
        float effectiveBoundaryNoiseStrength = enableBoundaryNoise ? BoundaryNoiseStrength : 0.0f;
        int sampleCount = GetPlateSampleCount();
        if (sampleCount <= 0)
        {
            return new Godot.Vector4(0.0f, 0.0f, 0.0f, 0.0f);
        }

        PlateMatch plateMatch = FindPrimaryPlateMetrics(dir, sampleCount, effectiveDomainWarpStrength);
        float bestMetric = plateMatch.BestMetric;
        float secondMetric = plateMatch.SecondMetric;
        int bestIndex = plateMatch.BestIndex;
        if (effectiveBoundaryNoiseStrength > 0.0f && float.IsFinite(secondMetric))
        {
            float bn = RawBoundaryNoise(dir);
            float delta = bn * effectiveBoundaryNoiseStrength * PlateBoundaryWidth * 3.0f;
            secondMetric = Godot.Mathf.Max(secondMetric - delta, bestMetric);
        }

        float stress = ComputePlateBoundaryStress(bestMetric, secondMetric);
        int clampedIndex = Godot.Mathf.Clamp(bestIndex, 0, sampleCount - 1);
        int secondIndex = plateMatch.SecondIndex;
        int secondClamped = Godot.Mathf.Clamp(secondIndex, 0, sampleCount - 1);
        float opening = 0.0f;
        float shear = 0.0f;
        if (PlateKinematicStrength > 0.0f && float.IsFinite(secondMetric) && clampedIndex != secondClamped)
        {
            int n = PlateCount;
            if (_pairOpening.Count == n * n && clampedIndex < n && secondClamped < n)
            {
                opening = _pairOpening[clampedIndex * n + secondClamped];
                BoundaryKinematics ks = ComputeBoundaryKinematics(dir, clampedIndex, secondClamped);
                shear = ks.Shear;
            }
            else
            {
                BoundaryKinematics ks = ComputeBoundaryKinematics(dir, clampedIndex, secondClamped);
                opening = ks.Divergence;
                shear = ks.Shear;
            }
        }

        float secondBase = PlateRefForIndex(secondClamped);
        Godot.Vector3 q = DomainWarpUnitDirection(dir, effectiveDomainWarpStrength);
        float interiorMetric = bestMetric;
        if (clampedIndex < _plateReliefPeaks.Count && clampedIndex < _plateRadii.Count)
        {
            Godot.Vector3 pk = _plateReliefPeaks[clampedIndex];
            float angPeak = (float)Godot.Mathf.Acos(Godot.Mathf.Clamp(q.Dot(pk), -1.0f, 1.0f));
            interiorMetric = angPeak / Godot.Mathf.Max(_plateRadii[clampedIndex], 0.01f);
        }

        float elevationM = ComputePlateElevationMeters(
            interiorMetric,
            stress,
            _plateBaseHeights[clampedIndex],
            opening,
            shear,
            clampedIndex,
            secondBase,
            secondClamped,
            dir
        );
        return new Godot.Vector4(elevationM, clampedIndex, stress, opening);
    }

    private int GetPlateSampleCount()
    {
        return Godot.Mathf.Min(Godot.Mathf.Min(_plateCenters.Count, _plateRadii.Count), _plateBaseHeights.Count);
    }

    private float PlateRefForIndex(int idx)
    {
        if (idx >= 0 && idx < _plateBaseHeights.Count)
        {
            return _plateBaseHeights[idx];
        }

        return OceanicBaseHeightNorm;
    }

    private bool IsOceanicPlateIndex(int idx)
    {
        if (idx < 0 || idx >= _plateBaseHeights.Count)
        {
            return true;
        }

        float crustMidpoint = (OceanicBaseHeightNorm + ContinentalBaseHeightNorm) * 0.5f;
        return _plateBaseHeights[idx] <= crustMidpoint;
    }

    private float RandNormal(Godot.RandomNumberGenerator rng, float mean, float sigma)
    {
        float u1 = Godot.Mathf.Max((float)rng.Randf(), 0.00001f);
        float u2 = (float)rng.Randf();
        float z0 = (float)(Godot.Mathf.Sqrt(-2.0f * Godot.Mathf.Log(u1)) * Godot.Mathf.Cos(Godot.Mathf.Tau * u2));
        return mean + z0 * sigma;
    }

    private Godot.Vector3 RandomUnitVector(Godot.RandomNumberGenerator rng)
    {
        float z = (float)rng.RandfRange(-1.0f, 1.0f);
        float t = (float)rng.RandfRange(0.0f, Godot.Mathf.Tau);
        float r = (float)Godot.Mathf.Sqrt(Godot.Mathf.Max(0.0f, 1.0f - z * z));
        return new Godot.Vector3(r * Godot.Mathf.Cos(t), z, r * Godot.Mathf.Sin(t));
    }

    private float ApplyHypsometricCurve(float heightNorm)
    {
        float clamped = Godot.Mathf.Clamp(heightNorm, -1.0f, 1.0f);
        if (clamped < 0.0f)
        {
            return -Godot.Mathf.Pow(-clamped, Godot.Mathf.Max(OceanDepthExponent, 0.05f));
        }

        return Godot.Mathf.Pow(clamped, Godot.Mathf.Max(LandHeightExponent, 0.05f));
    }

    private PlateMatch FindPrimaryPlateMetrics(Godot.Vector3 direction, int sampleCount, float domainWarpStrength)
    {
        float bestMetric = float.PositiveInfinity;
        float secondMetric = float.PositiveInfinity;
        int bestIndex = 0;
        int secondIndex = 0;
        Godot.Vector3 q = DomainWarpUnitDirection(direction, domainWarpStrength);
        for (int i = 0; i < sampleCount; i++)
        {
            Godot.Vector3 center = _plateCenters[i];
            float radiusAngle = _plateRadii[i];
            float dotVal = (float)Godot.Mathf.Clamp(q.Dot(center), -1.0f, 1.0f);
            float angle = (float)Godot.Mathf.Acos(dotVal);
            float metric = angle / Godot.Mathf.Max(radiusAngle, 0.01f);
            if (metric < bestMetric)
            {
                secondMetric = bestMetric;
                secondIndex = bestIndex;
                bestMetric = metric;
                bestIndex = i;
            }
            else if (metric < secondMetric)
            {
                secondMetric = metric;
                secondIndex = i;
            }
        }

        return new PlateMatch
        {
            BestMetric = bestMetric,
            SecondMetric = secondMetric,
            BestIndex = bestIndex,
            SecondIndex = secondIndex
        };
    }

    private float ComputePlateBoundaryStress(float bestMetric, float secondMetric)
    {
        float boundaryGap = Godot.Mathf.Max(secondMetric - bestMetric, 0.0f);
        return Godot.Mathf.Clamp(1.0f - boundaryGap / Godot.Mathf.Max(PlateBoundaryWidth, 0.001f), 0.0f, 1.0f);
    }

    private Godot.Vector3 SeparationTangent(Godot.Vector3 p, Godot.Vector3 cA, Godot.Vector3 cB)
    {
        Godot.Vector3 chord = cB - cA;
        Godot.Vector3 n = chord - p * chord.Dot(p);
        return n;
    }

    /// <summary>Velocity of a rigid plate with 3D velocity V at unit surface point p (tangent projection).</summary>
    private static Godot.Vector3 TangentVelocityFromPlateVelocity(Godot.Vector3 plateVelocity, Godot.Vector3 p)
    {
        Godot.Vector3 pn = p.Normalized();
        return plateVelocity - pn * plateVelocity.Dot(pn);
    }

    private float BoundaryOpeningRate(Godot.Vector3 p, int idxA, int idxB)
    {
        BoundaryKinematics k = ComputeBoundaryKinematics(p, idxA, idxB);
        return k.Divergence;
    }

    private BoundaryKinematics ComputeBoundaryKinematics(Godot.Vector3 p, int idxA, int idxB)
    {
        if (PlateKinematicStrength <= 0.0f || idxA == idxB)
        {
            return new BoundaryKinematics { Divergence = 0.0f, Shear = 0.0f };
        }

        if (idxA < 0 || idxB < 0 || idxA >= PlateCount || idxB >= PlateCount)
        {
            return new BoundaryKinematics { Divergence = 0.0f, Shear = 0.0f };
        }

        if (_plateCenters.Count != PlateCount || _plateVelocity.Count != PlateCount)
        {
            return new BoundaryKinematics { Divergence = 0.0f, Shear = 0.0f };
        }

        Godot.Vector3 cA = _plateCenters[idxA];
        Godot.Vector3 cB = _plateCenters[idxB];
        Godot.Vector3 n = SeparationTangent(p, cA, cB);
        float nLenSq = (float)n.LengthSquared();
        if (nLenSq < 1e-16f)
        {
            return new BoundaryKinematics { Divergence = 0.0f, Shear = 0.0f };
        }

        n /= Godot.Mathf.Sqrt(nLenSq);
        Godot.Vector3 pN = p.Normalized();
        Godot.Vector3 vA = TangentVelocityFromPlateVelocity(_plateVelocity[idxA], pN);
        Godot.Vector3 vB = TangentVelocityFromPlateVelocity(_plateVelocity[idxB], pN);
        Godot.Vector3 vRel = vA - vB;

        // Opening vs closing along the inter-plate normal: divergent if vRel·n > 0.
        float dotOpen = (float)vRel.Dot(n);
        // Shear / strike-slip intensity in the tangent plane (|v × n| = |v| sin θ for θ in tangent plane).
        float crossMag = (float)vRel.Cross(n).Length();

        float denom = Godot.Mathf.Max(_kinematicOpeningDenom, 0.0001f);
        return new BoundaryKinematics
        {
            Divergence = Godot.Mathf.Clamp(dotOpen / denom, -1.0f, 1.0f),
            Shear = Godot.Mathf.Clamp(crossMag / denom, 0.0f, 1.0f)
        };
    }

    private float ComputePlateElevationMeters(
        float interiorRadialMetric,
        float stress,
        float @base,
        float boundaryDivergence = 0.0f,
        float boundaryShear = 0.0f,
        int plateIdx = -1,
        float secondBase = 0.0f,
        int secondPlateIdx = -1,
        Godot.Vector3 boundaryDirection = default
    )
    {
        float plateRef = @base;
        if (BinaryOceanLandCrust && plateIdx >= 0 && plateIdx < _plateBaseHeights.Count)
        {
            plateRef = _plateBaseHeights[plateIdx];
        }

        float meanBoundaryRef = (plateRef + secondBase) * 0.5f;
        float crustSpan = Godot.Mathf.Max(ContinentalBaseHeightNorm - OceanicBaseHeightNorm, 0.05f);
        float landness = Godot.Mathf.Clamp((meanBoundaryRef - OceanicBaseHeightNorm) / crustSpan, 0.0f, 1.0f);
        float boundaryKScale = Godot.Mathf.Lerp(BoundaryKinematicOceanScale, BoundaryKinematicLandScale, landness);

        float normalizedDistance = Godot.Mathf.Clamp(interiorRadialMetric, 0.0f, 2.0f);
        float interiorFactor = Godot.Mathf.Clamp(1.0f - normalizedDistance * 0.55f, 0.0f, 1.0f);
        float baseHeightNorm = (plateRef + 1.0f) * 0.5f;
        float mountainFactor = Godot.Mathf.Clamp(baseHeightNorm * 0.65f + stress * RoughnessStressInfluence, 0.0f, 1.0f);
        Godot.Vector3 dir = boundaryDirection;
        if (dir.LengthSquared() < 1e-24f)
        {
            dir = Godot.Vector3.Up;
        }
        else
        {
            dir = dir.Normalized();
        }

        int nPlates = PlateCount;
        bool validPair = plateIdx >= 0 && secondPlateIdx >= 0 && plateIdx != secondPlateIdx
            && plateIdx < nPlates && secondPlateIdx < nPlates
            && _plateCenters.Count == nPlates;
        uint pairHash = validPair ? HashBoundaryPair(plateIdx, secondPlateIdx) : 0u;
        float rangeAge = validPair ? RangeAgeFromPairHash(pairHash) : 0.5f;
        float youngSharpBlend = Godot.Mathf.Clamp((0.3f - rangeAge) / 0.3f, 0.0f, 1.0f);
        float oldSmoothBlend = Godot.Mathf.Clamp((rangeAge - 0.7f) / 0.3f, 0.0f, 1.0f);
        float effRidgeSharpness = Godot.Mathf.Clamp(
            RidgeSharpness * (1.0f + 0.48f * youngSharpBlend - 0.45f * oldSmoothBlend),
            0.2f,
            5.5f
        );
        float foldAlongTangent = Godot.Mathf.SmoothStep(0.65f, 1.0f, rangeAge) * OldRangeFoldNoiseStretch;
        Godot.Vector3 noiseCoord = dir * BoundaryNoiseCoordScale;
        if (validPair && foldAlongTangent > 0.02f)
        {
            Godot.Vector3 tProj = SeparationTangent(dir, _plateCenters[plateIdx], _plateCenters[secondPlateIdx]);
            tProj = tProj - dir * dir.Dot(tProj);
            if (tProj.LengthSquared() > 1e-16f)
            {
                tProj = tProj.Normalized();
                noiseCoord = dir * BoundaryNoiseCoordScale + tProj * BoundaryNoiseCoordScale * foldAlongTangent;
            }
        }

        float islandMask = RawBoundaryNoiseAt(noiseCoord);
        float islandMask01 = Godot.Mathf.Clamp(islandMask * 0.5f + 0.5f, 0.0f, 1.0f);

        // 2. Identify deep oceanic gaps
        bool isOceanicBoundary = landness < 0.42f;
        bool isGap = isOceanicBoundary && islandMask01 < 0.5f;

        // 3. Suppress the universal base uplift completely in the gaps
        float baseUpliftMask = isGap ? 0.0f : 1.0f;
        float uplift = Godot.Mathf.Pow(stress, Godot.Mathf.Max(effRidgeSharpness, 0.05f)) * Godot.Mathf.Lerp(0.2f, 1.0f, mountainFactor) * baseUpliftMask;
        if (PlateKinematicStrength > 0.0f)
        {
            float d = boundaryDivergence;
            if (d < -0.02f)
            {
                // Convergent: Allow uplift
                uplift *= Godot.Mathf.Lerp(0.4f, 1.12f, landness);
            }
            else if (d > 0.02f)
            {
                // Divergent (Rift): Zero out base uplift completely so Phase 2 can carve the trench
                uplift = 0.0f;
            }
            else
            {
                // Transform or dead/locked boundaries should avoid broad ridge-like uplift.
                bool deadLocked = Godot.Mathf.Abs(d) < 0.01f && boundaryShear < 0.01f;
                uplift *= deadLocked ? 0.01f : 0.05f;
            }
        }
        else
        {
            // If kinematics are completely off, prevent the universal plateau
            uplift *= 0.1f;
        }

        float interiorGain = Godot.Mathf.Lerp(0.18f, 0.42f, mountainFactor);
        float interiorBump = interiorFactor * interiorGain;
        float upliftBump = uplift * 0.58f;
        float reliefBump = interiorBump + upliftBump;
        if (RidgeInteriorAntiGutter > 0.0f)
        {
            float mx = Godot.Mathf.Max(interiorBump, upliftBump);
            reliefBump = Godot.Mathf.Lerp(reliefBump, mx, RidgeInteriorAntiGutter);
        }

        float heightNorm = Godot.Mathf.Clamp(plateRef + reliefBump, -1.0f, 1.0f);
        float smoothMix = (1.0f - mountainFactor) * Godot.Mathf.Clamp(LowlandSmoothing, 0.0f, 1.0f);
        heightNorm = Godot.Mathf.Lerp(heightNorm, plateRef, smoothMix);

        float meters;
        if (BinaryOceanLandCrust)
        {
            // In binary crust mode, bypass hypsometric shaping entirely.
            meters = heightNorm * BinaryTectonicMetersPerNorm;
        }
        else
        {
            float shiftedHeightNorm = Godot.Mathf.Clamp(heightNorm + SeaLevelBias, -1.0f, 1.0f);
            float earthLikeHeightNorm = ApplyHypsometricCurve(shiftedHeightNorm);
            float t = (earthLikeHeightNorm + 1.0f) * 0.5f;
            meters = Godot.Mathf.Lerp(EARTH_MIN_ELEVATION_METERS, EARTH_MAX_ELEVATION_METERS, t);
        }

        if (PlateKinematicStrength > 0.0f)
        {
            float edgeWeight = stress * stress * boundaryKScale;
            float divergenceMag = Godot.Mathf.Abs(boundaryDivergence);

            float convergentWeight = Godot.Mathf.Clamp(-boundaryDivergence, 0.0f, 1.0f);
            float divergentWeight = Godot.Mathf.Clamp(boundaryDivergence, 0.0f, 1.0f);

            float upliftMask = isOceanicBoundary
                ? (isGap ? 0.0f : Godot.Mathf.SmoothStep(0.5f, 1.0f, islandMask01))
                : Godot.Mathf.SmoothStep(0.2f, 1.0f, islandMask01);

            bool plateContinental = !IsOceanicPlateIndex(plateIdx);
            bool secondContinental = !IsOceanicPlateIndex(secondPlateIdx);
            bool continentContinent = plateContinental && secondContinental;
            if (continentContinent && convergentWeight > 0.0f && validPair)
            {
                int hinterlandPlate = ((pairHash >> 17) & 1u) == 0u
                    ? Godot.Mathf.Min(plateIdx, secondPlateIdx)
                    : Godot.Mathf.Max(plateIdx, secondPlateIdx);
                float edgeLow = plateIdx == hinterlandPlate ? 0.035f : 0.22f;
                upliftMask = Godot.Mathf.SmoothStep(edgeLow, 1.0f, islandMask01);
            }

            float trenchMask = 1.0f - upliftMask;

            float oceanicUpliftScale = isOceanicBoundary ? 0.3f : 1.0f;
            float convStressExpBase = Godot.Mathf.Lerp(5.4f, 2.05f, Godot.Mathf.SmoothStep(0.22f, 0.78f, rangeAge));
            float stressExponent = isOceanicBoundary ? convStressExpBase + 0.55f : convStressExpBase;

            bool hasDensityPair = plateIdx >= 0
                && secondPlateIdx >= 0
                && plateIdx < _plateDensity.Count
                && secondPlateIdx < _plateDensity.Count;

            float stressForConvergent = stress;
            if (validPair && convergentWeight > 0.0f && OceanContinentUpliftInlandShift > 0.0f && hasDensityPair && !continentContinent)
            {
                bool ocPair = plateContinental != secondContinental;
                if (ocPair && plateContinental)
                {
                    float dHere = _plateDensity[plateIdx];
                    float dOther = _plateDensity[secondPlateIdx];
                    bool lighterHere = dHere < dOther - 1e-5f
                        || (Godot.Mathf.Abs(dHere - dOther) < 1e-5f && plateIdx < secondPlateIdx);
                    if (lighterHere)
                    {
                        float sh = Godot.Mathf.Clamp(OceanContinentUpliftInlandShift, 0.0f, 0.35f);
                        stressForConvergent = Godot.Mathf.Clamp(
                            stress - sh * Godot.Mathf.Pow(stress, 2.35f),
                            0.0f,
                            1.0f
                        );
                    }
                }
            }

            float stressFalloff = Godot.Mathf.Pow(Godot.Mathf.Clamp(stressForConvergent, 0.0f, 1.0f), stressExponent);
            float convergentUpliftM = ConvergentBoundaryUpliftM
                * upliftMask
                * oceanicUpliftScale
                * divergenceMag
                * boundaryKScale
                * stressFalloff;

            float oceanicSuppression = Godot.Mathf.Pow(1.0f - landness, 1.6f);
            float boundarySeaBiasInfluence = Godot.Mathf.Max(-SeaLevelBias, 0.0f);
            float carveStrength = isOceanicBoundary ? 3.0f : 0.85f;
            float convergentTrenchM = ConvergentBoundaryUpliftM
                * boundarySeaBiasInfluence
                * carveStrength
                * oceanicSuppression
                * Godot.Mathf.Pow(trenchMask, 1.2f);
            if (isGap)
            {
                convergentTrenchM *= 2.0f;
            }

            float convergentNetM = convergentUpliftM - convergentTrenchM;
            if (convergentWeight > 0.0f && continentContinent)
            {
                convergentNetM = convergentUpliftM;
            }
            else if (convergentWeight > 0.0f && hasDensityPair && !continentContinent)
            {
                float d0 = _plateDensity[plateIdx];
                float d1 = _plateDensity[secondPlateIdx];
                int denserPlate;
                if (d0 > d1 + 1e-5f)
                {
                    denserPlate = plateIdx;
                }
                else if (d1 > d0 + 1e-5f)
                {
                    denserPlate = secondPlateIdx;
                }
                else
                {
                    denserPlate = ((pairHash & 1u) == 0u)
                        ? Godot.Mathf.Min(plateIdx, secondPlateIdx)
                        : Godot.Mathf.Max(plateIdx, secondPlateIdx);
                }

                if (plateIdx == denserPlate)
                {
                    convergentNetM = -convergentTrenchM;
                }
                else
                {
                    convergentNetM = convergentUpliftM;
                }
            }

            float divergentNetM = -RiftBoundaryDepthM * divergenceMag * edgeWeight;
            float boundaryDeltaM = convergentNetM * convergentWeight + divergentNetM * divergentWeight;
            meters += boundaryDeltaM;

            // Transform fault expression: high shear with near-zero divergence.
            float nearNeutralDivergence = 1.0f - Godot.Mathf.SmoothStep(0.01f, 0.06f, divergenceMag);
            float highShear = Godot.Mathf.SmoothStep(0.08f, 0.28f, boundaryShear);
            float transformWeight = nearNeutralDivergence * highShear;
            if (transformWeight > 0.0f)
            {
                float narrowFaultMask = Godot.Mathf.Pow(Godot.Mathf.Clamp(stress, 0.0f, 1.0f), 4.6f);
                float jagged = Godot.Mathf.Clamp(
                    0.35f + 0.65f * Godot.Mathf.Abs(RawBoundaryNoise(dir * 2.7f + new Godot.Vector3(11.0f, -7.0f, 19.0f))),
                    0.0f,
                    1.0f
                );
                float transformDepthM = RiftBoundaryDepthM
                    * 0.42f
                    * transformWeight
                    * narrowFaultMask
                    * jagged
                    * Godot.Mathf.Lerp(0.85f, 1.15f, 1.0f - landness);
                meters -= transformDepthM;
            }
        }

        return Godot.Mathf.Clamp(meters, EARTH_MIN_ELEVATION_METERS, EARTH_MAX_ELEVATION_METERS);
    }
}
