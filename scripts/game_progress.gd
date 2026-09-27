extends Node

## Global game progress tracker (autoload singleton "GameProgress").
## Tracks the forest challenges the player must clear before the volcano's
## cave entrance opens, and remembers which scene/spawn point to use when
## loading Cave Interior and Volcano Summit.

signal challenge_completed(count: int, total: int)
signal cave_unlocked

const TOTAL_CHALLENGES := 3

var challenges_completed: int = 0
var cave_is_unlocked: bool = false
var oasis_found: bool = false


func complete_challenge() -> void:
	if cave_is_unlocked:
		return
	challenges_completed += 1
	challenge_completed.emit(challenges_completed, TOTAL_CHALLENGES)
	if challenges_completed >= TOTAL_CHALLENGES:
		cave_is_unlocked = true
		cave_unlocked.emit()


func reset() -> void:
	challenges_completed = 0
	cave_is_unlocked = false
	oasis_found = false
