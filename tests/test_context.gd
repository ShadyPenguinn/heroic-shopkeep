class_name TestContext
extends RefCounted
## Collects assertion failures for one test method.

var failures: PackedStringArray = []


func ok(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		failures.append(msg)


func eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		failures.append("%s expected %s, got %s" % [msg, str(b), str(a)])


func empty(list: Variant, msg: String = "") -> void:
	if list.size() != 0:
		failures.append("%s expected empty, got %s" % [msg, str(list)])
