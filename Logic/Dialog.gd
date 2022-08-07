extends Node

func _ready():
	create_all_dialogs()

enum SPEAKERS {DRILL, ROLLER, MERCHANT, FISH, HOOK}

var names = {
	SPEAKERS.DRILL: "Robot",
	SPEAKERS.ROLLER: "Human",
	SPEAKERS.MERCHANT: "Merchant",
	SPEAKERS.FISH: "Fish",
	SPEAKERS.HOOK: "Hook",
}

var colors = {
	SPEAKERS.DRILL: Color.steelblue,
	SPEAKERS.ROLLER: Color.orange,
	SPEAKERS.MERCHANT: Color.coral,
	SPEAKERS.FISH: Color.white,
	SPEAKERS.HOOK: Color.gray,
}

var icons = {
	SPEAKERS.DRILL: preload("res://Assets/Sprites/characters/drill_transparent.png"),
	SPEAKERS.ROLLER: preload("res://Assets/Sprites/characters/roller_transparent.png"),
	SPEAKERS.MERCHANT: preload("res://Assets/Sprites/characters/human_PLACEHOLDER.png"),
	SPEAKERS.FISH: preload("res://Assets/Sprites/characters/human_PLACEHOLDER.png"),
	SPEAKERS.HOOK: preload("res://Assets/Sprites/characters/hook.png"),
}

class DialogLine:
	var speaker_id: int
	var text: String
	var duration: float
	
	func _init(sid, t, d := 3.0):
		speaker_id = sid
		text = t
		duration = d * 1.15
	
	func to_dict() -> Dictionary:
		return {
			"speaker_id": speaker_id, "text": text, "duration": duration
		}

class DialogSequence:
	var lines := []
	var played := false
	
	func _init(l):
		lines = l
		
	func to_basic_data() -> Array:  # array of dictionaries for rpc calls
		var ret = []
		for line in lines:
			ret.append(line.to_dict())
		return ret

enum SELECTION_MODES {ORDER, RANDOM}
enum TRIGGER_MODES {
	ONCE,
	COUNT_EXACT,
	COUNT_GREATER_EQ,  
	VALUE_EXACT,
	VALUE_GREATER_EQ,
	CHANCE
}

class DialogTrigger:
	var trigger_key: String
	var selection_mode : int = SELECTION_MODES.ORDER
	var trigger_mode : int = TRIGGER_MODES.ONCE
	var condition_value
	var importance: int = 1
	var queue := false
	var always := false
	var trigger_count := 0
	var max_triggers := 0
	var can_trigger := true
	var sequences := []
	
	func _init(t):
		trigger_key = t
	
	func is_all_played():
		for s in sequences:
			if not s.played:
				return false
		return true

var currently_dialoging := false
var current_dialog_trigger : DialogTrigger
var current_dialog_sequence : DialogSequence
var trigger_counts := {}

var all_dialogs := []
var dialog_queue := []

class ImportanceSorter:
	static func sort(a, b):
		if a.importance > b.importance:
			return true
		return false


func trigger(trigger_key: String, value = null):
	if trigger_key in trigger_counts:
		trigger_counts[trigger_key] = trigger_counts[trigger_key] + 1
	else:
		trigger_counts[trigger_key] = 1
	
	var found_dialogs := []
	for dialog_trigger in all_dialogs:
		dialog_trigger = dialog_trigger as DialogTrigger
#		dialog_trigger.index = index
		if dialog_trigger.trigger_key == trigger_key and dialog_trigger.can_trigger:
			match(dialog_trigger.trigger_mode):
				TRIGGER_MODES.ONCE:
					found_dialogs.append(dialog_trigger)
				TRIGGER_MODES.COUNT_EXACT:
					if trigger_counts[trigger_key] == dialog_trigger.condition_value:
						found_dialogs.append(dialog_trigger)
				TRIGGER_MODES.COUNT_GREATER_EQ:
					if trigger_counts[trigger_key] >= dialog_trigger.condition_value:
						found_dialogs.append(dialog_trigger)
				TRIGGER_MODES.VALUE_EXACT:
					if value != null:
						if value == dialog_trigger.condition_value:
							found_dialogs.append(dialog_trigger)
				TRIGGER_MODES.VALUE_GREATER_EQ:
					if value != null:
						if value >= dialog_trigger.condition_value:
							found_dialogs.append(dialog_trigger)
				TRIGGER_MODES.CHANCE:
					if randf() <= dialog_trigger.condition_value:
						found_dialogs.append(dialog_trigger)
	
	if not found_dialogs.empty():
		found_dialogs.sort_custom(ImportanceSorter, "sort")
		var best_match := current_dialog_trigger
		var best_match_index := 0
		for dialog_trigger in found_dialogs:
			if best_match == null:
				best_match = dialog_trigger
			elif dialog_trigger.importance > best_match.importance:
				best_match = dialog_trigger
			elif dialog_trigger.queue:
				for i in range(len(dialog_queue)):
					if dialog_queue[i].importance < dialog_trigger.importance:
						dialog_queue.insert(i, dialog_trigger)
					elif i == len(dialog_queue) - 1:
						dialog_queue.append(dialog_trigger)
		
		if best_match != current_dialog_trigger:
			execute_dialog(best_match)
	else:
		Game.log("unknown dialog trigger: " + trigger_key)

signal dialog_started

func execute_dialog(dialog_trigger: DialogTrigger):
	var seq = null
	if dialog_trigger.selection_mode == SELECTION_MODES.ORDER:
		if dialog_trigger.always:
			seq = dialog_trigger.sequences[dialog_trigger.trigger_count % len(dialog_trigger.sequences)]
		else:
			for s in dialog_trigger.sequences:
				s = s as DialogSequence
				if not s.played:
					seq = s
					break
	elif dialog_trigger.selection_mode == SELECTION_MODES.RANDOM:
		for i in range(50):
			dialog_trigger.sequences.shuffle()
			var s = dialog_trigger.sequences[0] as DialogTrigger
			if (not s.played) or dialog_trigger.always:
				seq = s
				break
	if seq != null:
		currently_dialoging = true
		current_dialog_trigger = dialog_trigger
		current_dialog_sequence = seq
		current_dialog_sequence.played = true
		dialog_trigger.trigger_count += 1
		if dialog_trigger.max_triggers != 0:
			if dialog_trigger.trigger_count >= dialog_trigger.max_triggers:
				dialog_trigger.can_trigger = false
		if not dialog_trigger.always and dialog_trigger.is_all_played():
			dialog_trigger.can_trigger = false
		emit_signal("dialog_started")

var queue_cooldown_time := 4.0
signal dialog_ended
func on_dialog_ended():
	emit_signal("dialog_ended")
	currently_dialoging = false
	current_dialog_trigger = null
	yield(get_tree().create_timer(queue_cooldown_time),"timeout")
	if not currently_dialoging:
		if not dialog_queue.empty():
			execute_dialog(dialog_queue.pop_front())
			
			
func add_dialog():
	# TODO connect to signal automatically
	pass

func create_all_dialogs():
	var d
	
	
	d = DialogTrigger.new("power_low")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "We'll go home once the our power is out.."),
		DialogLine.new(SPEAKERS.DRILL, "So soon.. but at least going home means shopping time!"),
		DialogLine.new(SPEAKERS.ROLLER, "Right! Let's find some treasures then."),
	]))
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.DRILL, "The power levels are halfway down again..."),
		DialogLine.new(SPEAKERS.ROLLER, "It always happens so fast"),
	]))
	all_dialogs.append(d)

	d = DialogTrigger.new("treasure_drill")
	d.trigger_mode = TRIGGER_MODES.COUNT_EXACT
	d.condition_value = 4
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "Can't you hurry up with your drilling? You're taking your time."),
		DialogLine.new(SPEAKERS.DRILL, "Hey, these treasures have to be drilled with utmost care!"),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("getting_hit")
	d.trigger_mode = TRIGGER_MODES.COUNT_GREATER_EQ
	d.condition_value = 4
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "Those eels always steal our power."),
		DialogLine.new(SPEAKERS.DRILL, "I hope your battery doesn't get damaged."),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("treasure_found")
	d.trigger_mode = TRIGGER_MODES.COUNT_EXACT
	d.condition_value = 5
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.DRILL, "This is our fifth treasure finding!"),
		DialogLine.new(SPEAKERS.DRILL, "Yeee!"),
	]))
	all_dialogs.append(d)
	
#	d = DialogTrigger.new("gold_earned")
#	d.trigger_mode = TRIGGER_MODES.VALUE_GREATER_EQ
#	d.condition_value = 100
#	d.sequences.append(DialogSequence.new([
#		DialogLine.new(SPEAKERS.ROLLER, "Amazing, now we can afford the Bomb!"),
#		DialogLine.new(SPEAKERS.DRILL, "I would love to use it."),
#	]))
#	all_dialogs.append(d)
	
	
#	d = DialogTrigger.new("see_a_fish")
#	d.trigger_mode = TRIGGER_MODES.CHANCE
#	d.condition_value = .5
#	d.selection_mode = SELECTION_MODES.RANDOM
#	d.sequences.append(DialogSequence.new([
#		DialogLine.new(SPEAKERS.ROLLER, "There is a fish!"),
#	]))
#	d.sequences.append(DialogSequence.new([
#		DialogLine.new(SPEAKERS.DRILL, "Another fish over there."),
#	]))
#	d.sequences.append(DialogSequence.new([
#		DialogLine.new(SPEAKERS.ROLLER, "I like fishes."),
#	]))
#	all_dialogs.append(d)

	d = DialogTrigger.new("eel_middle")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "This eel looks really icky..", 2.0),
		DialogLine.new(SPEAKERS.DRILL, "It wants to drain our power levels!"),
		DialogLine.new(SPEAKERS.ROLLER, "I'd like to shoot it.", 2.0),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("close_to_eel")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "These eels look really icky..", 2.0),
		DialogLine.new(SPEAKERS.DRILL, "I've seen them before. They drain our power levels!"),
		DialogLine.new(SPEAKERS.ROLLER, "Sounds scary.", 1.5),
	]))
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.DRILL, "There has to be a way to fend the eels off!"),
		DialogLine.new(SPEAKERS.ROLLER, "You know that's what I'm built for, right?"),
		DialogLine.new(SPEAKERS.ROLLER, "I just need crystals to power my gun."),
		DialogLine.new(SPEAKERS.DRILL, "Those shiny purple ones, right.."),
	]))
	all_dialogs.append(d)

	d = DialogTrigger.new("drill_too_weak")
	d.queue = true
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.DRILL, "Damn!", 1.2),
		DialogLine.new(SPEAKERS.DRILL, "My Drill power is too low.", 2.4),
		DialogLine.new(SPEAKERS.ROLLER, "You're really useless without your upgrades.", 2.4),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("see_wall")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.DRILL, "DRILL! DRILL! DRILL!", 1.2),
		DialogLine.new(SPEAKERS.DRILL, "Drive next to that wall!", 2.4),
		DialogLine.new(SPEAKERS.DRILL, "I will drill it to dust.", 2.4),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("other_side")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.DRILL, "I see that shiny diamond.", 2.4),
		DialogLine.new(SPEAKERS.DRILL, "Get me over there!", 2.2),
		DialogLine.new(SPEAKERS.DRILL, "I can't.", 1.4),
		DialogLine.new(SPEAKERS.DRILL, "We'd both sink to the ground.", 1.4),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("wall_destroyed")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.DRILL, "Yes!", 1.4),
		DialogLine.new(SPEAKERS.DRILL, "I told you, I would drill that wall."),
		DialogLine.new(SPEAKERS.DRILL, "All hail the drill!", 2.2),
		DialogLine.new(SPEAKERS.DRILL, "-.-", 1.4),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("anemone_drill")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "?", 1.4),
		DialogLine.new(SPEAKERS.ROLLER, "Why are you drilling that sea anemone?", 3.0),
		DialogLine.new(SPEAKERS.DRILL, "I'm a drill", 1.9),
		DialogLine.new(SPEAKERS.DRILL, "That's what I do...", 2.4),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("anemone_drill")
	d.trigger_mode = TRIGGER_MODES.COUNT_GREATER_EQ
	d.condition_value = 4
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "Could you stop drilling those useless anemones?"),
		DialogLine.new(SPEAKERS.DRILL, "I could but I won't."),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("hook")
	d.trigger_mode = TRIGGER_MODES.COUNT_GREATER_EQ
	d.condition_value = 3
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "Oh all mighty hook, get out of here!"),
		DialogLine.new(SPEAKERS.HOOK, "I got you.", 2.0),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("intro_sequence")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "Finally, the first treasure hunt on our own!", 2.5),
		DialogLine.new(SPEAKERS.DRILL, "So exciting, which treasure will I drill first?", 3.0),
		DialogLine.new(SPEAKERS.ROLLER, "The ocean feels so different from the academy pool..", 3.0),
		DialogLine.new(SPEAKERS.DRILL, "This is what we've been training for!", 2.3),
		DialogLine.new(SPEAKERS.DRILL, "Scrap metal, crystals, explosions, crazy heists..", 2.5),
		DialogLine.new(SPEAKERS.ROLLER, "Well... let's touch some seaweed first.", 2.5),
	]))
	all_dialogs.append(d)
	
	d = DialogTrigger.new("intro_sequence")
	d.trigger_mode = TRIGGER_MODES.COUNT_GREATER_EQ
	d.condition_value = 5
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "Did you know, we're sold labled as T.R.U.S.D. unit?", 2.8),
		DialogLine.new(SPEAKERS.DRILL, "I did not, what does it mean?", 2.0),
		DialogLine.new(SPEAKERS.ROLLER, "Treasure Receiving Unit: Scavenge & Drill", 3.0),
	]))
	all_dialogs.append(d)

	d = DialogTrigger.new("diamond_drilled")
	d.sequences.append(DialogSequence.new([
		DialogLine.new(SPEAKERS.ROLLER, "We finally got that shiny diamond!"),
		DialogLine.new(SPEAKERS.ROLLER, "That will get us a special reward. I'm sure."),
		DialogLine.new(SPEAKERS.ROLLER, "At least I hope...", 2.0),
		DialogLine.new(SPEAKERS.ROLLER, "Would be nice.", 1.5),
	]))
	all_dialogs.append(d)
