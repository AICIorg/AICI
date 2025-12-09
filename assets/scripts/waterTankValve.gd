extends StaticBody3D

signal valve_opening
signal valve_closing

@export var open_animation: String = "valvula_abrir_tanque"
@export var close_animation: String = "valvula_cerrar_tanque"
@export var allow_interrupt: bool = true  # nueva opción para habilitar/deshabilitar interrupción
@export var interaction_distance: float = 10.0  # Distancia para interactuar (aumentada para facilitar uso)

@onready var animation_player: AnimationPlayer = null
@onready var valveLabel3D = get_node_or_null("ValveLabel3D")
@onready var waterLevelLabel3D = get_node_or_null("WaterLevelLabel3D")
@onready var player: CharacterBody3D = null
@onready var water_mesh: MeshInstance3D = null

enum ValveState { CLOSED, OPENING, OPEN, CLOSING }
var current_state: ValveState = ValveState.CLOSED
var is_filling: bool = false
var water_level: float = 0.0  # 0 = vacío, 1 = lleno
var fill_speed: float = 0.15  # Velocidad de llenado/vaciado
var use_existing_water: bool = false  # Flag para usar WaterVolume existente

func _ready() -> void:
	animation_player = _find_animation_player(self)
	if animation_player:
		animation_player.connect("animation_finished", Callable(self, "_on_animation_finished"))
	
	# Buscar el jugador en la escena con múltiples intentos
	await get_tree().process_frame
	
	# Intento 1: Buscar por grupo
	player = get_tree().get_first_node_in_group("player")
	print("🔍 Búsqueda por grupo 'player': ", player)
	
	# Intento 2: Buscar por ruta absoluta
	if not player:
		player = get_node_or_null("/root/Node3D/Player")
		print("🔍 Búsqueda por ruta /root/Node3D/Player: ", player)
	
	# Intento 3: Buscar en la escena raíz
	if not player:
		var root = get_tree().root
		for child in root.get_children():
			print("🔍 Hijo de root: ", child.name)
			var p = child.find_child("Player", true, false)
			if p:
				player = p
				print("✅ Player encontrado: ", player)
				break
	
	if not player:
		print("❌ ERROR: No se encontró el jugador!")
	else:
		print("✅ Player configurado correctamente: ", player.name)
	
	# Buscar si ya existe un WaterVolume creado por Mundo.gd
	water_mesh = get_node_or_null("WaterVolume")
	if water_mesh:
		print("✅ Usando WaterVolume existente")
		use_existing_water = true
		water_mesh.visible = false
		water_mesh.scale = Vector3(1, 0, 1)
	else:
		# Si no existe, crear el mesh del agua dinámicamente
		print("⚠️ Creando nuevo mesh de agua")
		_create_water_mesh()
	
	# Debug: Verificar que los labels existen
	print("🏷️ ValveLabel3D: ", valveLabel3D)
	print("🏷️ WaterLevelLabel3D: ", waterLevelLabel3D)
	
	if valveLabel3D:
		valveLabel3D.visible = false
		print("✅ ValveLabel3D configurado")
	
	if waterLevelLabel3D:
		waterLevelLabel3D.visible = false
		print("✅ WaterLevelLabel3D configurado")

func _process(delta: float) -> void:
	if not player:
		# Intentar encontrar el jugador cada frame si no existe
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return
	
	# Verificar distancia al jugador
	var distance = global_position.distance_to(player.global_position)
	
	# Debug periódico cada 60 frames
	if Engine.get_process_frames() % 60 == 0:
		print("📏 Distancia al tanque: %.2f m (límite: %.2f m)" % [distance, interaction_distance])
		print("📍 Posición tanque: ", global_position)
		print("📍 Posición player: ", player.global_position)
	
	# Mostrar/ocultar indicador de interacción
	if distance <= interaction_distance:
		if valveLabel3D:
			valveLabel3D.visible = true
			if current_state == ValveState.CLOSED or current_state == ValveState.CLOSING:
				valveLabel3D.text = "Presiona [E] para abrir"
				valveLabel3D.modulate = Color(1, 1, 1, 1)  # Blanco
			elif current_state == ValveState.OPEN or current_state == ValveState.OPENING:
				valveLabel3D.text = "Presiona [E] para cerrar"
				valveLabel3D.modulate = Color(1, 0.3, 0.3, 1)  # Rojo claro
			print("👁️ Label visible: ", valveLabel3D.text)
		
		# Detectar tecla E
		if Input.is_action_just_pressed("interact"):
			interact()
	else:
		if valveLabel3D:
			valveLabel3D.visible = false
	
	# Actualizar nivel de agua
	_update_water_level(delta)
	
	# Actualizar indicador de nivel de agua
	if waterLevelLabel3D:
		# Mostrar siempre que hay agua o la válvula está abierta
		if water_level > 0 or current_state == ValveState.OPEN or current_state == ValveState.OPENING:
			waterLevelLabel3D.visible = true
			var percentage = int(water_level * 100)
			waterLevelLabel3D.text = "Nivel: %d%%" % percentage
			
			# Cambiar color según el nivel
			if water_level < 0.3:
				waterLevelLabel3D.modulate = Color(1, 0.3, 0.3, 1)  # Rojo bajo
			elif water_level < 0.7:
				waterLevelLabel3D.modulate = Color(1, 1, 0.3, 1)  # Amarillo medio
			else:
				waterLevelLabel3D.modulate = Color(0.3, 1, 0.3, 1)  # Verde alto
			
			# Agregar estado de la válvula
			if current_state == ValveState.OPEN or current_state == ValveState.OPENING:
				waterLevelLabel3D.text += " (Llenando)"
			elif current_state == ValveState.CLOSING and water_level > 0:
				waterLevelLabel3D.text += " (Vaciando)"
		else:
			waterLevelLabel3D.visible = false

func _create_water_mesh() -> void:
	# Crear un cilindro para el agua
	water_mesh = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.8  # Radio del tanque
	cylinder_mesh.bottom_radius = 0.8
	cylinder_mesh.height = 2.0  # Altura máxima del agua
	water_mesh.mesh = cylinder_mesh
	
	# Crear material para el agua
	var water_material = StandardMaterial3D.new()
	water_material.albedo_color = Color(0.2, 0.5, 0.8, 0.6)  # Color azul semi-transparente
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.1
	water_material.metallic = 0.3
	water_mesh.material_override = water_material
	
	# Posicionar el agua dentro del tanque
	water_mesh.position = Vector3(0, -0.5, 0)  # Ajustar según tu tanque
	water_mesh.scale = Vector3(1, 0, 1)  # Empezar sin altura (invisible)
	water_mesh.visible = false  # Comienza invisible
	add_child(water_mesh)

func _update_water_level(delta: float) -> void:
	if not water_mesh:
		return
	
	if is_filling:
		# Llenando
		water_level = min(water_level + fill_speed * delta, 1.0)
		if water_level >= 1.0:
			is_filling = false
	else:
		# Vaciando
		water_level = max(water_level - fill_speed * delta, 0.0)
	
	# Actualizar la escala del agua (solo en Y)
	water_mesh.scale = Vector3(1, water_level, 1)
	
	# Controlar visibilidad: mostrar solo si hay agua
	if water_level > 0.01:
		water_mesh.visible = true
	else:
		water_mesh.visible = false
	
	# Controlar visibilidad: mostrar solo si hay agua
	if water_level > 0.01:
		water_mesh.visible = true
	else:
		water_mesh.visible = false

func _update_label() -> void:
	if not valveLabel3D:
		return
	
	match current_state:
		ValveState.CLOSED:
			valveLabel3D.text = "[E] Abrir válvula"
			valveLabel3D.modulate = Color.DARK_RED
		ValveState.OPEN:
			valveLabel3D.text = "[E] Cerrar válvula"
			valveLabel3D.modulate = Color.GREEN
		ValveState.OPENING:
			valveLabel3D.text = "Abriendo..."
			valveLabel3D.modulate = Color.YELLOW
		ValveState.CLOSING:
			valveLabel3D.text = "Cerrando..."
			valveLabel3D.modulate = Color.ORANGE

func interact() -> void:
	if not animation_player:
		return

	# Si allow_interrupt es false, ignorar inputs mientras se reproduce
	if not allow_interrupt and animation_player.is_playing():
		print("water_tank_valve: animación en curso, bloqueado")
		return

	# Determinar qué animación reproducir según el estado actual/deseado
	var anim_to_play: String = ""
	var new_state: ValveState
	
	match current_state:
		ValveState.CLOSED, ValveState.CLOSING:
			# Si está cerrada o cerrándose, queremos abrir
			anim_to_play = open_animation
			new_state = ValveState.OPENING
			is_filling = true  # Empezar a llenar
		ValveState.OPEN, ValveState.OPENING:
			# Si está abierta o abriéndose, queremos cerrar
			anim_to_play = close_animation
			new_state = ValveState.CLOSING
			is_filling = false  # Empezar a vaciar

	# Si ya está reproduciendo la misma animación que queremos, no hacer nada
	if animation_player.is_playing() and animation_player.current_animation == anim_to_play:
		print("water_tank_valve: ya reproduciendo ", anim_to_play)
		return

	# Reproducir la nueva animación (interrumpe la anterior si estaba corriendo)
	if animation_player.has_animation(anim_to_play):
		current_state = new_state
		animation_player.play(anim_to_play)
		print("water_tank_valve: reproduciendo ", anim_to_play, " (estado: ", ValveState.keys()[current_state], ")")
		
		_update_label()
		
		if current_state == ValveState.OPENING:
			emit_signal("valve_opening")
			print("Válvula abriendo - agua llenando")
		elif current_state == ValveState.CLOSING:
			emit_signal("valve_closing")
			print("Válvula cerrando - agua vaciando")
			
	else:
		push_warning("water_tank_valve: animación no encontrada: " + anim_to_play)

func _on_animation_finished(anim_name: String) -> void:
	# Actualizar estado final solo cuando termina completamente
	if anim_name == open_animation:
		current_state = ValveState.OPEN
		print("water_tank_valve: válvula ABIERTA")
		_update_label()

	elif anim_name == close_animation:
		current_state = ValveState.CLOSED
		print("water_tank_valve: válvula CERRADA")
		_update_label()

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var res = _find_animation_player(child)
		if res:
			return res
	return null
