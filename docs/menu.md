# Settings menu integration

dot-profiler does not depend on dot-menu, and dot-menu does not depend on dot-profiler. A `DotProfiler` registers itself in `DotRegistry` as `&"dot_profiler"` (`register_as_service`, on by default). A menu that finds that service and sees `make_menu_panel` on it adds a Performance section built by `make_menu_panel(kit)`, passing its `DotMenuKit` so the panel matches the menu's theme. With no profiler placed, the section is not shown.

The panel holds:

- the overlay toggle;
- Record / Stop, with the elapsed time while recording;
- "Saved to <path>" once a report is written;
- on desktop, Open folder and Copy path; in the browser, Download report (every write and prune already calls `DotWeb.sync_filesystem()`, so the file survives a reload);
- the recent recordings, newest first.

Reports are a JSON file and a text file per recording in `profiler_record_dir` (`user://profiles`), the oldest deleted beyond `profiler_keep_recordings`.

Any other menu can do the same: look the service up, call `make_menu_panel(kit_or_null)`, and add the returned `Control`.
