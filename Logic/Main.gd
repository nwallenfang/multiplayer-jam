extends Spatial

onready var game = $Level
onready var ui_layer: UILayer = $UILayer
onready var ready_screen = $UILayer/Screens/ReadyScreen

var players := {}

var players_ready := {}
var players_score := {}

func _ready() -> void:
	var args = OS.get_cmdline_args()
	if len(args) >= 1:
		if args[0] == 'debug':
			Game.debug = true

	OnlineMatch.connect("error", self, "_on_OnlineMatch_error")
	OnlineMatch.connect("disconnected", self, "_on_OnlineMatch_disconnected")
	OnlineMatch.connect("player_status_changed", self, "_on_OnlineMatch_player_status_changed")
	OnlineMatch.connect("player_left", self, "_on_OnlineMatch_player_left")

#func _unhandled_input(event: InputEvent) -> void:
#	# Trigger debugging action!
#	if event.is_action_pressed("player_debug"):
#		# Close all our peers to force a reconnect (to make sure it works).
#		for session_id in OnlineMatch.webrtc_peers:
#			var webrtc_peer = OnlineMatch._webrtc_peers[session_id]
#			webrtc_peer.close()

####### UNSERES
# OnlineMatch.get_session_id(player_id)
# set_network_master(peer_id)
# OnlineMatchPlayer.start_playing()
# Extremely naive position and animation sync'ing.
#
# This will work locally, and under ideal network conditions, but likely won't 
# be acceptable over the live internet for a large percentage of users.
#
# You'll need to replace this with more efficient sync'ing mechanism, which
# could include input prediction, rollback, limiting how often sync'ing happens
# or any other number of techniques.
#
# In addition to that, you'll also need to expand the number of things that are
# sync'd, depending on the needs of your game.
#puppet func update_remote_player(_position: Vector2, is_attacking: bool) -> void:
#	global_position = _position
#
#	if is_attacking and not animation_player.is_playing():
#		animation_player.play("Attack")


#####
# UI callbacks
#####

func _on_TitleScreen_play_local() -> void:
	Game.online_play = false
	
	ui_layer.hide_screen()
	ui_layer.show_back_button()
	
	start_game()

func _on_TitleScreen_play_online() -> void:
	Game.online_play = true
	
	ui_layer.show_screen("ConnectionScreen")

func _on_UILayer_change_screen(name: String, _screen) -> void:
	if name == 'TitleScreen':
		ui_layer.hide_back_button()
	else:
		ui_layer.show_back_button()

func _on_UILayer_back_button() -> void:
	ui_layer.hide_message()
	
	stop_game()
	
	if ui_layer.current_screen_name in ['ConnectionScreen', 'MatchScreen']:
		ui_layer.show_screen("TitleScreen")
	elif not Game.online_play:
		ui_layer.show_screen("TitleScreen")
	else:
		ui_layer.show_screen("MatchScreen")

func _on_ReadyScreen_ready_pressed() -> void:
	print("pressed")
	rpc("player_ready", OnlineMatch.get_my_session_id())

#####
# OnlineMatch callbacks
#####

func _on_OnlineMatch_error(message: String):
	if message != '':
		ui_layer.show_message(message)
	ui_layer.show_screen("MatchScreen")

func _on_OnlineMatch_disconnected():
	#_on_OnlineMatch_error("Disconnected from host")
	_on_OnlineMatch_error('')

func _on_OnlineMatch_player_left(player) -> void:
	ui_layer.show_message(player.username + " has left")
	
	game.kill_player(player.peer_id)
	
	players.erase(player.peer_id)
	players_ready.erase(player.peer_id)

func _on_OnlineMatch_player_status_changed(player, status) -> void:
	if status == OnlineMatch.PlayerStatus.CONNECTED:
		if get_tree().is_network_server():
			# Tell this new player about all the other players that are already ready.
			for session_id in players_ready:
				rpc_id(player.peer_id, "player_ready", session_id)

#####
# Gameplay methods and callbacks
#####

remotesync func player_ready(session_id: String) -> void:
	ready_screen.set_status(session_id, "READY!")
	
	if get_tree().is_network_server() and not players_ready.has(session_id):
		players_ready[session_id] = true
		if players_ready.size() == OnlineMatch.players.size():
			if OnlineMatch.match_state != OnlineMatch.MatchState.PLAYING:
				OnlineMatch.start_playing()
			start_game()

func start_game() -> void:
	if Game.online_play:
		players = OnlineMatch.get_player_names_by_peer_id()
#	else:
#		players = {
#			1: "Player1",
#			2: "Player2",
#		}
	game.game_start(players)

func stop_game() -> void:
	OnlineMatch.leave()
	
	players.clear()
	players_ready.clear()
	players_score.clear()
	
	game.game_stop()

func restart_game() -> void:
	stop_game()
	start_game()

func _on_Game_game_started() -> void:
	ui_layer.hide_screen()
	ui_layer.hide_all()
	ui_layer.show_back_button()
	Game.game_started = true

func _on_Game_player_dead(player_id: int) -> void:
	if Game.online_play:
		var my_id = get_tree().get_network_unique_id()
		if player_id == my_id:
			ui_layer.show_message("You lose!")

func _on_Game_game_over(player_id: int) -> void:
	players_ready.clear()
	
	if not Game.online_play:
		show_winner(players[player_id])
	elif get_tree().is_network_server():
		if not players_score.has(player_id):
			players_score[player_id] = 1
		else:
			players_score[player_id] += 1
		
		var player_session_id = OnlineMatch.get_session_id(player_id)
		var is_match: bool = players_score[player_id] >= 5
		rpc("show_winner", players[player_id], player_session_id, players_score[player_id], is_match)

remotesync func show_winner(name: String, session_id: String = '', score: int = 0, is_match: bool = false) -> void:
	if is_match:
		ui_layer.show_message(name + " WINS THE WHOLE MATCH!")
	else:
		ui_layer.show_message(name + " wins this round!")
	
	yield(get_tree().create_timer(2.0), "timeout")
	if not game.game_started:
		return
	
	if Game.online_play:
		if is_match:
			stop_game()
			ui_layer.show_screen("MatchScreen")
		else:
			ready_screen.hide_match_id()
			ready_screen.reset_status("Waiting...")
			ready_screen.set_score(session_id, score)
			ui_layer.show_screen("ReadyScreen")
	else:
		restart_game()



func _on_OnlineLobby_game_over(player_id) -> void:
	pass # Replace with function body.


func _on_OnlineLobby_game_started() -> void:
	pass # Replace with function body.


func _on_OnlineLobby_player_dead(player_id) -> void:
	pass # Replace with function body.


func _on_Level_game_started():
	pass # Replace with function body.
