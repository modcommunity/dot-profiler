# The profiler on a dedicated server

A headless server has no menu and no overlay, so its profiler is driven from dot-server's console: the server's stdin, `server.cfg`, or RCON.

```gdscript
var prof := DotProfiler.new()
prof.config = DotProfilerConfig.new()
add_child(prof)
var res := DotProfilerServer.new().install(prof)   # finds dot_console, dot_server, dot_query_source in DotRegistry
```

`install` parents the controls under the profiler, so freeing the profiler takes the commands, cvars and query provider away again. Pass the console, server and query source explicitly when they are not registered. It fails with `CODE_UNSUPPORTED` when no dot-server console is found.

## Commands

All are registered through `DotConsole.add_source` with the `config` admin flag, the same gate as other `sv_` settings, so they work from the console and over RCON for an admin with that flag and are refused for everyone else. None is a chat command.

| Command | Answers |
| --- | --- |
| `sv_profiler_record [seconds]` | Starts a recording (default `profiler_record_seconds`); it stops itself when the time is up. |
| `sv_profiler_stop` | Stops it and writes `profile-<stamp>.json` and `.txt`, the same format as a client's. Replies with the absolute path. |
| `sv_profiler_status` | Watching, recording, elapsed, spikes, smoothed frame ms, the repeating beat, the directory and the last saved report. |
| `sv_profiler_frame` | FPS, frame, process and physics ms from the engine monitors, and the smoothed physics, script, render and wait phases. |
| `sv_profiler_hitches` | Spikes per cause, worst first, with the beat each repeats on. Empty until `profiler_enabled 1` or a recording. |
| `sv_profiler_systems [n]` | The n costliest systems reported through `DotFrameCost`. |
| `sv_profiler_memory` | Static memory, object, node, orphan and resource counts. |
| `sv_profiler_net` | Bytes in and out, rates since the last call, players and bots. |
| `sv_profiler_metrics` | Everything above as one JSON line, for a tool reading over RCON. |

Network bytes come from a `DotMeteredPeer` when the peer is one, otherwise from the ENet host's statistics, which this drains and sums; the plain ENet server peer has no other reader. `metered: false` means neither could be read (a WebSocket peer).

## Cvars

Every `profiler_*` setting in [design.md](design.md#configuration) is also a server cvar, so `server.cfg` can set them. The two that matter most on a server:

- `profiler_record_dir`: left at the default, it becomes `<log_directory>/profiles` (dot-server's `log_directory`, `user://logs` unless configured), so recordings sit beside the logs. An absolute path is accepted.
- `profiler_sample_hz`: metric samples per second in a recording's `samples`. On a server each sample has memory and counts, bytes in and out, players and bots.

## Remote reading

Over RCON every command above works as on the console. For a query client, `profiler_query 1` adds `profiler_ms`, `profiler_spikes`, `profiler_period`, `profiler_static_mb` and `profiler_nodes` to the dot-server-query game section. It is off by default because the query answers anyone.

## Tested

`examples/profiler_selftest`'s server section installs on a real `DotConsole`, refuses RCON and chat callers without `config`, records and stops over RCON into an absolute log directory, reads every metric command and the JSON line, checks the samples in the report, the query keys with `profiler_query` off and on, and that freeing the profiler removes everything.
