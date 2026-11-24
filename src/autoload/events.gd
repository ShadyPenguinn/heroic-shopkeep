extends Node
## Global signal bus for things many unrelated nodes care about. Prefer direct
## signals between parent and child; use this only when the sender should not
## know who listens (achievements, audio stingers, tutorial hints).

signal achievement_unlocked(id: String)
signal overlay_toggled(active: bool)
signal settings_changed

# Season flow (emitted by the Game autoload)
signal state_loaded
signal day_started(day: int)
signal gear_lent(hero_uid: String)
signal gear_bought(gear: Dictionary)
signal delves_sent(results: Array)
signal dusk_report(report: Array)
signal card_taken(hero_uid: String, card: Dictionary)
signal title_earned(gear_uid: String, title: String)
signal rent_collected(amount: int, paid: bool)
signal day_ended(day: int)
signal season_over(won: bool)
