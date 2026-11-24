class_name CharacterSprites
extends RefCounted
## Builds SpriteFrames from the Zerie Tiny RPG Character pack at runtime.
##
## Expected layout (copy from the pack, flattening its nested folders):
##   assets/characters/<Sprite>/<Sprite>-Idle.png
##   assets/characters/<Sprite>/<Sprite>-Attack01.png   ... etc.
## where <Sprite> is the "sprite" value in classes.json / monsters.json.
## Each sheet is one row of 100x100 frames. Missing sprites return null and the
## playback actor draws a placeholder instead, so code never waits on art.

const ROOT := "res://assets/characters/"
const CELL := Vector2i(100, 100)
# animation name in game -> file suffix in the pack, in order of preference
const ANIMS := {
	"idle": ["Idle"],
	"walk": ["Walk"],
	"attack": ["Attack01", "Attack"],
	"attack2": ["Attack02", "Attack01"],
	"hurt": ["Hurt"],
	"block": ["Block", "Hurt"],
	"death": ["Death"],
}
const FPS := {"idle": 8.0, "walk": 10.0, "attack": 14.0, "attack2": 14.0, "hurt": 12.0, "block": 12.0, "death": 10.0}
const LOOPS := ["idle", "walk"]

static var _cache: Dictionary = {}


static func frames_for(sprite_key: String) -> SpriteFrames:
	if _cache.has(sprite_key):
		return _cache[sprite_key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var found := false
	for anim in ANIMS:
		for suffix in ANIMS[anim]:
			var path := "%s%s/%s-%s.png" % [ROOT, sprite_key, sprite_key, suffix]
			if not ResourceLoader.exists(path):
				continue
			var tex: Texture2D = load(path)
			frames.add_animation(anim)
			frames.set_animation_speed(anim, FPS[anim])
			frames.set_animation_loop(anim, LOOPS.has(anim))
			var count := maxi(1, tex.get_width() / CELL.x)
			for i in count:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * CELL.x, 0, CELL.x, CELL.y)
				frames.add_frame(anim, at)
			found = true
			break
	_cache[sprite_key] = frames if found else null
	return _cache[sprite_key]
