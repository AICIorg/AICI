extends StaticBody3D

signal valve_opening
signal valve_closing

@export var open_animation: String = "valvula_abrir_tanque"
@export var close_animation: String = "valvula_cerrar_tanque"
@export var allow_interrupt: bool = true  # nueva opción para habilitar/deshabilitar interrupción

@onready var animation_player: AnimationPlayer = null
@onready var valveLabel3D = get_node_or_null("ValveLabel3D")

enum ValveState { CLOSED, OPENING, OPEN, CLOSING }
var current_state: ValveState = ValveState. CLOSED

func _ready() -> void:
	animation_player = _find_animation_player(self)
	if animation_player:
		animation_player.connect("animation_finished", Callable(self, "_on_animation_finished"))
	
	self.connect("input_event", Callable(self, "_on_valve_input_event"))

func _on_valve_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb. pressed:
			interact()

func interact() -> void:
	if not animation_player:
		return

	# Si allow_interrupt es false, ignorar clicks mientras se reproduce
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
		ValveState.OPEN, ValveState.OPENING:
			# Si está abierta o abriéndose, queremos cerrar
			anim_to_play = close_animation
			new_state = ValveState. CLOSING

	# Si ya está reproduciendo la misma animación que queremos, no hacer nada
	if animation_player.is_playing() and animation_player.current_animation == anim_to_play:
		print("water_tank_valve: ya reproduciendo ", anim_to_play)
		return

	# Reproducir la nueva animación (interrumpe la anterior si estaba corriendo)
	if animation_player.has_animation(anim_to_play):
		current_state = new_state
		animation_player.play(anim_to_play)
		print("water_tank_valve: reproduciendo ", anim_to_play, " (estado: ", ValveState. keys()[current_state], ")")
		
		if current_state == ValveState.OPENING:
			valveLabel3D.text = "Abriendo VÁLVULA"
			valveLabel3D.modulate = Color.WEB_GREEN
			emit_signal("valve_opening")
			print("sale agua")
			var parts = get_tree().get_nodes_in_group("debug_particles")
			print("DEBUG PARTICLES EN ESCENA:", parts)
		elif current_state == ValveState.CLOSING:
			valveLabel3D.text = "Cerrando VÁLVULA"
			valveLabel3D.modulate = Color.RED
			emit_signal("valve_closing")
			
	else:
		push_warning("water_tank_valve: animación no encontrada: " + anim_to_play)

func _on_animation_finished(anim_name: String) -> void:
	# Actualizar estado final solo cuando termina completamente
	if anim_name == open_animation:
		current_state = ValveState.OPEN
		print("water_tank_valve: válvula ABIERTA")
		valveLabel3D.text = "VÁLVULA TOTALMENTE ABIERTA"
		valveLabel3D.modulate = Color.GREEN

		# bajar el nivel del agua
		var water = self.get_node("WaterVolume")
		var mat = water.material_override
		mat.set_shader_parameter("water_level", 0.1)

		# 🔵 ACTIVAR partículas (si existen)
		var particles := get_node_or_null("ValveWaterParticles")
		if particles:
			particles.emitting = true

	elif anim_name == close_animation:
		current_state = ValveState.CLOSED
		print("water_tank_valve: válvula CERRADA")
		valveLabel3D.text = "VÁLVULA TOTALMENTE CERRADA"
		valveLabel3D.modulate = Color.DARK_RED

		var water = self.get_node("WaterVolume")
		var mat = water.material_override
		mat.set_shader_parameter("water_level", 1.0) # lleno otra vez

		# 🔴 DESACTIVAR partículas (si existen)
		var particles := get_node_or_null("ValveWaterParticles")
		if particles:
			particles.emitting = false

	


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var res = _find_animation_player(child)
		if res:
			return res
	return null
