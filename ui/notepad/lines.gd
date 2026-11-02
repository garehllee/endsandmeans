class_name Lines

const DATA := {
	# Movement (logged as "action")
	"walk_left":  ["Walked to the left", "Headed left", "Shuffled off to the left"],
	"walk_right": ["Walked to the right", "Headed right", "Wandered off to the right"],
	"walk_up":    ["Walked up", "Headed north", "Moved up"],
	"walk_down":  ["Walked down", "Headed south", "Moved down"],

	# Interactions (logged as "thought")
	"document_near": [
		"There's an {item} here. Maybe i should inspect it with 'e'.",
		"This {item} looks interesting. Maybe i should inspect closer with 'e'.",
		"Huh. An {item}. Should i take a closer look with 'e'?",
	],
	"document_inspect": [
		"Okay, let's see what this {item} says...",
		"I'll take a closer look at the {item}.",
	],

	# Idle nudges
	"idle": [
		"...Am i supposed to do something?",
		"It's quiet. maybe i should look around.",
	],
	
	# Window
	"window_hover": [
		"There's something on the opposite side of this wall."],
	
	# File Management
	"folder_open": ["let's see what's inside {item}.", "opening {item}."],
	"folder_leave": ["back out we go.", "okay. back where i started.", "that's enough of that folder."],
		"file_near": [
	"{item}. maybe i should open it.",
	"there's a file here. {item}.",
	"huh. {item}. what's in it?",
	],
	"image_near": [
	"{item}... it looks like a picture.",
	"this is an image. {item}. maybe i should look closer.",
	"{item}. i think i recognize this.",
	],
	"folder_near": [
	"a folder. {item}. can i walk into it?",
	"{item}... what's in there?",
	],
	
	#door
	"door_near": ["a door. it feels important.", "that door again."],
	"door_inspect": ["okay. here goes nothing.", "let's see what's behind it."],
	"library_arrive": ["so many files...", "where... is this?"],
	
	#exit
	"exit_near": ["the way back.", "i could head out from here."],
	"exit_inspect": ["okay. back out.", "that's enough files for now."],
	
	#analysis
	"analysis_open": ["...is that another AI?", "someone left a message in here."],
	"analysis_write_near": ["write the folder. that feels right.", "i could ask for the orange folder."],
	"analysis_later_near": ["not right now. that's an option too.", "maybe i should wait."],
	"analysis_later": ["okay. later, then.", "i'll come back to this."],
	"analysis_start": ["firewalls. don't touch the firewalls.", "grab a folder. avoid the walls."],
	"firewall_hit": ["ow. firewall. again.", "that wall hurts."],
	"folder_caught": ["got one!", "folder secured."],
	"orange_added": ["a new folder appeared at the end of the repository.", "ZZ_Confirm_Anyone_See_Orange_Folder. it's there now."],

}
