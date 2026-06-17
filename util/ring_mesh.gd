class_name RingMesh
extends RefCounted

# Flat ground-indicator mesh builders for combat (attack arcs, sweeping rings, parry discs).
# Each method appends one surface to the given ImmediateMesh, so a fill plus an outline is
# just two calls on the same mesh.


static func add_sector_fill(mesh: ImmediateMesh, mat: Material, radius: float,
		center_angle: float, half_arc: float, y: float = 0.0, segments: int = 48) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for i in range(segments):
		var a1 := center_angle - half_arc + float(i) / segments * (half_arc * 2.0)
		var a2 := center_angle - half_arc + float(i + 1) / segments * (half_arc * 2.0)
		mesh.surface_add_vertex(Vector3(0.0, y, 0.0))
		mesh.surface_add_vertex(Vector3(sin(a2) * radius, y, cos(a2) * radius))
		mesh.surface_add_vertex(Vector3(sin(a1) * radius, y, cos(a1) * radius))
	mesh.surface_end()


static func add_sector_outline(mesh: ImmediateMesh, mat: Material, radius: float,
		center_angle: float, half_arc: float, y: float = 0.0, segments: int = 16) -> void:
	# Arc along the rim plus a spoke back to the center at each end.
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	mesh.surface_add_vertex(Vector3(0.0, y, 0.0))
	for i in range(segments + 1):
		var a := center_angle - half_arc + float(i) / segments * (half_arc * 2.0)
		mesh.surface_add_vertex(Vector3(sin(a) * radius, y, cos(a) * radius))
	mesh.surface_add_vertex(Vector3(0.0, y, 0.0))
	mesh.surface_end()


static func add_disc(mesh: ImmediateMesh, mat: Material, radius: float,
		y: float = 0.0, segments: int = 48) -> void:
	add_sector_fill(mesh, mat, radius, 0.0, PI, y, segments)


static func add_circle_outline(mesh: ImmediateMesh, mat: Material, radius: float,
		y: float = 0.0, segments: int = 48) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in range(segments + 1):
		var a := float(i) / segments * TAU
		mesh.surface_add_vertex(Vector3(sin(a) * radius, y, cos(a) * radius))
	mesh.surface_end()


static func add_annulus_sweep(mesh: ImmediateMesh, mat: Material, inner: float, outer: float,
		start_angle: float, span: float, y: float = 0.0, segments: int = 48) -> void:
	# A thick ring band that fills clockwise from start_angle by `span` radians.
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for i in range(segments):
		var a1 := start_angle - float(i) / segments * span
		var a2 := start_angle - float(i + 1) / segments * span
		mesh.surface_add_vertex(Vector3(sin(a1) * outer, y, cos(a1) * outer))
		mesh.surface_add_vertex(Vector3(sin(a2) * outer, y, cos(a2) * outer))
		mesh.surface_add_vertex(Vector3(sin(a2) * inner, y, cos(a2) * inner))
		mesh.surface_add_vertex(Vector3(sin(a1) * outer, y, cos(a1) * outer))
		mesh.surface_add_vertex(Vector3(sin(a2) * inner, y, cos(a2) * inner))
		mesh.surface_add_vertex(Vector3(sin(a1) * inner, y, cos(a1) * inner))
	mesh.surface_end()
