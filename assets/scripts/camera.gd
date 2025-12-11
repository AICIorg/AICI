extends CharacterBody3D

var speed
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 4.8
const SENSITIVITY = 0.004

# bob variables
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

# fov variables
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = 9.8

@onready var head = $Node3D
@onready var camera = $Node3D/Camera3D

# --- Interacción (configurar en el Inspector si querés) ---
@export var ui_line_edit: LineEdit = null        # opcional: evita clicks cuando el chat tiene foco
@export var info_label: Node = null              # opcional: Label o RichTextLabel para mensajes
@export var default_interact_distance: float = 3.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	# Rotación de cámara por movimiento del mouse
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40), deg_to_rad(60))
		# Detectar cuando se presiona Esc (ui_cancel)
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # Liberar mouse
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # Volver a capturarlo

	# Manejo de clicks: llamamos al handler si es botón del mouse
	if event is InputEventMouseButton:
		_handle_click_interaction(event)

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle Sprint.
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)

	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)

	# FOV
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)

	move_and_slide()

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

# ---------------- Click / interacción ----------------
func _handle_click_interaction(event: InputEventMouseButton) -> void:
	# Solo al presionar y con botón izquierdo
	if not event.pressed:
		return
	if event.button_index != MouseButton.MOUSE_BUTTON_LEFT:
		return

	# Evitar procesar clicks si el LineEdit del chat tiene foco
	if ui_line_edit and ui_line_edit.has_focus():
		return

	# Ray desde la cámara usando la posición del mouse
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 200.0

	var space = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(params)
	if not result or result.empty():
		_set_info("No se hizo click sobre ningún objeto.")
		return

	var collider = result.collider
	if not collider:
		_set_info("Collider nulo.")
		return

	# Subir por la jerarquía hasta encontrar nodo con group "interactive" o método interact()
	var node = collider
	while node and not node.is_in_group("interactive") and not node.has_method("interact"):
		node = node.get_parent()

	if not node:
		_set_info("Objeto no interactivo.")
		return

	# Comprobar proximidad (si el Interactable exportó require_proximity)
	var max_dist = default_interact_distance
	if node.has("require_proximity"):
		max_dist = float(node.get("require_proximity"))

	var cam_pos = camera.global_transform.origin
	var node_pos = node.global_transform.origin
	var dist = cam_pos.distance_to(node_pos)

	if dist > max_dist:
		_set_info("Acercate más a " + node.name + " (" + str(dist) + "m > " + str(max_dist) + "m)")
		return

	# Invocar interact()
	if node.has_method("interact"):
		node.interact()
		_set_info("Interaccionando con: " + node.name)
	else:
		# fallback: reproducir la primera animación si existe
		var ap = findAnimationPlayerInNode(node)
		if ap and ap.get_animation_list().size() > 0:
			ap.play(ap.get_animation_list()[0])
			_set_info("Reproduciendo animación (fallback) en " + node.name)
		else:
			_set_info("Nada para reproducir en " + node.name)

func findAnimationPlayerInNode(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var res = findAnimationPlayerInNode(child)
		if res:
			return res
	return null

func _set_info(text: String) -> void:
	print("[camera] ", text)
	if info_label:
		if info_label is RichTextLabel:
			info_label.append_bbcode("\n[color=lightblue]" + text + "[/color]")
		elif info_label is Label:
			info_label.text = text
