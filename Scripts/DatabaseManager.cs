using System;
using Godot;
using Microsoft.Data.Sqlite;

/// <summary>
/// Static access to the local SQLite delta database (terrain, climate overrides, world entities).
/// Call <see cref="Initialize"/> early in startup (e.g. from an autoload or main scene).
/// </summary>
public static class DatabaseManager
{
	private static string _connectionString = string.Empty;
	private static bool _initialized;

	public static string ConnectionString => _connectionString;

	public static bool IsInitialized => _initialized;

	public static void Initialize()
	{
		if (_initialized)
			return;

		try
		{
			string dbPath = ProjectSettings.GlobalizePath("user://planet_deltas.db");

			var builder = new SqliteConnectionStringBuilder
			{
				DataSource = dbPath
			};
			string connStr = builder.ConnectionString;

			using (var connection = new SqliteConnection(connStr))
			{
				connection.Open();

				const string sqlModifiedTerrain = @"
CREATE TABLE IF NOT EXISTS Modified_Terrain (
	Face INTEGER NOT NULL,
	X INTEGER NOT NULL,
	Y INTEGER NOT NULL,
	NewElevation REAL NOT NULL,
	PRIMARY KEY (Face, X, Y)
);";

				const string sqlClimateOverrides = @"
CREATE TABLE IF NOT EXISTS Climate_Overrides (
	Face INTEGER NOT NULL,
	X INTEGER NOT NULL,
	Y INTEGER NOT NULL,
	TempOverride REAL,
	PrecipOverride REAL,
	BiomeOverride INTEGER,
	PRIMARY KEY (Face, X, Y)
);";

				const string sqlWorldEntities = @"
CREATE TABLE IF NOT EXISTS World_Entities (
	EntityID TEXT PRIMARY KEY NOT NULL,
	EntityType TEXT NOT NULL,
	Face INTEGER NOT NULL,
	X INTEGER NOT NULL,
	Y INTEGER NOT NULL,
	EntityName TEXT
);";

				using (var cmd = connection.CreateCommand())
				{
					cmd.CommandText = sqlModifiedTerrain;
					cmd.ExecuteNonQuery();
				}

				using (var cmd = connection.CreateCommand())
				{
					cmd.CommandText = sqlClimateOverrides;
					cmd.ExecuteNonQuery();
				}

				MigrateClimateOverridesToNullableIfNeeded(connection);

				using (var cmd = connection.CreateCommand())
				{
					cmd.CommandText = sqlWorldEntities;
					cmd.ExecuteNonQuery();
				}
			}

			_connectionString = connStr;
			_initialized = true;
			GD.Print($"Planet deltas database and tables initialized successfully at: {dbPath}");
		}
		catch (Exception ex)
		{
			_connectionString = string.Empty;
			_initialized = false;
			GD.PushError($"DatabaseManager.Initialize failed: {ex.Message}");
			GD.PushError(ex.StackTrace ?? string.Empty);
		}
	}

	private static void MigrateClimateOverridesToNullableIfNeeded(SqliteConnection connection)
	{
		if (!ClimateOverridesNeedsNullableMigration(connection))
			return;

		const string migrateSql = @"
BEGIN IMMEDIATE;
CREATE TABLE Climate_Overrides__migration (
	Face INTEGER NOT NULL,
	X INTEGER NOT NULL,
	Y INTEGER NOT NULL,
	TempOverride REAL,
	PrecipOverride REAL,
	BiomeOverride INTEGER,
	PRIMARY KEY (Face, X, Y)
);
INSERT INTO Climate_Overrides__migration (Face, X, Y, TempOverride, PrecipOverride, BiomeOverride)
SELECT Face, X, Y, TempOverride, PrecipOverride, BiomeOverride FROM Climate_Overrides;
DROP TABLE Climate_Overrides;
ALTER TABLE Climate_Overrides__migration RENAME TO Climate_Overrides;
COMMIT;";

		using (var cmd = connection.CreateCommand())
		{
			cmd.CommandText = migrateSql;
			cmd.ExecuteNonQuery();
		}
	}

	private static bool ClimateOverridesNeedsNullableMigration(SqliteConnection connection)
	{
		using (var cmd = connection.CreateCommand())
		{
			cmd.CommandText = "PRAGMA table_info(Climate_Overrides);";
			using (var reader = cmd.ExecuteReader())
			{
				while (reader.Read())
				{
					string colName = reader.GetString(1);
					int notNull = reader.GetInt32(3);
					if ((colName == "TempOverride" || colName == "PrecipOverride" || colName == "BiomeOverride") && notNull != 0)
						return true;
				}
			}
		}

		return false;
	}

	private static bool EnsureReady(string operationLabel)
	{
		if (!_initialized)
			Initialize();

		if (_initialized && !string.IsNullOrEmpty(_connectionString))
			return true;

		GD.PushError($"DatabaseManager.{operationLabel}: database is not initialized.");
		return false;
	}

	public static void UpsertTerrainElevation(int face, int x, int y, float newElevation)
	{
		if (!EnsureReady(nameof(UpsertTerrainElevation)))
			return;

		try
		{
			using (var connection = new SqliteConnection(_connectionString))
			{
				connection.Open();
				using (var cmd = connection.CreateCommand())
				{
					cmd.CommandText = @"
INSERT OR REPLACE INTO Modified_Terrain (Face, X, Y, NewElevation)
VALUES ($Face, $X, $Y, $NewElevation);";
					cmd.Parameters.AddWithValue("$Face", face);
					cmd.Parameters.AddWithValue("$X", x);
					cmd.Parameters.AddWithValue("$Y", y);
					cmd.Parameters.AddWithValue("$NewElevation", newElevation);
					cmd.ExecuteNonQuery();
				}
			}
		}
		catch (Exception ex)
		{
			GD.PushError($"DatabaseManager.UpsertTerrainElevation failed: {ex.Message}");
			GD.PushError(ex.StackTrace ?? string.Empty);
		}
	}

	public static void UpsertClimateOverride(int face, int x, int y, float? temp, float? precip, int? biome)
	{
		if (!EnsureReady(nameof(UpsertClimateOverride)))
			return;

		try
		{
			using (var connection = new SqliteConnection(_connectionString))
			{
				connection.Open();
				using (var cmd = connection.CreateCommand())
				{
					cmd.CommandText = @"
INSERT INTO Climate_Overrides (Face, X, Y, TempOverride, PrecipOverride, BiomeOverride)
VALUES ($Face, $X, $Y, $Temp, $Precip, $Biome)
ON CONFLICT(Face, X, Y) DO UPDATE SET
	TempOverride = COALESCE(excluded.TempOverride, Climate_Overrides.TempOverride),
	PrecipOverride = COALESCE(excluded.PrecipOverride, Climate_Overrides.PrecipOverride),
	BiomeOverride = COALESCE(excluded.BiomeOverride, Climate_Overrides.BiomeOverride);";
					cmd.Parameters.AddWithValue("$Face", face);
					cmd.Parameters.AddWithValue("$X", x);
					cmd.Parameters.AddWithValue("$Y", y);
					cmd.Parameters.AddWithValue("$Temp", temp.HasValue ? temp.Value : (object)DBNull.Value);
					cmd.Parameters.AddWithValue("$Precip", precip.HasValue ? precip.Value : (object)DBNull.Value);
					cmd.Parameters.AddWithValue("$Biome", biome.HasValue ? biome.Value : (object)DBNull.Value);
					cmd.ExecuteNonQuery();
				}
			}
		}
		catch (Exception ex)
		{
			GD.PushError($"DatabaseManager.UpsertClimateOverride failed: {ex.Message}");
			GD.PushError(ex.StackTrace ?? string.Empty);
		}
	}

	public static void ApplyTerrainDeltas(float[] elevationMap, int face, int res)
	{
		if (elevationMap == null || res <= 0)
			return;

		if (!EnsureReady(nameof(ApplyTerrainDeltas)))
			return;

		try
		{
			using (var connection = new SqliteConnection(_connectionString))
			{
				connection.Open();
				using (var cmd = connection.CreateCommand())
				{
					cmd.CommandText = @"
SELECT X, Y, NewElevation FROM Modified_Terrain WHERE Face = $Face;";
					cmd.Parameters.AddWithValue("$Face", face);
					using (var reader = cmd.ExecuteReader())
					{
						while (reader.Read())
						{
							int x = reader.GetInt32(0);
							int y = reader.GetInt32(1);
							double elev = reader.GetDouble(2);
							if ((uint)x >= (uint)res || (uint)y >= (uint)res)
								continue;
							int index = y * res + x;
							if ((uint)index >= (uint)elevationMap.Length)
								continue;
							elevationMap[index] = (float)elev;
						}
					}
				}
			}
		}
		catch (Exception ex)
		{
			GD.PushError($"DatabaseManager.ApplyTerrainDeltas failed: {ex.Message}");
			GD.PushError(ex.StackTrace ?? string.Empty);
		}
	}

	public static void ApplyClimateDeltas(float[] tempMap, float[] precipMap, float[] biomeMap, int face, int res)
	{
		if (res <= 0)
			return;

		if (!EnsureReady(nameof(ApplyClimateDeltas)))
			return;

		try
		{
			using (var connection = new SqliteConnection(_connectionString))
			{
				connection.Open();
				using (var cmd = connection.CreateCommand())
				{
					cmd.CommandText = @"
SELECT X, Y, TempOverride, PrecipOverride, BiomeOverride FROM Climate_Overrides WHERE Face = $Face;";
					cmd.Parameters.AddWithValue("$Face", face);
					using (var reader = cmd.ExecuteReader())
					{
						while (reader.Read())
						{
							int x = reader.GetInt32(0);
							int y = reader.GetInt32(1);
							if ((uint)x >= (uint)res || (uint)y >= (uint)res)
								continue;
							int index = y * res + x;

							if (tempMap != null && !reader.IsDBNull(2))
							{
								if ((uint)index < (uint)tempMap.Length)
									tempMap[index] = (float)reader.GetDouble(2);
							}

							if (precipMap != null && !reader.IsDBNull(3))
							{
								if ((uint)index < (uint)precipMap.Length)
									precipMap[index] = (float)reader.GetDouble(3);
							}

							if (biomeMap != null && !reader.IsDBNull(4))
							{
								if ((uint)index < (uint)biomeMap.Length)
									biomeMap[index] = reader.GetInt32(4);
							}
						}
					}
				}
			}
		}
		catch (Exception ex)
		{
			GD.PushError($"DatabaseManager.ApplyClimateDeltas failed: {ex.Message}");
			GD.PushError(ex.StackTrace ?? string.Empty);
		}
	}
}
