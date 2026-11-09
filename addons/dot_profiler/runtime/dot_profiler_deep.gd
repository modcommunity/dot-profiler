class_name DotProfilerDeep
extends RefCounted

## Native samples next to a recording: Linux perf attached to this process for the recording's length,
## written as perf.data beside the report. Says why when it cannot run (no perf, kernel paranoia, not Linux).
## The engine's own frames only have names in a build with symbols; docs/deep-mode.md has the details.

const CHANNEL := "dot.profiler"
## Samples per second; an odd rate keeps clear of the frame rate.
const HZ := 999


## Starts perf on this process for [param seconds], writing [param out_path] (an OS path).
## The value is {pid, file, command}; perf stops by itself, so nothing has to stop it.
static func start(seconds: float, out_path: String) -> DotResult:
	var why := unavailable()
	if why != "":
		return DotResult.fail(DotError.CODE_UNSUPPORTED, why)
	var args := PackedStringArray(["record", "-g", "-F", str(HZ), "-p", str(OS.get_process_id()), "-o", out_path,
		"--", "sleep", str(maxi(ceili(seconds), 1))])
	var pid := OS.create_process("perf", args)
	if pid <= 0:
		return DotResult.fail(DotError.CODE_IO, "perf did not start (perf %s)." % " ".join(args))
	DotLog.info(CHANNEL, "deep mode: perf sampling pid %d for %.0f s into %s" % [OS.get_process_id(), seconds, out_path])
	return DotResult.success({"pid": pid, "file": out_path, "command": "perf " + " ".join(args)})


## Why perf cannot sample this process here, or "" when it can.
static func unavailable() -> String:
	if OS.get_name() != "Linux":
		return "deep mode needs Linux perf; this is %s." % OS.get_name()
	var out: Array = []
	var rc := OS.execute("sh", ["-c", "command -v perf"], out)
	if rc != 0 or out.is_empty() or String(out[0]).strip_edges() == "":
		return "perf is not installed (apt install linux-perf)."
	var f := FileAccess.open("/proc/sys/kernel/perf_event_paranoid", FileAccess.READ)
	if f != null:
		var level := f.get_as_text().strip_edges().to_int()
		if level > 2:
			return "kernel.perf_event_paranoid is %d; perf needs 2 or less (sysctl kernel.perf_event_paranoid=1)." % level
	return ""
