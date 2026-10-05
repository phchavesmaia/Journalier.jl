# Journalier

Journalier collects recent economics papers from Crossref and provides a terminal reader for tracking new, unread, and saved papers.

Papers are shown by newest Crossref registration date first, with local discovery time and title breaking ties. Publication dates may refer to online-first publication; the reader does not infer an in-press status from those dates. Today and This Week continue to filter by local discovery time.

## Requirements

Journalier requires Julia 1.11 or later. Crossref collection needs an internet connection.

## Run from this checkout

From the repository root, run `julia --project=. bin/journalier` to open the reader or pass a command such as `julia --project=. bin/journalier init`. To install dependencies first, run `julia --project=. -e 'using Pkg; Pkg.instantiate()'`.

## Install the `journalier` command

Julia's package manager can install a package app from a checkout. In the Julia REPL, run:

```julia
using Pkg
Pkg.Apps.develop("/absolute/path/to/Journalier")
```

The command shim is installed under `~/.julia/bin` by default. Add that directory to your `PATH`, then run `journalier`. The package app interface is experimental in Pkg, so the local `bin/journalier` launcher remains available as a reliable checkout-based option.

## First run and configuration

On the first interactive launch, Journalier asks for an optional Crossref contact email if the config file is missing. It creates a missing database, seeds the six starter journals, and attempts an initial Crossref collection. If that request fails, the database remains usable and Journalier tells you to retry with `journalier collect`. Without an interactive terminal, it skips the email prompt and creates a blank config. You can also run `journalier init` to perform first-run setup explicitly; journals can be managed from the TUI. `journalier paths` prints the active locations, and `journalier config` shows the configuration values.

The TOML file accepts these settings:

```toml
mailto = "reader@example.org"
records_per_journal = 100
```

`mailto` identifies the Crossref API client; when it is blank, Journalier uses `CROSSREF_MAILTO` if set. `records_per_journal` controls the maximum number fetched for each journal and must be between 1 and 1000. The file lives in the platform's user configuration directory. On Linux, the defaults are `~/.config/journalier/config.toml`, `~/.local/share/journalier/papers.db`, and `~/.local/state/journalier/collector.log`; XDG environment variables override those roots.

## Commands

- `journalier` or `journalier tui` opens the terminal reader.
- `journalier collect` fetches recent records from registered journals.
- `journalier list` prints stored papers.
- `journalier schedule install [--time HH:MM]` enables daily collection at 07:00 by default. Linux uses a systemd user timer when available and falls back to cron; the command requires the installed `journalier` executable on `PATH`.
- `journalier schedule status` reports the detected schedule, and `journalier schedule remove` removes Journalier's managed schedule.
- `journalier help` lists the commands.

Scheduling is opt-in. Cron output is appended to `collector.log` in the per-user state directory. Systemd captures service output in the user journal; view it with `journalctl --user -u journalier-collect.service`.

Schedules retain the XDG configuration, data, and state settings used at installation. Reinstall the schedule after changing these settings. Crontab read errors abort installation instead of replacing existing jobs.

This beta version requires the current database schema and does not migrate older databases. An unsupported schema produces an explicit error; use a new database to initialize this version. Paper text is stored as plain text, and journal filtering uses the collection ISSN.

## Tests

Run the package test suite with `julia --project=. -e 'using Pkg; Pkg.test()'`.

`test/runtests.jl` loads the paths, configuration, database, collector, TUI, scheduler, and CLI suites in an explicit order. Source files for the database, TUI, and scheduler coordinate their respective implementation directories; Crossref handling and shared text utilities have separate files.
