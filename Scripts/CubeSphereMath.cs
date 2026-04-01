using Godot;

public static class CubeSphereMath
{
    public enum FaceID
    {
        RIGHT = 0,
        LEFT = 1,
        TOP = 2,
        BOTTOM = 3,
        FRONT = 4,
        BACK = 5
    }

    public struct FaceUV
    {
        public int Face;
        public Godot.Vector2 Uv;
    }

    public static readonly Godot.Collections.Array<string> EXR_FACE_NAMES =
    [
        "right", "left", "top", "bottom", "front", "back"
    ];

    public static Godot.Collections.Dictionary get_face_coordinates(Godot.Vector3 point_on_sphere)
    {
        Godot.Vector3 p = point_on_sphere.Normalized();
        FaceUV r = unit_direction_to_face_uv01(p);
        return new Godot.Collections.Dictionary
        {
            { "face", r.Face },
            { "x", r.Uv.X },
            { "y", r.Uv.Y }
        };
    }

    public static FaceUV unit_direction_to_face_uv01(Godot.Vector3 dir)
    {
        Godot.Vector3 p = dir.Normalized();
        float ax = (float)Godot.Mathf.Abs(p.X);
        float ay = (float)Godot.Mathf.Abs(p.Y);
        float az = (float)Godot.Mathf.Abs(p.Z);
        int face;
        Godot.Vector2 uv;
        float d;

        if (ax >= ay && ax >= az)
        {
            d = Godot.Mathf.Max(ax, 1e-8f);
            if (p.X > 0.0f)
            {
                face = (int)FaceID.RIGHT;
                uv = new Godot.Vector2(p.Z / (2.0f * d) + 0.5f, 0.5f - p.Y / (2.0f * d));
            }
            else
            {
                face = (int)FaceID.LEFT;
                uv = new Godot.Vector2(0.5f - p.Z / (2.0f * d), 0.5f - p.Y / (2.0f * d));
            }
        }
        else if (ay >= ax && ay >= az)
        {
            d = Godot.Mathf.Max(ay, 1e-8f);
            if (p.Y > 0.0f)
            {
                face = (int)FaceID.TOP;
                uv = new Godot.Vector2(p.X / (2.0f * d) + 0.5f, 0.5f - p.Z / (2.0f * d));
            }
            else
            {
                face = (int)FaceID.BOTTOM;
                uv = new Godot.Vector2(0.5f - p.X / (2.0f * d), 0.5f - p.Z / (2.0f * d));
            }
        }
        else
        {
            d = Godot.Mathf.Max(az, 1e-8f);
            if (p.Z > 0.0f)
            {
                face = (int)FaceID.FRONT;
                uv = new Godot.Vector2(0.5f + p.Y / (2.0f * d), 0.5f - p.X / (2.0f * d));
            }
            else
            {
                face = (int)FaceID.BACK;
                uv = new Godot.Vector2(0.5f - p.Y / (2.0f * d), 0.5f - p.X / (2.0f * d));
            }
        }

        return new FaceUV
        {
            Face = face,
            Uv = uv
        };
    }

    public static Godot.Vector3I unit_direction_to_nearest_cell(int res, Godot.Vector3 dir_unit)
    {
        Godot.Vector3 p = dir_unit.Normalized();
        float ax = (float)Godot.Mathf.Abs(p.X);
        float ay = (float)Godot.Mathf.Abs(p.Y);
        float az = (float)Godot.Mathf.Abs(p.Z);
        int face;
        Godot.Vector2 uv;
        float d;

        if (ax >= ay && ax >= az)
        {
            d = Godot.Mathf.Max(ax, 1e-8f);
            if (p.X > 0.0f)
            {
                face = (int)FaceID.RIGHT;
                uv = new Godot.Vector2(p.Z / (2.0f * d) + 0.5f, 0.5f - p.Y / (2.0f * d));
            }
            else
            {
                face = (int)FaceID.LEFT;
                uv = new Godot.Vector2(0.5f - p.Z / (2.0f * d), 0.5f - p.Y / (2.0f * d));
            }
        }
        else if (ay >= ax && ay >= az)
        {
            d = Godot.Mathf.Max(ay, 1e-8f);
            if (p.Y > 0.0f)
            {
                face = (int)FaceID.TOP;
                uv = new Godot.Vector2(p.X / (2.0f * d) + 0.5f, 0.5f - p.Z / (2.0f * d));
            }
            else
            {
                face = (int)FaceID.BOTTOM;
                uv = new Godot.Vector2(0.5f - p.X / (2.0f * d), 0.5f - p.Z / (2.0f * d));
            }
        }
        else
        {
            d = Godot.Mathf.Max(az, 1e-8f);
            if (p.Z > 0.0f)
            {
                face = (int)FaceID.FRONT;
                uv = new Godot.Vector2(0.5f + p.Y / (2.0f * d), 0.5f - p.X / (2.0f * d));
            }
            else
            {
                face = (int)FaceID.BACK;
                uv = new Godot.Vector2(0.5f - p.Y / (2.0f * d), 0.5f - p.X / (2.0f * d));
            }
        }

        uv.X = Godot.Mathf.Clamp(uv.X, 0.0f, 1.0f);
        uv.Y = Godot.Mathf.Clamp(uv.Y, 0.0f, 1.0f);
        float dsc = Godot.Mathf.Max(res - 1, 1);
        int xi = Godot.Mathf.Clamp((int)Godot.Mathf.Round(uv.X * dsc), 0, res - 1);
        int yi = Godot.Mathf.Clamp((int)Godot.Mathf.Round(uv.Y * dsc), 0, res - 1);
        return new Godot.Vector3I(face, xi, yi);
    }

    public static Godot.Vector3 face_uv01_to_cube_point(int face, Godot.Vector2 uv)
    {
        Godot.Vector3 normal = _face_center_normal(face);
        Godot.Vector3 axis_a = new Godot.Vector3(normal.Y, normal.Z, normal.X);
        Godot.Vector3 axis_b = normal.Cross(axis_a);
        return normal
            + (uv.X - 0.5f) * 2.0f * axis_a
            + (uv.Y - 0.5f) * 2.0f * axis_b;
    }

    public static Godot.Vector3 face_uv01_to_unit_direction(int face, Godot.Vector2 uv)
    {
        return face_uv01_to_cube_point(face, uv).Normalized();
    }

    public static Godot.Vector3 _face_center_normal(int face)
    {
        switch (face)
        {
            case (int)FaceID.RIGHT:
                return new Godot.Vector3(1, 0, 0);
            case (int)FaceID.LEFT:
                return new Godot.Vector3(-1, 0, 0);
            case (int)FaceID.TOP:
                return new Godot.Vector3(0, 1, 0);
            case (int)FaceID.BOTTOM:
                return new Godot.Vector3(0, -1, 0);
            case (int)FaceID.FRONT:
                return new Godot.Vector3(0, 0, 1);
            case (int)FaceID.BACK:
                return new Godot.Vector3(0, 0, -1);
            default:
                return new Godot.Vector3(0, 0, 1);
        }
    }

    public static Godot.Vector3I climate_grid_neighbor(int res, int face, int x, int y, int dx, int dy)
    {
        int nx = x + dx;
        int ny = y + dy;
        if (nx >= 0 && nx < res && ny >= 0 && ny < res)
        {
            return new Godot.Vector3I(face, nx, ny);
        }

        float f_res = Godot.Mathf.Max(res, 1);
        float u = (x + 0.5f) / f_res;
        float v = (y + 0.5f) / f_res;
        float u2 = u + dx / f_res;
        float v2 = v + dy / f_res;
        Godot.Vector3 p = face_uv01_to_cube_point(face, new Godot.Vector2(u2, v2));
        Godot.Vector3 dir = p.Normalized();
        FaceUV r = unit_direction_to_face_uv01(dir);
        int nf = Godot.Mathf.Clamp(r.Face, 0, (int)FaceID.BACK);
        Godot.Vector2 uv_out = r.Uv;
        int qx = Godot.Mathf.Clamp((int)Godot.Mathf.Floor(uv_out.X * f_res), 0, res - 1);
        int qy = Godot.Mathf.Clamp((int)Godot.Mathf.Floor(uv_out.Y * f_res), 0, res - 1);
        return new Godot.Vector3I(nf, qx, qy);
    }
}
