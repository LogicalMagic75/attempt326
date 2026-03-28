@tool
extends Node3D

## 6,700 km diameter → 3,350 km radius; 1 game unit = 10 m (see docs).
const PLANET_RADIUS_GAME_UNITS: float = 335_000.0

@export_group("Dimensions")
@export var radius: float = PLANET_RADIUS_GAME_UNITS:
	set(val):
		radius = val
		generate_sphere()

@export_range(2, 100) var resolution: int = 32:
	set(val):
		resolution = val
		generate_sphere()

func _ready() -> void:
	generate_sphere()

func generate_sphere() -> void:
	for child in get_children():
		child.queue_free()
		
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "SphereMesh"
	add_child(mesh_instance)
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var face_normals = [
		Vector3.MODEL_FRONT, Vector3.MODEL_REAR,
		Vector3.MODEL_LEFT, Vector3.MODEL_RIGHT,
		Vector3.MODEL_TOP, Vector3.MODEL_BOTTOM
	]
	
	var current_vertex_count = 0
	for normal in face_normals:
		current_vertex_count = create_face(st, normal, current_vertex_count)
	
	# Critical for Phase 5 aesthetics and correct lighting [cite: 47, 50]
	st.generate_normals()
	mesh_instance.mesh = st.commit()

func create_face(st: SurfaceTool, normal: Vector3, offset: int) -> int:
	var axis_a := Vector3(normal.y, normal.z, normal.x)
	var axis_b := normal.cross(axis_a)
	
	var vertices_added = 0
	
	for y in range(resolution):
		for x in range(resolution):
			var percent := Vector2(x, y) / (resolution - 1)
			var point_on_cube := normal + (percent.x - 0.5) * 2.0 * axis_a + (percent.y - 0.5) * 2.0 * axis_b
			var point_on_sphere := point_on_cube.normalized() * radius
			
			st.add_vertex(point_on_sphere)
			vertices_added += 1
			
			if x < resolution - 1 and y < resolution - 1:
				var i = x + y * resolution
				
				# FLIPPED WINDING ORDER: (offset + i, offset + i + resolution, offset + i + resolution + 1)
				# This ensures the 'front' of the face points away from the center.
				st.add_index(offset + i)
				st.add_index(offset + i + resolution)
				st.add_index(offset + i + resolution + 1)
				
				st.add_index(offset + i)
				st.add_index(offset + i + resolution + 1)
				st.add_index(offset + i + 1)
				
	return offset + vertices_added
