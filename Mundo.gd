extends Node3D

# --- TUS VARIABLES ---
@export var line_edit: LineEdit
@export var rich_text_label: RichTextLabel
@export var sub_viewport_node: SubViewport
@export var chat_ui: Control  # Nueva referencia al ChatUI

# ¡NUEVA VARIABLE! - OpenAI HTTPRequest
@export var openai_request: HTTPRequest
@onready var sprite = $Sprite3D
@onready var camera = $Player/Head/Camera3D
@onready var camera_controller = $Player/Head/Camera3D # Referencia al script de la cámara
@onready var water_tank_valve = $waterTankValve

var isVisible = false
var is_dragging_chat = false
var drag_start_pos = Vector2.ZERO

# Sistema de instrucciones y visión
var system_prompt = ""
var conversation_history = []
var screenshot_data = ""

# 🔑 OPENAI API KEY (desde localStorage del navegador)
var api_key = ""
var api_key_configured = false
var api_key_dialog_shown = false

# 🌐 URL de la API de OpenAI (GPT-4 Vision)
var api_url = "https://api.openai.com/v1/chat/completions"

# 🔒 CONTROL DE PETICIONES: Una a la vez (no queue system)
var is_processing_request = false  # Simple boolean lock
var retry_count = 0
var MAX_RETRIES = 3
var current_request_data = null  # Para reintentos si falla

# --- NUEVO: referencia al AssetManager ---
@onready var asset_manager = $AssetManager

var spawned_assets: Array = []

# NUEVO: Contador de instancias por asset
var asset_spawn_count = {}

# NUEVO: Límites de spawneo por asset (cuántos máximo se pueden crear)
var asset_spawn_limits = {
	"valvula": 1,
	"fresadora": 1,
	"chiller": 1,
	"llave": 5,
	"panel": 1,
	"tanque de agua": 1,
}

#  NUEVO: Posiciones y rotaciones fijas para assets específicos
#TODO: BORRAR ESTO PARA QUE SEA MAS DINAMICO Y NO ESTE TAN HARDCODED
var fixed_positions = {
	"valvula": {
		"position": Vector3(0.657, 0.05, 0.96),
		"rotation": Vector3(0, 0, 0)
	},
	"fresadora": {
		"position": Vector3(-2.759, -1.027, -2.221),
		"rotation": Vector3(0, -180, 0)  # Y rotado -180 grados
	},
	"chiller": {
		"position": Vector3(3.811, -1.755, -6.491),
		"rotation": Vector3(0, 90, 0)
	},
	"panel": {
		"position": Vector3(0, 0, 0),
		"rotation": Vector3(0, 0, 0)
	}
}


func _ready():
	# Cargar el system prompt desde el archivo
	load_system_prompt()

	# 🔑 Intentar cargar API key desde localStorage (web) o variable de entorno (desktop)
	load_api_key()

	# 1. Conectar la UI (esto ya lo tenías)
	line_edit.text_submitted.connect(_on_text_submitted)

	# Conectar señales de focus del LineEdit
	line_edit.focus_entered.connect(_on_line_edit_focus_exited)
	line_edit.focus_exited.connect(_on_line_edit_focus_entered)

	# 2. ¡CONEXIÓN OPENAI!
	# Conectamos la señal de "request_completed" del nodo HTTPRequest
	openai_request.request_completed.connect(_on_request_completed)

	# Mensaje de bienvenida
	show_welcome_message()

# 🔑 Cargar API key desde localStorage (solo web)
func load_api_key():
	# Intentar cargar desde localStorage
	if OS.has_feature("web"):
		var js_code = "localStorage.getItem('openai_api_key') || ''"
		api_key = JavaScriptBridge.eval(js_code)
		if api_key != "" and api_key != "null":
			api_key_configured = true
			print("🔑 API key cargada desde localStorage")
		else:
			print("⚠️ No hay API key en localStorage")
	else:
		print("⚠️ No hay API key configurada (modo desktop requiere /setkey)")

# 💾 Guardar API key en localStorage (solo web)
func save_api_key(key: String):
	if OS.has_feature("web"):
		var js_code = "localStorage.setItem('openai_api_key', '" + key + "')"
		JavaScriptBridge.eval(js_code)
		print("💾 API key guardada en localStorage")
	else:
		print("💾 API key guardada en memoria (solo sesión actual)")
	api_key = key
	api_key_configured = true

# 🗑️ Eliminar API key
func clear_api_key():
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.removeItem('openai_api_key')")
	api_key = ""
	api_key_configured = false
	print("🗑️ API key eliminada")

# 📝 Mostrar mensaje de bienvenida
func show_welcome_message():
	if api_key_configured:
		rich_text_label.text = "[color=orange]🏭 Asistente Industrial:[/color] ¡Hola! Soy tu asistente de enseñanza industrial.\n\n💡 Puedo ayudarte con:\n- Explicaciones sobre herramientas y equipos\n- Insertar objetos 3D en el simulador\n- Responder preguntas técnicas\n\n¿En qué puedo ayudarte?"
	else:
		rich_text_label.text = "[color=yellow]⚠️ API Key Requerida[/color]\n\nPara usar el asistente, necesitas una API key de OpenAI.\n\n📋 [color=lightblue]Pasos:[/color]\n1. Ve a: [color=cyan]https://platform.openai.com/api-keys[/color]\n2. Crea una cuenta (gratis)\n3. Genera una API key\n4. Escribe: [color=green]/setkey tu-api-key-aqui[/color]\n\n💡 Tu key se guardará localmente en tu navegador."

func load_system_prompt():
	var file_path = "res://system_prompt_industrial.md"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		system_prompt = file.get_as_text()
		file.close()
		print("✅ System prompt cargado: ", system_prompt.length(), " caracteres")
	else:
		print("⚠️ No se encontró system_prompt_industrial.md, usando prompt básico")
		system_prompt = "Eres un asistente de enseñanza industrial especializado en equipamiento, herramientas y procesos industriales. Ayuda a los usuarios a aprender de manera clara y práctica."
	system_prompt += "\n\nIMPORTANTE:\n" \
		+ "Cuando el usuario pida insertar, agregar, crear o mostrar un objeto 3D, " \
		+ "debes responder SOLO en formato JSON, sin texto adicional, con las siguientes claves:\n" \
		+ "{ \"action\": \"insert\", \"asset\": \"<nombre_del_asset>\" }\n" \
		+ "Ejemplo: {\"action\":\"insert\",\"asset\":\"fresadora\"}"


# --- 2. FUNCIÓN MODIFICADA - ALWAYS CAPTURE ---
func _on_text_submitted(text):
	rich_text_label.text += "\n[color=lightblue]Tú:[/color] " + text
	line_edit.text = ""
	line_edit.grab_focus()  # ✅ Mantener foco después de enviar

	# 🔑 Comando especial: /setkey para configurar API key
	if text.begins_with("/setkey "):
		var new_key = text.substr(8).strip_edges()
		if new_key.length() > 20:  # Validación básica
			save_api_key(new_key)
			rich_text_label.text += "\n[color=green]✅ API key configurada correctamente![/color]\n\n" + \
				"[color=orange]Bot:[/color] Ahora puedes usar el asistente. ¿En qué puedo ayudarte?"
		else:
			rich_text_label.text += "\n[color=red]❌ Error: API key inválida (muy corta)[/color]"
		return

	# 🔑 Comando especial: /clearkey para eliminar API key
	if text == "/clearkey":
		clear_api_key()
		rich_text_label.text += "\n[color=yellow]🗑️ API key eliminada[/color]"
		show_welcome_message()
		return

	# 🚫 Verificar que haya API key configurada
	if not api_key_configured or api_key == "":
		rich_text_label.text += "\n[color=red]❌ Error: No hay API key configurada[/color]\n\n" + \
			"Usa el comando: [color=green]/setkey tu-api-key-aqui[/color]"
		return

	# 🧠 CAPTURA INTELIGENTE: Siempre capturar (GPT-4o decide si la usa)
	rich_text_label.text += "\n[color=orange]Bot:[/color] Pensando..."

	# Siempre tomar captura para contexto visual
	await take_screenshot()

	# 🚫 Bloquear si ya hay una petición en curso
	if is_processing_request:
		rich_text_label.text = rich_text_label.text.replace("Pensando...",
			"⚠️ Esperando respuesta anterior...")
		print("⚠️ Petición bloqueada: Ya hay una en proceso")
		return

	is_processing_request = true

	# 🌐 Construir mensaje OpenAI (formato chat/completions)
	var messages = [{"role": "system", "content": system_prompt}]

	# Siempre incluir captura de pantalla para contexto visual
	if screenshot_data != "":
		print("🖼️ Agregando imagen al mensaje (", screenshot_data.length(), " chars)")
		messages.append({
			"role": "user",
			"content": [
				{"type": "text", "text": text},
				{
					"type": "image_url",
					"image_url": {
						"url": "data:image/png;base64," + screenshot_data,
						"detail": "high"
					}
				}
			]
		})
	else:
		messages.append({"role": "user", "content": text})

	var body = {
		"model": "gpt-4o-2024-08-06",
		"messages": messages,
		"max_tokens": 1000
	}

	var body_json = JSON.stringify(body)
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]

	# 📊 Enhanced logging
	print("\n============================================================")
	print("📤 ENVIANDO REQUEST A OPENAI")
	print("============================================================")
	print("🌐 URL: ", api_url)
	print("📋 Headers: ", headers)

	var has_image = body_json.find("image_url") != -1
	var has_base64 = body_json.find("data:image/png;base64,") != -1
	print("🖼️ Contiene imagen: ", "SÍ ✅" if has_image else "NO ❌")
	print("📊 Tamaño del body: ", body_json.length(), " caracteres")
	if has_base64:
		var image_start = body_json.find("data:image/png;base64,")
		print("📸 Base64 encontrado en posición: ", image_start)

	print("📦 Body (primeros 500 chars): ", body_json.substr(0, 500))
	print("============================================================")
	print("(2) ")

	send_openai_request(body_json, headers)



# Función para tomar captura de pantalla
func take_screenshot():
	# Esperar un frame para asegurar que todo esté renderizado
	await get_tree().process_frame

	# Capturar la imagen del viewport
	var img = get_viewport().get_texture().get_image()

	# Convertir a PNG
	var png_data = img.save_png_to_buffer()

	# Convertir a base64 para enviar a la API
	screenshot_data = Marshalls.raw_to_base64(png_data)

	print("📸 Captura tomada: ", screenshot_data.length(), " caracteres en base64")


# 📡 Enviar request a OpenAI
func send_openai_request(body_json: String, headers: Array):
	current_request_data = {"body": body_json, "headers": headers}
	var error = openai_request.request(api_url, headers, HTTPClient.METHOD_POST, body_json)

	if error != OK:
		print("❌ Error al enviar request: ", error)
		rich_text_label.text = rich_text_label.text.replace("Pensando...",
			"Error al enviar mensaje ❌")
		is_processing_request = false


# --- 3. FUNCIÓN MODIFICADA ---
# Esta función se llama AUTOMÁTICAMENTE cuando la API responde
func _on_request_completed(result, response_code, headers, body):
	print("\n============================================================")
	print("📥 RESPUESTA RECIBIDA DE OPENAI")
	print("============================================================")
	print("📊 Result Code: ", result)
	print("🔢 HTTP Status: ", response_code)
	print("📋 Headers: ", headers)

	var response_text = body.get_string_from_utf8()
	print("📦 Body: ", response_text)
	print("============================================================\n")

	# 🆕 MANEJO DE ERRORES
	if response_code == 429:
		rich_text_label.text += "\n[color=yellow]⚠️ Límite de API excedido. Espera unos segundos...[/color]"
		print("⚠️ Error 429: Rate limit excedido")
		is_processing_request = false
		return

	if response_code == 401:
		rich_text_label.text += "\n[color=red]❌ Error de autenticación. Verifica tu API key.[/color]"
		print("❌ Error 401: API key inválida")
		is_processing_request = false
		return

	if response_code != 200:
		rich_text_label.text = rich_text_label.text.replace("Pensando...",
			"Error: Código " + str(response_code) + " ❌")
		print("Error de API: ", response_text)
		is_processing_request = false
		return

	# Parsear respuesta JSON
	var json_data = JSON.parse_string(response_text)

	if json_data == null or not json_data.has("choices"):
		rich_text_label.text = rich_text_label.text.replace("Pensando...",
			"Error: Respuesta inválida ❌")
		print("❌ Respuesta inválida de OpenAI")
		is_processing_request = false
		return

	# Extraer respuesta del bot
	var bot_response = json_data.choices[0].message.content
	print("🧠 Respuesta cruda de OpenAI:\n", bot_response)

	# Intentar parsear JSON si la respuesta es estructurada
	var parsed = {}
	var clean_response = bot_response.strip_edges()

	# Buscar bloque JSON (puede estar en ```json o sin markdown)
	var json_substring = clean_response
	if "```json" in clean_response:
		var json_start = clean_response.find("```json") + 7
		var json_end = clean_response.find("```", json_start)
		if json_end != -1:
			json_substring = clean_response.substr(json_start, json_end - json_start).strip_edges()
	elif "```" in clean_response:
		var json_start = clean_response.find("```") + 3
		var json_end = clean_response.find("```", json_start)
		if json_end != -1:
			json_substring = clean_response.substr(json_start, json_end - json_start).strip_edges()

	# Intentar parsear como JSON
	var json_start = json_substring.find("{")
	var json_end = json_substring.rfind("}")
	if json_start != -1 and json_end != -1:
		var json_only = json_substring.substr(json_start, json_end - json_start + 1)
		var parsed_json = JSON.parse_string(json_only)
		if typeof(parsed_json) == TYPE_DICTIONARY:
			parsed = parsed_json

	# Si contiene 'action', interpretar como comando
	if parsed.has("action"):
		handleBotAction(parsed)
		rich_text_label.text = rich_text_label.text.replace("Pensando...", "")
	else:
		# Mostrar texto normal
		rich_text_label.text = rich_text_label.text.replace("Pensando...", bot_response)

	# ✅ Desbloquear para permitir nuevas peticiones
	current_request_data = null
	is_processing_request = false

	# 🔄 Devolver el foco al chat para continuar conversación
	if line_edit and not line_edit.has_focus():
		line_edit.grab_focus()

# Funciones para manejar el focus del chat
func _on_line_edit_focus_entered():
	# Desactivar controles de cámara cuando se enfoca el chat (como si presionaras CTRL)
	if camera_controller and camera_controller.has_method("disable_movement"):
		camera_controller.disable_movement()
	print("🔒 Chat enfocado - FREE CAM DESACTIVADA automáticamente")

func _on_line_edit_focus_exited():
	# Reactivar controles cuando se desenfoca el chat
	if camera_controller and camera_controller.has_method("enable_movement"):
		camera_controller.enable_movement()
	print("🔓 Chat desenfocado - FREE CAM ACTIVADA automáticamente")


func _input(event):
	# Zoom del chat con la rueda del mouse (solo cuando NO estás escribiendo)
	if event is InputEventMouseButton and not line_edit.has_focus():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Acercar el chat (aumentar escala)
			sprite.scale += Vector3(0.1, 0.1, 0.1)
			sprite.scale = sprite.scale.clamp(Vector3(0.5, 0.5, 0.5), Vector3(5.0, 5.0, 5.0))
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Alejar el chat (disminuir escala)
			sprite.scale -= Vector3(0.1, 0.1, 0.1)
			sprite.scale = sprite.scale.clamp(Vector3(0.5, 0.5, 0.5), Vector3(5.0, 5.0, 5.0))
			get_viewport().set_input_as_handled()
			return

	# Toggle chat con tecla T
	if event.is_action_pressed("ui_text_completion_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_T and not line_edit.has_focus()):
		if chat_ui and chat_ui.has_method("toggle_minimize"):
			chat_ui.toggle_minimize()
		get_viewport().set_input_as_handled()
		return

	# Manejar arrastre del chat en 3D (solo si NO está escribiendo)
	if not line_edit.has_focus():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Verificar si el click está sobre el chat (Sprite3D)
				var mouse_pos = get_viewport().get_mouse_position()

				# Si no hay colisión, verificar si está sobre el sprite visualmente
				var sprite_screen_pos = camera.unproject_position(sprite.global_transform.origin)
				var distance_to_sprite = mouse_pos.distance_to(sprite_screen_pos)

				# Si está cerca del sprite (dentro de un radio aproximado)
				if distance_to_sprite < 400:  # Radio de detección ajustable
					is_dragging_chat = true
					drag_start_pos = mouse_pos
					get_viewport().set_input_as_handled()
					return
			else:
				is_dragging_chat = false

		elif event is InputEventMouseMotion and is_dragging_chat:
			# Mover el sprite en el espacio 3D según el movimiento del mouse
			var mouse_pos = get_viewport().get_mouse_position()
			var delta_mouse = mouse_pos - drag_start_pos
			drag_start_pos = mouse_pos

			# Convertir movimiento 2D a movimiento 3D
			var cam_transform = camera.global_transform
			var right = cam_transform.basis.x
			var up = cam_transform.basis.y

			# Mover el sprite
			sprite.global_transform.origin += right * delta_mouse.x * 0.005
			sprite.global_transform.origin += -up * delta_mouse.y * 0.005

			get_viewport().set_input_as_handled()
			return
	else:
		# Si está escribiendo, detener cualquier arrastre
		is_dragging_chat = false

	if event.is_action_pressed("ui_focus_next"):
		if line_edit.has_focus():
			line_edit.release_focus()
			# 🔓 Reactivar FREE CAM cuando se desenfoca el chat
			if camera_controller and camera_controller.has_method("enable_movement"):
				camera_controller.enable_movement()
			print("Chat desenfocado - FREE CAM ACTIVADA")
		else:
			line_edit.grab_focus()
			# 🔒 Desactivar FREE CAM cuando se enfoca el chat
			if camera_controller and camera_controller.has_method("disable_movement"):
				camera_controller.disable_movement()
			print("Chat enfocado - FREE CAM DESACTIVADA")
		get_viewport().set_input_as_handled()
	elif line_edit.has_focus():
		sub_viewport_node.push_input(event)
		get_viewport().set_input_as_handled()

	# Toggle sprite solo cuando NO estás escribiendo
	if event.is_action_pressed("toggle_sprite") and not line_edit.has_focus():
		isVisible = !isVisible
		sprite.visible = isVisible
		if isVisible:
			# Calculamos posición frente a la cámara
			var cam_transform = camera.global_transform
			sprite.global_transform.origin = cam_transform.origin + cam_transform.basis.z * -2.0

# --- NUEVO: manejar acciones del bot ---
func handleBotAction(parsed: Dictionary):
	print("🎬 handleBotAction:", parsed)

	if parsed.has("action") and parsed.action == "insert":
		var assets_to_insert = []

		# Soportar asset único (string o array)
		if parsed.has("asset"):
			var asset_value = parsed.get("asset")
			if typeof(asset_value) == TYPE_STRING and asset_value != "":
				assets_to_insert.append(asset_value)
			elif typeof(asset_value) == TYPE_ARRAY:
				assets_to_insert = asset_value

		# También soportar "assets" (plural, array)
		if parsed.has("assets") and typeof(parsed.assets) == TYPE_ARRAY:
			assets_to_insert = parsed.assets

		# 🔑 Si alguno de los assets es "all", insertar todos los assets disponibles
		for asset_name in assets_to_insert:
			if typeof(asset_name) == TYPE_STRING and asset_name.to_lower() == "all":
				insertAllAssets()
				return
		# Insertar todos los assets
		if assets_to_insert.size() > 0:
			for asset_name in assets_to_insert:
				insertAsset(asset_name)
		else:
			rich_text_label.text += "\n[color=red]Error:[/color] No se indicaron assets."

	elif parsed.has("action") and parsed.action == "say":
		var msg = parsed.get("message", "ok")
		rich_text_label.text += "\n[color=orange]Bot:[/color] " + msg
	else:
		rich_text_label.text += "\n[color=red]Error:[/color] Acción desconocida."

func insertAllAssets():
	var names: Array[String] = []

	# Si el AssetManager sabe listar todos los assets, usalo
	if asset_manager and asset_manager.has_method("get_all_asset_names"):
		names = asset_manager.get_all_asset_names()
	else:
		# Fallback: usar las claves de asset_spawn_limits y validar que existan
		for k in asset_spawn_limits.keys():
			var key := String(k)
			if asset_manager.getAsset(key) != null:
				names.append(key)

	if names.is_empty():
		rich_text_label.text += "\n[color=yellow]Sistema:[/color] No hay assets disponibles para insertar."
		return

	for name in names:
		if typeof(name) == TYPE_STRING:
			insertAsset(name)

# --- NUEVO: insertar asset en el mundo ---
func insertAsset(name: String):
	print("insertAsset")
	var asset_key = name.to_lower()
	
	# 🚰 CASO ESPECIAL: Tanque de agua (ya existe en la escena, solo hacerlo visible)
	if asset_key == "tanque de agua":
		if water_tank_valve == null:
			rich_text_label.text += "\n[color=red]Error:[/color] No se encontró el nodo waterTankValve en la escena."
			print("❌ water_tank_valve es null.  Verifica que el nodo exista y la ruta sea correcta.")
			return
		
		if water_tank_valve.visible:
			rich_text_label.text += "\n[color=yellow]Sistema:[/color] El tanque de agua ya está activado."
			print("⚠️ Tanque de agua ya activado")
			return
		
		# Hacer visible el tanque
		water_tank_valve.visible = true
		rich_text_label.text += "\n[color=green]Sistema:[/color] Se activó el tanque de agua."
		print("✅ Tanque de agua activado")
		
		# Incrementar contador
		if asset_spawn_count.has(asset_key):
			asset_spawn_count[asset_key] += 1
		else:
			asset_spawn_count[asset_key] = 1
		return  # ← Salir, no instanciar nada

	#  VERIFICAR SI EL ASSET TIENE LÍMITE DE SPAWNEO
	if asset_spawn_limits.has(asset_key):
		var current_count = asset_spawn_count.get(asset_key, 0)
		var max_limit = asset_spawn_limits[asset_key]

		if current_count >= max_limit:
			# Ya se alcanzó el límite
			var msg = "No se puede crear otro/a '" + name + "'. Ya existe " + str(current_count) + " en la escena (máximo: " + str(max_limit) + ")."
			rich_text_label.text += "\n[color=red]Error:[/color] " + msg
			print(msg)
			return  # ← Salir sin crear el asset

	var scene = asset_manager.getAsset(name)
	if scene == null:
		rich_text_label.text += "\n[color=red]Error:[/color] No se encontró el asset '" + name + "'."
		return

	var instance = scene.instantiate()
	instance.name = name + "_" + str(Time.get_ticks_msec())

	#  VERIFICAR SI EL ASSET TIENE POSICIÓN FIJA
	if fixed_positions.has(asset_key):
		# Usar posición y rotación fijas
		var fixed_data = fixed_positions[asset_key]
		instance.global_transform.origin = fixed_data.position

		# Aplicar rotación (convertir de grados a radianes)
		instance.rotation_degrees = fixed_data.rotation

		print("Asset '", name, "' colocado en posición fija: ", fixed_data.position)
		rich_text_label.text += "\n[color=green]Sistema:[/color] Se insertó " + name + " en posición fija."
	else:
		# Posición dinámica
		instance.scale = Vector3(2, 2, 2)

		# --- Posición frente a cámara ---
		var cam_transform = camera.global_transform
		var forward = -cam_transform.basis.z.normalized()
		var start_pos = cam_transform.origin + forward * 3.0 + Vector3(0, 2.0, 0)

		# --- Buscar el piso con raycast ---
		var space = get_world_3d().direct_space_state
		var ray_params = PhysicsRayQueryParameters3D.create(start_pos, start_pos + Vector3(0, -20, 0))
		var ray_result = space.intersect_ray(ray_params)

		if ray_result.size() > 0:
			var ground_pos = ray_result.position
			var free_pos = findFreeSpot(ground_pos, 1.5)  # ← ahora es por distancia
			instance.global_transform.origin = free_pos
		else:
			instance.global_transform.origin = start_pos + Vector3(0, -1.0, 0)

	# --- Iniciar animación automáticamente  de los assets ---
	var anim_player = findAnimationPlayerInNode(instance)
	if anim_player:
		# Opción 1: Reproducir animación específica
		if anim_player.has_animation("Fresadora_TodoJunto"):
			anim_player.play("Fresadora_TodoJunto")
			print("Animación 'Fresadora_TodoJunto' iniciada")
		# Opción 2: Reproducir la primera animación disponible
		elif anim_player.get_animation_list().size() > 0:
			var first_anim = anim_player.get_animation_list()[0]
			anim_player.play(first_anim)
			print("Animación '", first_anim, "' iniciada")
	
	get_tree().current_scene.add_child(instance)
	spawned_assets.append(instance)
	rich_text_label.text += "\n[color=green]Sistema:[/color] Se insertó " + name + " en " + str(instance.global_transform.origin)

	# INCREMENTAR EL CONTADOR DE ASSET GENERADO
	if asset_spawn_count.has(asset_key):
		asset_spawn_count[asset_key] += 1
	else:
		asset_spawn_count[asset_key] = 1

# --- para animacion de los elementos ---
func findAnimationPlayerInNode(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var result = findAnimationPlayerInNode(child)
		if result:
			return result

	return null

## --- NUEVO: heurística simple para encontrar espacio libre ---
#func findFreePosition() -> Vector3:
	#var space = get_world_3d().direct_space_state
	#for i in range(20):
		#var pos = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		#var box_size = Vector3(0.5, 0.5, 0.5)
		#var result = space.intersect_box(Transform3D(Basis(), pos), box_size, [], 1)
		#if result.size() == 0:
			#return pos
	#return Vector3(0, 0, 0)

func findFreeSpot(base_pos: Vector3, min_distance: float = 1.5, max_attempts: int = 40) -> Vector3:
	# Distribución en anillos: intenta posiciones alrededor del punto base,
	# aumentando radio si no encuentra hueco. Sin física, solo distancia.
	var ring_step := 0.6
	var angle_step := 18.0 # grados
	var radius := 0.0

	for attempt in range(max_attempts):
		if attempt % int(360.0 / angle_step) == 0:
			radius += ring_step

		var angle_deg = float(attempt % int(360.0 / angle_step)) * angle_step
		var angle = deg_to_rad(angle_deg)
		var offset = Vector3(cos(angle), 0, sin(angle)) * radius
		var test_pos = base_pos + offset

		var libre := true
		for n in spawned_assets:
			if n and n.is_inside_tree():
				if test_pos.distance_to(n.global_transform.origin) < min_distance:
					libre = false
					break
		if libre:
			return test_pos

	# Si no encontró nada “perfecto”, usa el base_pos
	return base_pos
