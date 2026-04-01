using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;

public partial class RiverGenerator : RefCounted
{
    private const float D8StepCard = 1.0f;
    private const float D8StepDiag = 1.4142135623730951f;

    private static readonly Vector2I[] Dirs8 =
    {
        new Vector2I(1, 0),
        new Vector2I(-1, 0),
        new Vector2I(0, 1),
        new Vector2I(0, -1),
        new Vector2I(1, 1),
        new Vector2I(1, -1),
        new Vector2I(-1, 1),
        new Vector2I(-1, -1),
    };

    public void CalculateFlowAccumulation(GodotObject grid, bool[] oceanMask, Callable progress)
    {
        if (!(bool)grid.Call("is_allocated"))
        {
            GD.PushError("RiverGenerator.CalculateFlowAccumulation: grid is not allocated");
            return;
        }

        ReportProgress(progress, 0.0f);

        float[] elev = grid.Get("elevation_map").AsFloat32Array();
        float[] precipitation = grid.Get("precipitation_map").AsFloat32Array();
        float[] temperature = grid.Get("temperature_map").AsFloat32Array();
        int res = grid.Get("face_resolution").AsInt32();
        int n = elev.Length;
        float seaLevelM = ClimateSimulator.GenerationSeaLevelOffsetM;
        if (oceanMask == null || oceanMask.Length != n)
        {
            GD.PushError("RiverGenerator.CalculateFlowAccumulation: oceanMask is null or has invalid length.");
            return;
        }

        float[] hRoute = PriorityFloodFillOcean(elev, oceanMask, res, n, progress);
        ReportProgress(progress, 0.08f);

        int totalLandish = 0;
        for (int i = 0; i < n; i++)
        {
            if (!oceanMask[i])
            {
                totalLandish++;
            }
        }

        int routed = 0;
        int[] downstream = BuildDownstreamD8(hRoute, oceanMask, res, n, progress, totalLandish, ref routed);
        ReportProgress(progress, 0.62f);

        int[] mouthIdAt = new int[n];
        Array.Fill(mouthIdAt, -1);
        int mouthCount = 0;
        for (int lin = 0; lin < n; lin++)
        {
            if (oceanMask[lin])
            {
                continue;
            }
            if (CoastalLandLin(oceanMask, res, n, lin))
            {
                mouthIdAt[lin] = mouthCount;
                mouthCount++;
            }
        }

        int[] basin = new int[n];
        Array.Fill(basin, -1);

        int[] topoDesc = BuildDownstreamTopologicalOrder(downstream, oceanMask, n);
        int landN = topoDesc.Length;
        for (int idx = landN - 1; idx >= 0; idx--)
        {
            int linA = topoDesc[idx];
            int dsA = downstream[linA];
            if (dsA >= 0)
            {
                basin[linA] = basin[dsA];
            }
            else if (mouthIdAt[linA] >= 0)
            {
                basin[linA] = mouthIdAt[linA];
            }
        }

        List<int> qRev = new();
        for (int lin = 0; lin < n; lin++)
        {
            if (mouthIdAt[lin] < 0 || oceanMask[lin])
            {
                continue;
            }
            if (basin[lin] < 0)
            {
                basin[lin] = mouthIdAt[lin];
            }
            qRev.Add(lin);
        }

        int qrH = 0;
        int revSteps = 0;
        int revReport = Math.Max(n / 128, 4096);
        int cpf = res * res;
        while (qrH < qRev.Count)
        {
            int c = qRev[qrH++];
            revSteps++;
            if (revReport > 0 && revSteps % revReport == 0)
            {
                float uRev = Mathf.Clamp((float)qrH / Math.Max(n, 1), 0.0f, 1.0f);
                ReportProgress(progress, Mathf.Lerp(0.62f, 0.635f, uRev));
            }

            int label = basin[c];
            if (label < 0)
            {
                continue;
            }

            int face = c / cpf;
            int rem = c % cpf;
            int y = rem / res;
            int x = rem % res;

            foreach (Vector2I d in Dirs8)
            {
                Vector3I nb = ClimateCellNeighbor(res, face, x, y, d.X, d.Y);
                if (nb.X == face && nb.Y == x && nb.Z == y)
                {
                    continue;
                }
                int nlin = nb.X * cpf + nb.Z * res + nb.Y;
                if (nlin < 0 || nlin >= n || oceanMask[nlin])
                {
                    continue;
                }
                if (downstream[nlin] != c)
                {
                    continue;
                }
                if (basin[nlin] < 0)
                {
                    basin[nlin] = label;
                    qRev.Add(nlin);
                }
            }
        }

        int qh = 0;
        List<int> qBfsCells = new();
        for (int lin = 0; lin < n; lin++)
        {
            if (!oceanMask[lin] && mouthIdAt[lin] >= 0)
            {
                qBfsCells.Add(lin);
            }
        }

        int gapSteps = 0;
        int gapReport = Math.Max(n / 128, 4096);
        while (qh < qBfsCells.Count)
        {
            int c = qBfsCells[qh++];
            gapSteps++;
            if (gapReport > 0 && gapSteps % gapReport == 0)
            {
                float uGap = Mathf.Clamp((float)qh / Math.Max(n, 1), 0.0f, 1.0f);
                ReportProgress(progress, Mathf.Lerp(0.635f, 0.655f, uGap));
            }

            int label = basin[c];
            if (label < 0)
            {
                label = mouthIdAt[c];
                if (label < 0)
                {
                    continue;
                }
                basin[c] = label;
            }

            int face = c / cpf;
            int rem = c % cpf;
            int y = rem / res;
            int x = rem % res;

            foreach (Vector2I d in Dirs8)
            {
                Vector3I nb = ClimateCellNeighbor(res, face, x, y, d.X, d.Y);
                if (nb.X == face && nb.Y == x && nb.Z == y)
                {
                    continue;
                }
                int nlin = nb.X * cpf + nb.Z * res + nb.Y;
                if (nlin < 0 || nlin >= n || oceanMask[nlin] || basin[nlin] >= 0)
                {
                    continue;
                }
                basin[nlin] = label;
                qBfsCells.Add(nlin);
            }
        }

        for (int i = 0; i < n; i++)
        {
            if (!oceanMask[i] && basin[i] < 0)
            {
                basin[i] = 0;
            }
        }

        ReportProgress(progress, 0.66f);

        float[] source = new float[n];
        const float thawC = 2.0f;
        const float freezeC = -2.0f;
        for (int i = 0; i < n; i++)
        {
            if (oceanMask[i])
            {
                source[i] = 0.0f;
                continue;
            }

            float tempC = temperature[i];
            float thawF = FreezeRunoffFactor(tempC, thawC, freezeC);
            float moistureN = Mathf.Clamp(precipitation[i] / 450.0f, 0.0f, 1.0f);
            float reliefF = LocalReliefFactor(hRoute, res, n, i);
            float runoffWetness = 0.35f + 0.65f * Mathf.Pow(moistureN, 1.8f);
            float runoffRelief = 0.55f + 0.45f * Mathf.Pow(reliefF, 1.15f);
            source[i] = thawF * runoffWetness * runoffRelief;
        }

        ReportProgress(progress, 0.72f);

        float[] flowAccum = new float[n];
        Array.Copy(source, flowAccum, n);

        int accReport = Math.Max((int)Math.Ceiling((float)Math.Max(landN, 1) / 32.0f), 1);
        for (int k = 0; k < landN; k++)
        {
            int lin = topoDesc[k];
            int dlin = downstream[lin];
            if (dlin >= 0)
            {
                flowAccum[dlin] += flowAccum[lin];
            }
            if (k % accReport == 0 || k == landN - 1)
            {
                ReportProgress(progress, 0.72f + 0.20f * (k + 1) / Math.Max(landN, 1));
            }
        }

        int majorTarget = Mathf.Clamp(3 + (int)MathF.Floor((float)res / 192.0f), 3, 6);
        BoostMajorBasinTrunks(downstream, oceanMask, basin, flowAccum, res, n, majorTarget);

        int[] basinIdMap = new int[n];
        for (int i = 0; i < n; i++)
        {
            basinIdMap[i] = oceanMask[i] ? -1 : basin[i];
        }

        grid.Set("flow_accumulation_map", flowAccum);
        grid.Set("flow_downstream_cell", downstream);
        grid.Set("basin_id_map", basinIdMap);

        ReportProgress(progress, 1.0f);
    }

    private static float[] PriorityFloodFillOcean(float[] elev, bool[] oceanMask, int res, int n, Callable progress)
    {
        float[] filled = new float[n];
        bool[] visited = new bool[n];
        PriorityQueue<int, float> queue = new();
        int oceanCount = 0;

        for (int i = 0; i < n; i++)
        {
            if (oceanMask[i])
            {
                filled[i] = elev[i];
                visited[i] = true;
                queue.Enqueue(i, elev[i]);
                oceanCount++;
            }
        }

        if (oceanCount == 0)
        {
            GD.PushWarning("RiverGenerator.PriorityFloodFillOcean: no ocean cells in ocean mask; using raw elevation for routing.");
            Array.Copy(elev, filled, n);
            return filled;
        }

        int cpf = res * res;
        int popped = 0;
        int reportStride = Math.Max(n / 64, 8192);

        while (queue.TryDequeue(out int ci, out float fillC))
        {
            int faceC = ci / cpf;
            int remC = ci % cpf;
            int yC = remC / res;
            int xC = remC % res;

            foreach (Vector2I d in Dirs8)
            {
                Vector3I nb = ClimateCellNeighbor(res, faceC, xC, yC, d.X, d.Y);
                if (nb.X == faceC && nb.Y == xC && nb.Z == yC)
                {
                    continue;
                }
                int nlin = nb.X * cpf + nb.Z * res + nb.Y;
                if (nlin < 0 || nlin >= n || visited[nlin])
                {
                    continue;
                }
                visited[nlin] = true;
                float noiseBias = FlowRoutingBiasM(res, nlin);
                float targetH = MathF.Max(elev[nlin], fillC + 0.0001f + noiseBias);
                filled[nlin] = targetH;
                queue.Enqueue(nlin, targetH);
            }

            popped++;
            if (reportStride > 0 && popped % reportStride == 0)
            {
                float ft = Mathf.Clamp((float)popped / Math.Max(n, 1), 0.0f, 1.0f);
                ReportProgress(progress, Mathf.Lerp(0.0f, 0.08f, ft));
            }
        }

        for (int i = 0; i < n; i++)
        {
            if (!visited[i])
            {
                filled[i] = elev[i];
            }
        }

        return filled;
    }

    private static int[] BuildDownstreamD8(float[] hRoute, bool[] oceanMask, int res, int n, Callable progress, int totalLandish, ref int routed)
    {
        int[] downstream = new int[n];
        Array.Fill(downstream, -1);
        int reportStride = Math.Max((int)Math.Ceiling((float)totalLandish / 48.0f), 4096);
        int cpf = res * res;

        for (int lin = 0; lin < n; lin++)
        {
            if (oceanMask[lin])
            {
                continue;
            }

            float hSelf = hRoute[lin];
            float bestSlope = float.NegativeInfinity;
            float bestTie = float.PositiveInfinity;
            int bestNlin = -1;

            int face = lin / cpf;
            int rem = lin % cpf;
            int y = rem / res;
            int x = rem % res;

            foreach (Vector2I d in Dirs8)
            {
                Vector3I nb = ClimateCellNeighbor(res, face, x, y, d.X, d.Y);
                if (nb.X == face && nb.Y == x && nb.Z == y)
                {
                    continue;
                }
                int nlin = nb.X * cpf + nb.Z * res + nb.Y;
                if (nlin < 0 || nlin >= n)
                {
                    continue;
                }
                float nhR = hRoute[nlin];
                if (nhR >= hSelf)
                {
                    continue;
                }
                (float slope, float tie) = D8DownhillSlopeAndTie(lin, nlin, d, hSelf, nhR);
                if (slope > bestSlope || (Mathf.IsEqualApprox(slope, bestSlope) && tie < bestTie))
                {
                    bestSlope = slope;
                    bestTie = tie;
                    bestNlin = nlin;
                }
            }

            if (bestNlin < 0 || oceanMask[bestNlin])
            {
                downstream[lin] = -1;
            }
            else
            {
                downstream[lin] = bestNlin;
            }

            routed++;
            if (reportStride > 0 && routed % reportStride == 0)
            {
                ReportProgress(progress, 0.08f + 0.52f * routed / Math.Max(totalLandish, 1));
            }
        }

        return downstream;
    }

    private static int[] BuildDownstreamTopologicalOrder(int[] downstream, bool[] oceanMask, int n)
    {
        int[] indegree = new int[n];
        int landCount = 0;
        for (int lin = 0; lin < n; lin++)
        {
            if (!oceanMask[lin])
            {
                landCount++;
                int ds = downstream[lin];
                if (ds >= 0 && ds < n && !oceanMask[ds])
                {
                    indegree[ds]++;
                }
            }
        }

        int[] queue = new int[Math.Max(landCount, 1)];
        int qHead = 0;
        int qTail = 0;
        for (int lin = 0; lin < n; lin++)
        {
            if (!oceanMask[lin] && indegree[lin] == 0)
            {
                queue[qTail++] = lin;
            }
        }

        int[] order = new int[Math.Max(landCount, 1)];
        int ordTail = 0;
        while (qHead < qTail)
        {
            int lin = queue[qHead++];
            order[ordTail++] = lin;
            int ds = downstream[lin];
            if (ds >= 0 && ds < n && !oceanMask[ds])
            {
                indegree[ds]--;
                if (indegree[ds] == 0)
                {
                    queue[qTail++] = ds;
                }
            }
        }

        if (ordTail < landCount)
        {
            for (int lin = 0; lin < n && ordTail < landCount; lin++)
            {
                if (!oceanMask[lin] && indegree[lin] > 0)
                {
                    order[ordTail++] = lin;
                    indegree[lin] = 0;
                }
            }
        }

        if (ordTail < landCount)
        {
            for (int lin = 0; lin < n && ordTail < landCount; lin++)
            {
                if (!oceanMask[lin])
                {
                    order[ordTail++] = lin;
                }
            }
        }

        int[] result = new int[landCount];
        Array.Copy(order, result, landCount);
        return result;
    }

    private static bool CoastalLandLin(bool[] oceanMask, int res, int n, int lin)
    {
        if (oceanMask[lin])
        {
            return false;
        }
        int cpf = res * res;
        int face = lin / cpf;
        int rem = lin % cpf;
        int y = rem / res;
        int x = rem % res;
        foreach (Vector2I d in Dirs8)
        {
            Vector3I nb = ClimateCellNeighbor(res, face, x, y, d.X, d.Y);
            if (nb.X == face && nb.Y == x && nb.Z == y)
            {
                continue;
            }
            int nlin = nb.X * cpf + nb.Z * res + nb.Y;
            if (nlin >= 0 && nlin < n && oceanMask[nlin])
            {
                return true;
            }
        }
        return false;
    }

    private static float FreezeRunoffFactor(float tempC, float thawC, float freezeC)
    {
        if (thawC <= freezeC)
        {
            return tempC > freezeC ? 1.0f : 0.0f;
        }
        return Mathf.Clamp((tempC - freezeC) / (thawC - freezeC), 0.0f, 1.0f);
    }

    private static float LocalReliefFactor(float[] hRoute, int res, int n, int lin)
    {
        if (lin < 0 || lin >= n)
        {
            return 0.0f;
        }
        int cpf = res * res;
        int face = lin / cpf;
        int rem = lin % cpf;
        int y = rem / res;
        int x = rem % res;
        float h0 = hRoute[lin];
        float maxDropM = 0.0f;
        foreach (Vector2I d in Dirs8)
        {
            Vector3I nb = ClimateCellNeighbor(res, face, x, y, d.X, d.Y);
            if (nb.X == face && nb.Y == x && nb.Z == y)
            {
                continue;
            }
            int nlin = nb.X * cpf + nb.Z * res + nb.Y;
            if (nlin < 0 || nlin >= n)
            {
                continue;
            }
            float dropM = h0 - hRoute[nlin];
            if (dropM > maxDropM)
            {
                maxDropM = dropM;
            }
        }
        return Mathf.Clamp(maxDropM / 80.0f, 0.0f, 1.0f);
    }

    private static int UpstreamMaxContributorInBasin(int[] downstream, bool[] oceanMask, int[] basin, float[] flow, int res, int n, int lin, int basinId)
    {
        int cpf = res * res;
        int face = lin / cpf;
        int rem = lin % cpf;
        int y = rem / res;
        int x = rem % res;
        int bestLin = -1;
        float bestFlow = -1.0f;
        foreach (Vector2I d in Dirs8)
        {
            Vector3I nb = ClimateCellNeighbor(res, face, x, y, d.X, d.Y);
            if (nb.X == face && nb.Y == x && nb.Z == y)
            {
                continue;
            }
            int nlin = nb.X * cpf + nb.Z * res + nb.Y;
            if (nlin < 0 || nlin >= n)
            {
                continue;
            }
            if (oceanMask[nlin] || basin[nlin] != basinId || downstream[nlin] != lin)
            {
                continue;
            }
            float nf = flow[nlin];
            if (nf > bestFlow)
            {
                bestFlow = nf;
                bestLin = nlin;
            }
        }
        return bestLin;
    }

    private static void BoostMajorBasinTrunks(int[] downstream, bool[] oceanMask, int[] basin, float[] flowAccum, int res, int n, int majorTarget)
    {
        if (majorTarget <= 0)
        {
            return;
        }

        Dictionary<int, int> basinMouthLin = new();
        Dictionary<int, float> basinMouthFlow = new();
        for (int lin = 0; lin < n; lin++)
        {
            if (oceanMask[lin] || downstream[lin] != -1)
            {
                continue;
            }
            int bid = basin[lin];
            if (bid < 0)
            {
                continue;
            }
            float q = flowAccum[lin];
            if (!basinMouthFlow.TryGetValue(bid, out float prev) || q > prev)
            {
                basinMouthFlow[bid] = q;
                basinMouthLin[bid] = lin;
            }
        }

        List<int> majorIds = new();
        List<float> majorScores = new();
        foreach (KeyValuePair<int, float> kv in basinMouthFlow)
        {
            int bid = kv.Key;
            float score = kv.Value;
            int insertAt = -1;
            for (int i = 0; i < majorIds.Count; i++)
            {
                if (score > majorScores[i])
                {
                    insertAt = i;
                    break;
                }
            }
            if (insertAt < 0 && majorIds.Count < majorTarget)
            {
                insertAt = majorIds.Count;
            }
            if (insertAt < 0)
            {
                continue;
            }
            majorIds.Insert(insertAt, bid);
            majorScores.Insert(insertAt, score);
            if (majorIds.Count > majorTarget)
            {
                majorIds.RemoveAt(majorIds.Count - 1);
                majorScores.RemoveAt(majorScores.Count - 1);
            }
        }

        const float trunkBoost = 2.4f;
        foreach (int bid in majorIds)
        {
            if (!basinMouthLin.TryGetValue(bid, out int linT))
            {
                continue;
            }
            int guard = 0;
            while (linT >= 0 && guard < n)
            {
                flowAccum[linT] *= trunkBoost;
                int up = UpstreamMaxContributorInBasin(downstream, oceanMask, basin, flowAccum, res, n, linT, bid);
                if (up < 0)
                {
                    break;
                }
                linT = up;
                guard++;
            }
        }
    }

    private static float FlowRoutingBiasM(int res, int lin)
    {
        int cpf = res * res;
        int face = lin / cpf;
        int rem = lin % cpf;
        int y = rem / res;
        int x = rem % res;
        int h = HashCode.Combine(face * 73856093, x * 19349663, y * 83492791);
        int u = h & 0x7fffffff;
        return (u % 1_000_000) * 1e-9f;
    }

    private static (float slope, float tie) D8DownhillSlopeAndTie(int lin, int nlin, Vector2I d, float hSelf, float nhR)
    {
        float step = (d.X == 0 || d.Y == 0) ? D8StepCard : D8StepDiag;
        float slope = (hSelf - nhR) / step;
        int tieHash = unchecked(lin ^ (nlin * 1_039_513_289) ^ (d.X * 91_181_711) ^ (d.Y * 47_992_919));
        float tie = tieHash & 0x7fffffff;
        return (slope, tie);
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static Vector3I ClimateCellNeighbor(int res, int face, int x, int y, int dx, int dy) =>
        CubeSphereMath.climate_grid_neighbor(res, face, x, y, dx, dy);

    private static void ReportProgress(Callable progress, float value)
    {
        if (progress.Target == null && progress.Delegate == null)
        {
            return;
        }
        try
        {
            progress.Call(Variant.From(value));
        }
        catch
        {
            // Optional callback; ignore invalid/non-callable values.
        }
    }
}
