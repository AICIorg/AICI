extends StaticBody3D

signal valve_opening
signal valve_closing
signal water_level_changed(liters:  float, percentage: float)

@export var open_animation: String = "valvula_abrir_tanque"
@export var close_animation:  String = "valvula_cerrar_tanque"
@export var allow_interrupt: bool = true

# 💧 Sistema de agua
@export_group("Water System")
@export var tank_capacity: float = 100.0  # Litros totales
@export var drain_rate_open: float = 4.0  # Litros/segundo cuando está ABIERTA
@export var drain_rate_opening: float = 2.0  # Litros/segundo cuando está ABRIENDO
@export var drain_rate_closing: float = 1.0  # Litros/segundo cuando está CERRANDO

@onready var animation_player: AnimationPlayer = null
@onready var valveLabel3D = get_node_or_null("ValveLabel3D")
@onready var waterLevelLabel3D = get_node_or_null("WaterLevelLabel3D") 

enum ValveState { CLOSED, OPENING, OPEN, CLOSING }
var current_state: ValveState = ValveState. CLOSED

# Estado del agua
var current_water_liters: float = 100.0  # Empieza lleno
var is_draining: bool = false

var water_original_y: float = 0.0

# Charco de agua en el suelo
var water_puddle: MeshInstance3D = null
var puddle_max_radius: float = 8.0  # Radio máximo del charco
var puddle_growth_speed: float = 0.15  # Velocidad de crecimiento

func _ready() -> void:
	print("\n💧 ========== WATER TANK VALVE INIT ==========")
	# Inicializar agua al máximo
	current_water_liters = tank_capacity
	
	animation_player = _find_animation_player(self)
	if animation_player:
		animation_player.connect("animation_finished", Callable(self, "_on_animation_finished"))
		print("✅ AnimationPlayer conectado")
	
	# Conectar input_event para clicks
	self.connect("input_event", Callable(self, "_on_valve_input_event"))
	
	# Inicializar labels
	if valveLabel3D:
		valveLabel3D.visible = false
	
	if waterLevelLabel3D:
		waterLevelLabel3D.visible = true
		_update_water_level_label()
	
	await get_tree().process_frame
	var water = get_node_or_null("WaterVolume")
	if water:
		water_original_y = water.position.y
	else:
		print("⚠️ WaterVolume no encontrado (se creará cuando se active el tanque)")
		
	# Crear el charco de agua dinámico
	_create_water_puddle()
	
	print("==========================================\n")

func _process(delta: float) -> void:
	# Sistema de vaciado según el estado
	if current_water_liters > 0:
		var drain_amount = 0.0
		
		match current_state:
			ValveState.OPEN:
				# Válvula completamente abierta → máximo drenaje
				drain_amount = drain_rate_open * delta
			ValveState. OPENING:
				# Válvula abriéndose → drenaje medio
				drain_amount = drain_rate_opening * delta
			ValveState.CLOSING:
				# Válvula cerrándose → drenaje bajo
				drain_amount = drain_rate_closing * delta
			ValveState.CLOSED:
				# Válvula cerrada → NO drena
				drain_amount = 0.0
		
		if drain_amount > 0:
			current_water_liters = max(0.0, current_water_liters - drain_amount)
			_update_water_level_label()
			_update_water_shader()
			
			# Emitir señal de cambio de nivel
			emit_signal("water_level_changed", current_water_liters, get_water_percentage())
			
			# Si se vacía completamente
			if current_water_liters <= 0:
				print("⚠️ TANQUE VACÍO")
				_on_tank_empty()
	
	# Actualizar intensidad de partículas según el estado
	_update_particle_intensity()
	# actualizar el charco de agua
	_update_puddle(delta)

func _update_water_level_label() -> void:
	if not waterLevelLabel3D: 
		return
	
	var percentage = get_water_percentage()
	waterLevelLabel3D.text = "💧 %.1f L (%.0f%%)" % [current_water_liters, percentage]
	
	# Color según el nivel
	if percentage < 20:
		waterLevelLabel3D.modulate = Color(1, 0.2, 0.2)  # Rojo
	elif percentage < 50:
		waterLevelLabel3D.modulate = Color(1, 0.8, 0.2)  # Amarillo
	else:
		waterLevelLabel3D.modulate = Color(0.2, 1, 0.3)  # Verde
	
	# Agregar estado
	match current_state:
		ValveState.OPEN:
			waterLevelLabel3D.text += " (Vaciando)"
		ValveState.OPENING:
			waterLevelLabel3D.text += " (Abriendo... )"
		ValveState.CLOSING:
			waterLevelLabel3D.text += " (Cerrando...)"
		ValveState.CLOSED:
			if current_water_liters > 0:
				waterLevelLabel3D.text += " (Cerrada)"

func _update_water_shader() -> void:
	var water = get_node_or_null("WaterVolume")
	if not water:
		return
	var level_normalized = current_water_liters / tank_capacity
	# Si tiene shader, actualizar parámetro
	if water.material_override and water.material_override is ShaderMaterial:
		var mat = water.material_override
		mat.set_shader_parameter("water_level", level_normalized)
	
	# Si es MeshInstance3D, bajar nivel físicamente
	if water is MeshInstance3D:
		_update_water_cylinder_level(water, level_normalized)

func _update_water_cylinder_level(water: MeshInstance3D, level: float) -> void:
	# Si es la primera vez y no tenemos la posición original, guardarla
	if water_original_y == 0.0:
		water_original_y = water.position.y
	
	# Obtener altura del mesh
	var mesh = water. mesh as CylinderMesh
	if not mesh:
		return
	var original_height = mesh.height
	
	var scale_y = max(level, 0.01)
	water.scale.y = scale_y
	
	# anim de agua cayendo 
	var height_reduction = (original_height * (1.0 - level) / 2.0) - 0.8
	water.position.y = water_original_y - height_reduction
	
	# Visibilidad
	water.visible = (level > 0.01)
	
func _update_particle_intensity() -> void:
	var particles = get_node_or_null("ValveWaterParticles")
	if not particles:
		return
	
	# Ajustar amount según el estado y nivel de agua
	if current_water_liters <= 0:
		particles.emitting = false
		return
	
	var base_amount = 1500
	var intensity_factor = 1.0
	
	match current_state:
		ValveState.OPEN:
			intensity_factor = 1.0  # 100% intensidad
			particles.emitting = true
		ValveState.OPENING:
			intensity_factor = 0.5  # 50% intensidad
			particles.emitting = true
		ValveState.CLOSING: 
			intensity_factor = 0.3  # 30% intensidad
			particles.emitting = true
		ValveState.CLOSED: 
			particles.emitting = false
			return
	
	# Reducir intensidad si queda poca agua
	var water_factor = current_water_liters / tank_capacity
	intensity_factor *= water_factor
	
	particles.amount = int(base_amount * intensity_factor)

func _on_tank_empty() -> void:
	print("⚠️ TANQUE VACÍO")
	# Detener partículas
	var particles = get_node_or_null("ValveWaterParticles")
	if particles:
		particles.emitting = false
	# Actualizar label
	if waterLevelLabel3D:
		waterLevelLabel3D.text = "💧 VACÍO (0%)"
		waterLevelLabel3D.modulate = Color(1, 0, 0)

func get_water_percentage() -> float:
	return (current_water_liters / tank_capacity) * 100.0

func _on_valve_input_event(camera: Node, event: InputEvent, event_position:  Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb. pressed:
			interact()

func interact() -> void:
	if not animation_player:
		return
	
	if not allow_interrupt and animation_player.is_playing():
		print("water_tank_valve: animación en curso, bloqueado")
		return
	
	var anim_to_play: String = ""
	var new_state: ValveState
	
	match current_state:
		ValveState. CLOSED, ValveState. CLOSING:
			# Intentando abrir
			anim_to_play = open_animation
			new_state = ValveState. OPENING
		ValveState. OPEN, ValveState. OPENING:
			# Intentando cerrar (siempre permitido)
			anim_to_play = close_animation
			new_state = ValveState. CLOSING
	
	if animation_player.is_playing() and animation_player. current_animation == anim_to_play:
		print("water_tank_valve: ya reproduciendo ", anim_to_play)
		return
	
	if animation_player.has_animation(anim_to_play):
		current_state = new_state
		animation_player.play(anim_to_play)
		print("water_tank_valve: reproduciendo ", anim_to_play, " (estado: ", ValveState. keys()[current_state], ")")
		
		if valveLabel3D:
			if current_state == ValveState.OPENING:
				valveLabel3D.text = "Abriendo VÁLVULA"
				valveLabel3D.modulate = Color.WEB_GREEN
			elif current_state == ValveState.CLOSING:
				valveLabel3D.text = "Cerrando VÁLVULA"
				valveLabel3D. modulate = Color.YELLOW
		
		# Emitir señales
		if current_state == ValveState.OPENING: 
			emit_signal("valve_opening")
			print("🚰 Agua saliendo")
		elif current_state == ValveState.CLOSING:
			emit_signal("valve_closing")
			print("🛑 Cerrando flujo")
	else:
		push_warning("water_tank_valve: animación no encontrada:  " + anim_to_play)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == open_animation:
		current_state = ValveState.OPEN
		print("water_tank_valve: válvula ABIERTA")
		
		if valveLabel3D:
			valveLabel3D.text = "VÁLVULA ABIERTA"
			valveLabel3D.modulate = Color. GREEN
	
	elif anim_name == close_animation:
		current_state = ValveState.CLOSED
		print("water_tank_valve: válvula CERRADA")
		
		if valveLabel3D:
			valveLabel3D.text = "VÁLVULA CERRADA"
			valveLabel3D.modulate = Color.DARK_RED

func _find_animation_player(node: Node) -> AnimationPlayer: 
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var res = _find_animation_player(child)
		if res:
			return res
	return null

func _create_water_puddle() -> void:
	print("\n🔵 ========== CREANDO CHARCO ==========")
	
	var exit = get_node_or_null("ValveExit")
	if exit:
		print("✅ ValveExit encontrado en: ", exit.global_position)
	else:
		print("⚠️ ValveExit NO encontrado")
	
	# Crear el mesh del charco (cilindro chato)
	water_puddle = MeshInstance3D.new()
	water_puddle.name = "WaterPuddle"
	
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.5  # Pequeño pero visible
	cylinder.bottom_radius = 0.5
	cylinder. height = 0.08  # Muy chato (charco)
	water_puddle.mesh = cylinder
	
	# ✅ Material ROJO para debug (cambiar después a azul)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.90)   
	mat.emission_enabled = true
	mat. emission = Color(0.2, 0.6, 1.0, 0.90)   
	mat.emission_energy = 1.0
	water_puddle.material_override = mat
	
	water_puddle.visible = false
	water_puddle.scale = Vector3(0.1, 1.0, 0.1)  # Escala normal
	water_puddle.cast_shadow = GeometryInstance3D. SHADOW_CASTING_SETTING_OFF
	
	# Añadir al árbol PRIMERO
	add_child(water_puddle)
	water_puddle.global_position = self.global_position + Vector3(-4, 0, 0.5)
	


func _update_puddle(delta: float) -> void:
	if not water_puddle:
		return	
	# Determinar si el agua está cayendo
	var is_water_falling = false
	var growth_factor = 0.0
	
	match current_state:
		ValveState.OPEN:
			if current_water_liters > 0:
				is_water_falling = true
				growth_factor = 1.0  # Crece rápido
		ValveState.OPENING:
			if current_water_liters > 0:
				is_water_falling = true
				growth_factor = 0.5  # Crece medio
		ValveState.CLOSING:
			if current_water_liters > 0:
				is_water_falling = true
				growth_factor = 0.3  # Crece lento
		ValveState.CLOSED:
			is_water_falling = false  # No crece
				
	if is_water_falling:
		# Mostrar charco cuando empieza a caer agua
		if not water_puddle.visible:
			water_puddle.visible = true
			print("💧 Charco ahora visible - agua cayendo")
		
		var current_radius = water_puddle.scale.x
		# Crecer gradualmente hasta el máximo
		if current_radius < puddle_max_radius:
			var growth_speed = puddle_growth_speed * growth_factor * delta
			var new_radius = current_radius + growth_speed
			new_radius = min(new_radius, puddle_max_radius)  # No pasar del máximo
			
			water_puddle.scale = Vector3(new_radius, 1.0, new_radius)
	else:
		pass
