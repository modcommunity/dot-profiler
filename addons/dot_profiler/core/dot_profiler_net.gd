class_name DotProfilerNet
extends RefCounted

## Reads the network rate for the merged graph without draining anything: it only diffs the byte totals of a
## metered peer (dot-net's DotMeteredPeer: bytes_in, bytes_out), by duck typing, so a game without one reads 0.

var _last_in := -1
var _last_out := -1
var _in_kb := 0.0
var _out_kb := 0.0


## Smoothed KB/s [in, out] after a frame of [param frame_ms] on [param tree]'s multiplayer peer.
func sample(tree: SceneTree, frame_ms: float) -> PackedFloat32Array:
	var peer: Object = tree.get_multiplayer().multiplayer_peer if tree != null and tree.get_multiplayer() != null else null
	if peer == null or not ("bytes_in" in peer) or not ("bytes_out" in peer):
		_last_in = -1
		return PackedFloat32Array([0.0, 0.0])
	var bin: int = peer.get(&"bytes_in")
	var bout: int = peer.get(&"bytes_out")
	if _last_in >= 0 and frame_ms > 0.0:
		var s := 1000.0 / frame_ms / 1024.0
		_in_kb = lerpf(_in_kb, maxi(bin - _last_in, 0) * s, 0.15)
		_out_kb = lerpf(_out_kb, maxi(bout - _last_out, 0) * s, 0.15)
	_last_in = bin
	_last_out = bout
	return PackedFloat32Array([_in_kb, _out_kb])
