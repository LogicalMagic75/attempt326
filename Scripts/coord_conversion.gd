class_name CubeSphereMath
extends RefCounted

enum FaceID {
	RIGHT = 0,  # +X
	LEFT = 1,   # -X
	TOP = 2,    # +Y
	BOTTOM = 3, # -Y
	FRONT = 4,  # +Z
	BACK = 5    # -Z
}

## Translates a global 3D Vector3 position on a sphere into a (Face ID, X, Y) coordinate.
## Returns a Dictionary: {"face": FaceID, "x": float, "y": float} where x and y are in the range [0.0, 1.0].
static func get_face_coordinates(point_on_sphere: Vector3) -> Dictionary:
	# 1. Ensure the vector is normalized (assuming it's a unit sphere)
	var p: Vector3 = point_on_sphere.normalized()
	
	var abs_x: float = abs(p.x)
	var abs_y: float = abs(p.y)
	var abs_z: float = abs(p.z)
	
	var max_axis: float = max(abs_x, max(abs_y, abs_z))
	
	var face: int
	var u: float
	var v: float
	
	# 2. Determine Face ID and project to local [-1.0, 1.0] space
	if max_axis == abs_x:
		if p.x > 0:
			face = FaceID.RIGHT
			u = -p.z / max_axis
			v = p.y / max_axis
		else:
			face = FaceID.LEFT
			u = p.z / max_axis
			v = p.y / max_axis
	elif max_axis == abs_y:
		if p.y > 0:
			face = FaceID.TOP
			u = p.x / max_axis
			v = -p.z / max_axis
		else:
			face = FaceID.BOTTOM
			u = p.x / max_axis
			v = p.z / max_axis
	else:
		if p.z > 0:
			face = FaceID.FRONT
			u = p.x / max_axis
			v = p.y / max_axis
		else:
			face = FaceID.BACK
			u = -p.x / max_axis
			v = p.y / max_axis

	# 3. Remap from [-1.0, 1.0] to [0.0, 1.0] grid space
	var grid_x: float = (u + 1.0) * 0.5
	var grid_y: float = (v + 1.0) * 0.5
	
	return {
		"face": face,
		"x": grid_x,
		"y": grid_y
	}
