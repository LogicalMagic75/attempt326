using System;
using System.Threading.Tasks;
using Godot;

[Tool]
public partial class PlanetBaseTruthBaker : Godot.Node
{
	[Signal]
	public delegate void BakeStartedEventHandler();

	[Signal]
	public delegate void BakeProgressEventHandler(string phase, double overall01, string message);

	[Signal]
	public delegate void BakeFinishedEventHandler(bool success, Godot.Collections.Dictionary elevationBuffersByFace);

	public const int FACE_RES = 512;
	private const int FACE_COUNT = 6;
	private const int _FACE_ROW_PROGRESS_STEP = 64;
	private const int _DETAIL_NOISE_SEED_MUL = 6151;
	private const int _DETAIL_NOISE_SEED_ADD = 101;

	[Export]
	public int WorldSeed { get; set; } = -1;

	[Export]
	public Godot.Resource Tectonics { get; set; }

	[Export]
	public Godot.FastNoiseLite DetailNoise { get; set; }

	[Export]
	public float NoiseAmplitudeM { get; set; } = 1280.0f;

	[Export(PropertyHint.Range, "0.01,5000.0,0.01,or_greater")]
	public float DetailNoiseCoordScale { get; set; } = 1000.0f;

	[ExportGroup("Debug: elevation noise toggles")]
	[Export]
	public bool EnableTectonicDomainWarpNoise { get; set; } = true;

	[Export]
	public bool EnableTectonicBoundaryNoise { get; set; } = true;

	[Export]
	public bool EnableDetailNoise { get; set; } = true;

	[Export]
	public string OutputDir { get; set; } = "user://planet_data/";

	[Export]
	public string FilePrefix { get; set; } = "level0_height_";

	[Export]
	public Godot.Resource ClimateGrid { get; set; }

	[Export]
	public bool UseWorkerThread { get; set; } = true;

	private bool _baking;
	private bool _deferBakeProgressReports;

	private TectonicPlates EnsureTectonics()
	{
		if (Tectonics is TectonicPlates typed)
		{
			return typed;
		}

		TectonicPlates created = new TectonicPlates();
		Tectonics = created;
		return created;
	}

	public void SetWorldSeed(int worldSeedValue)
	{
		WorldSeed = worldSeedValue;
		ApplyWorldSeedToComponents(worldSeedValue);
	}

	private int GetEffectiveWorldSeed()
	{
		if (WorldSeed >= 0)
		{
			return WorldSeed;
		}

		return EnsureTectonics().GenerationSeed;
	}

	private void ApplyWorldSeedToComponents(int worldSeedValue)
	{
		TectonicPlates tectonics = EnsureTectonics();

		if (DetailNoise == null)
		{
			DetailNoise = DefaultDetailNoise();
		}

		tectonics.GenerationSeed = worldSeedValue;
		if (DetailNoise != null)
		{
			DetailNoise.Seed = worldSeedValue * _DETAIL_NOISE_SEED_MUL + _DETAIL_NOISE_SEED_ADD;
		}
	}

	public override void _Ready()
	{
		DatabaseManager.Initialize();
		EnsureTectonics();

		if (DetailNoise == null)
		{
			DetailNoise = DefaultDetailNoise();
		}
	}

	public void SetTargetLandAreaPercent(float percent)
	{
		TectonicPlates tectonics = EnsureTectonics();
		tectonics.TargetLandAreaFraction = Godot.Mathf.Clamp(percent / 100.0f, 0.0f, 1.0f);
	}

	private Godot.FastNoiseLite DefaultDetailNoise()
	{
		Godot.FastNoiseLite n = new Godot.FastNoiseLite();
		n.Seed = 42;
		// Matches MainView.tscn DetailNoise subresource (Value noise + FBM).
		n.NoiseType = Godot.FastNoiseLite.NoiseTypeEnum.Value;
		n.FractalType = Godot.FastNoiseLite.FractalTypeEnum.Fbm;
		n.FractalOctaves = 7;
		n.Set(FastNoiseLite.PropertyName.Frequency, 0.002);
		n.Set(FastNoiseLite.PropertyName.FractalLacunarity, 5.0);
		n.Set(FastNoiseLite.PropertyName.FractalGain, 0.6);
		n.Set(FastNoiseLite.PropertyName.FractalWeightedStrength, 0.5);
		return n;
	}

	public bool GenerateBaseTruth(Godot.Resource applyToGrid = null)
	{
		_deferBakeProgressReports = false;
		float[][] buffers = ExecuteBakeCollectBuffers();
		bool ok = ValidateFaceBuffers(buffers);
		Godot.Resource target = applyToGrid ?? ClimateGrid;
		ApplyElevationToClimateGrid(target, buffers);
		return ok;
	}

	public void RequestGenerateBaseTruth()
	{
		if (_baking)
		{
			GD.PushWarning("PlanetBaseTruthBaker: bake already in progress");
			return;
		}

		_baking = true;
		EmitSignal(SignalName.BakeStarted);
		if (UseWorkerThread)
		{
			Task.Run(BakeWorkerTask);
		}
		else
		{
			_deferBakeProgressReports = false;
			float[][] buffers = ExecuteBakeCollectBuffers();
			bool ok = ValidateFaceBuffers(buffers);
			FinishBakeOnMain(ok, ConvertFaceBuffersToGodotDictionary(buffers));
		}
	}

	private void BakeWorkerTask()
	{
		try
		{
			_deferBakeProgressReports = true;
			float[][] buffers = ExecuteBakeCollectBuffers();
			bool ok = ValidateFaceBuffers(buffers);
			_deferBakeProgressReports = false;
			CallDeferred(MethodName.FinishBakeOnMain, ok, ConvertFaceBuffersToGodotDictionary(buffers));
		}
		catch (Exception ex)
		{
			_deferBakeProgressReports = false;
			GD.PushError($"PlanetBaseTruthBaker: bake worker failed: {ex.Message}");
			CallDeferred(MethodName.FinishBakeOnMain, false, new Godot.Collections.Dictionary());
		}
	}

	private void FinishBakeOnMain(bool success, Godot.Collections.Dictionary elevationBuffersByFace)
	{
		_baking = false;
		EmitSignal(SignalName.BakeFinished, success, success ? elevationBuffersByFace : new Godot.Collections.Dictionary());
	}

	public void ApplyElevationToClimateGrid(Godot.Resource grid, float[][] elevationBuffersByFace)
	{
		if (grid == null || elevationBuffersByFace == null || elevationBuffersByFace.Length == 0)
		{
			return;
		}

		Godot.Collections.Dictionary godotDictionary = ConvertFaceBuffersToGodotDictionary(elevationBuffersByFace);
		Variant result = ((GodotObject)grid).Call("update_elevation_from_buffers", godotDictionary);
		if (result.VariantType == Variant.Type.Bool && !result.AsBool())
		{
			GD.PushError("PlanetBaseTruthBaker: update_elevation_from_buffers failed");
		}
	}

	private void NotifyBakeProgress(string phase, float overall01, string message)
	{
		float o = Godot.Mathf.Clamp(overall01, 0.0f, 1.0f);
		if (_deferBakeProgressReports)
		{
			CallDeferred(MethodName.EmitBakeProgress, phase, o, message);
		}
		else
		{
			EmitBakeProgress(phase, o, message);
		}
	}

	private void EmitBakeProgress(string phase, float overall01, string message)
	{
		// Use double here so GDScript's 64-bit float parameters connect cleanly.
		EmitSignal(SignalName.BakeProgress, phase, (double)overall01, message);
	}

	public float[][] ExecuteBakeCollectBuffers()
	{
		ApplyWorldSeedToComponents(GetEffectiveWorldSeed());
		NotifyBakeProgress(
			"init",
			0.0f,
			$"Bake: 6×{FACE_RES}² (tectonic hypsometry + detail ±{NoiseAmplitudeM:0} m, worker={UseWorkerThread})"
		);

		TectonicPlates tectonics = EnsureTectonics();
		bool enableDomainWarpNoise = EnableTectonicDomainWarpNoise;
		bool enableBoundaryNoise = EnableTectonicBoundaryNoise;

		float landPct = tectonics.TargetLandAreaFraction * 100.0f;
		NotifyBakeProgress(
			"tectonics",
			0.04f,
			$"Bake: tectonics - {tectonics.PlateCount} plates, ~{landPct:0}% land, seed {tectonics.GenerationSeed}"
		);
		tectonics.Regenerate();

		if (DetailNoise == null)
		{
			DetailNoise = DefaultDetailNoise();
		}

		NotifyBakeProgress("tectonics", 0.11f, "Bake: tectonics ready - sampling cube faces");

		// Godot Resources (Tectonics, DetailNoise) are not thread-safe; do not use Parallel.For here.
		float[][] faceBuffers = new float[FACE_COUNT][];
		for (int face = 0; face < FACE_COUNT; face++)
		{
			faceBuffers[face] = GenerateTectonicFaceWithProgress(face, enableDomainWarpNoise, enableBoundaryNoise);
		}

		if (EnableDetailNoise)
		{
			for (int face = 0; face < FACE_COUNT; face++)
			{
				AddDetailNoiseToFaceWithProgress(faceBuffers[face], face);
				DatabaseManager.ApplyTerrainDeltas(faceBuffers[face], face, FACE_RES);
			}
		}
		else
		{
			NotifyBakeProgress("noise", 0.89f, "Bake: detail noise disabled (debug toggle)");
			for (int face = 0; face < FACE_COUNT; face++)
			{
				DatabaseManager.ApplyTerrainDeltas(faceBuffers[face], face, FACE_RES);
			}
		}
		ReportSeaLevelHistogram(faceBuffers);

		return faceBuffers;
	}

	private bool ValidateFaceBuffers(float[][] buffers)
	{
		NotifyBakeProgress("validate", 0.92f, "Bake: validate face buffers...");
		if (buffers == null || buffers.Length != FACE_COUNT)
		{
			int got = buffers?.Length ?? 0;
			GD.PushError($"PlanetBaseTruthBaker: expected 6 face buffers, got {got}");
			NotifyBakeProgress("validate", 0.94f, $"Validation failed: wrong face count ({got}).");
			return false;
		}

		int expected = FACE_RES * FACE_RES;
		for (int face = 0; face < FACE_COUNT; face++)
		{
			if (buffers[face] == null)
			{
				GD.PushError($"PlanetBaseTruthBaker: missing buffer for face {face}");
				NotifyBakeProgress("validate", 0.94f, $"Validation failed: missing face {face}.");
				return false;
			}

			if (buffers[face].Length != expected)
			{
				GD.PushError($"PlanetBaseTruthBaker: face {face} buffer size {buffers[face].Length} != {expected}");
				NotifyBakeProgress("validate", 0.94f, $"Validation failed: face {face} size {buffers[face].Length} (expected {expected}).");
				return false;
			}
		}

		NotifyBakeProgress("validate", 0.98f, $"Bake: validation OK ({FACE_RES}² floats/face)");
		return true;
	}

	private float BakeOverallFace(int faceIndex, int rowDone)
	{
		float faceFrac = (faceIndex + rowDone / (float)FACE_RES) / 6.0f;
		return Godot.Mathf.Lerp(0.12f, 0.88f, faceFrac);
	}

	private float[] GenerateTectonicFaceWithProgress(int faceIndex, bool enableDomainWarpNoise, bool enableBoundaryNoise)
	{
		TectonicPlates tectonics = EnsureTectonics();
		string faceName = CubeSphereMath.EXR_FACE_NAMES[faceIndex];
		NotifyBakeProgress(
			"face",
			BakeOverallFace(faceIndex, 0),
			$"Bake: face {faceIndex + 1}/6 ({faceName}) tectonics..."
		);

		float[] buf = new float[FACE_RES * FACE_RES];
		float denom = FACE_RES;
		int i = 0;
		for (int y = 0; y < FACE_RES; y++)
		{
			for (int x = 0; x < FACE_RES; x++)
			{
				Godot.Vector2 uv = new Godot.Vector2((x + 0.5f) / denom, (y + 0.5f) / denom);
				Godot.Vector3 sphereNormal = CubeSphereMath.face_uv01_to_unit_direction(faceIndex, uv);
				Godot.Vector4 sample = tectonics.Sample(sphereNormal, enableDomainWarpNoise, enableBoundaryNoise);
				buf[i] = (float)sample.X;
				i += 1;
			}

			int rowHi = y + 1;
			if (rowHi == 1 || rowHi % _FACE_ROW_PROGRESS_STEP == 0 || y == FACE_RES - 1)
			{
				NotifyBakeProgress(
					"face",
					BakeOverallFace(faceIndex, rowHi),
					$"Bake: face {faceIndex + 1}/6 ({faceName}) tectonics rows {rowHi}/{FACE_RES}"
				);
			}
		}

		float mn = buf[0];
		float mx = buf[0];
		for (int j = 1; j < buf.Length; j++)
		{
			float v = buf[j];
			if (v < mn)
			{
				mn = v;
			}

			if (v > mx)
			{
				mx = v;
			}
		}

		NotifyBakeProgress(
			"face",
			BakeOverallFace(faceIndex + 1, 0),
			$"Bake: face {faceIndex + 1}/6 ({faceName}) tectonics done - {mn:0}...{mx:0} m"
		);
		return buf;
	}

	private void AddDetailNoiseToFaceWithProgress(float[] buf, int faceIndex)
	{
		string faceName = CubeSphereMath.EXR_FACE_NAMES[faceIndex];
		NotifyBakeProgress(
			"noise",
			BakeOverallFace(faceIndex, 0),
			$"Bake: face {faceIndex + 1}/6 ({faceName}) detail noise..."
		);

		float denom = FACE_RES;
		int i = 0;
		for (int y = 0; y < FACE_RES; y++)
		{
			for (int x = 0; x < FACE_RES; x++)
			{
				Godot.Vector2 uv = new Godot.Vector2((x + 0.5f) / denom, (y + 0.5f) / denom);
				Godot.Vector3 sphereNormal = CubeSphereMath.face_uv01_to_unit_direction(faceIndex, uv);
				float noiseVal = (float)DetailNoise.GetNoise3Dv(sphereNormal * DetailNoiseCoordScale);
				buf[i] += noiseVal * NoiseAmplitudeM;
				i += 1;
			}

			int rowHi = y + 1;
			if (rowHi == 1 || rowHi % _FACE_ROW_PROGRESS_STEP == 0 || y == FACE_RES - 1)
			{
				NotifyBakeProgress(
					"noise",
					BakeOverallFace(faceIndex, rowHi),
					$"Bake: face {faceIndex + 1}/6 ({faceName}) noise rows {rowHi}/{FACE_RES}"
				);
			}
		}

		float mn = buf[0];
		float mx = buf[0];
		for (int j = 1; j < buf.Length; j++)
		{
			float v = buf[j];
			if (v < mn)
			{
				mn = v;
			}

			if (v > mx)
			{
				mx = v;
			}
		}

		NotifyBakeProgress(
			"noise",
			BakeOverallFace(faceIndex + 1, 0),
			$"Bake: face {faceIndex + 1}/6 ({faceName}) final - {mn:0}...{mx:0} m"
		);
	}

	public float[] GenerateFaceBuffer(int faceIndex)
	{
		float[] buf = GenerateTectonicFaceWithProgress(
			faceIndex,
			EnableTectonicDomainWarpNoise,
			EnableTectonicBoundaryNoise
		);
		AddDetailNoiseToFaceWithProgress(buf, faceIndex);
		return buf;
	}

	private void ReportSeaLevelHistogram(float[][] buffers)
	{
		if (buffers == null || buffers.Length != FACE_COUNT)
		{
			return;
		}

		NotifyBakeProgress("finalize", 0.90f, "Bake: sea-level histogram...");
		long veryLow = 0;    // < -50 m
		long low = 0;        // [-50, -10)
		long nearNeg = 0;    // [-10, -2)
		long jitterNeg = 0;  // [-2, 0)
		long jitterPos = 0;  // [0, 2)
		long nearPos = 0;    // [2, 10)
		long high = 0;       // [10, 50)
		long veryHigh = 0;   // >= 50
		float mn = float.PositiveInfinity;
		float mx = float.NegativeInfinity;

		for (int f = 0; f < FACE_COUNT; f++)
		{
			float[] b = buffers[f];
			if (b == null)
			{
				continue;
			}

			for (int i = 0; i < b.Length; i++)
			{
				float h = b[i];
				if (h < mn) mn = h;
				if (h > mx) mx = h;
				if (h < -50.0f) veryLow++;
				else if (h < -10.0f) low++;
				else if (h < -2.0f) nearNeg++;
				else if (h < 0.0f) jitterNeg++;
				else if (h < 2.0f) jitterPos++;
				else if (h < 10.0f) nearPos++;
				else if (h < 50.0f) high++;
				else veryHigh++;
			}
		}

		GD.Print(
			$"SeaLevelHistogram m: < -50:{veryLow}, -50..-10:{low}, -10..-2:{nearNeg}, -2..0:{jitterNeg}, 0..2:{jitterPos}, 2..10:{nearPos}, 10..50:{high}, >=50:{veryHigh}; min={mn:0.0}, max={mx:0.0}"
		);
	}

	private Godot.Collections.Dictionary ConvertFaceBuffersToGodotDictionary(float[][] faceBuffers)
	{
		Godot.Collections.Dictionary dict = new Godot.Collections.Dictionary();
		for (int face = 0; face < FACE_COUNT; face++)
		{
			dict[face] = faceBuffers[face];
		}

		return dict;
	}

}
