[![Build Status](https://github.com/phchavesmaia/Journalier.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/phchavesmaia/Journalier.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/phchavesmaia/Journalier.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/phchavesmaia/Journalier.jl)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Julia 1.12+](https://img.shields.io/badge/julia-%E2%89%A5%201.12-9558B2?logo=julia&logoColor=white)]()

# Journalier.jl

Tired of feeling behind on your reading? Journalier helps you keep up with what's happening in the academic world. Select your favorite journals, and Journalier collects their latest papers from Crossref, providing a terminal-based reader for keeping track of new, unread, and saved papers.

## Usage
After installing Journalier, run it by typing
```text
journalier
```
in your terminal to see what's new in your selected journals.

![Example of usage](./example.gif)

Journalier also has a search function, which you can access by pressing `/` and typing your keywords. Searches cover author names as well as words in the title or abstract. In the example above, I searched for papers containing the word "transport".

## Installation

### Requirements
Journalier requires Julia 1.12 or later. Crossref collection needs an internet connection.

### The `journalier` command
Julia's package manager can install a package app from a checkout. In the Julia REPL, run:

```julia
using Pkg
Pkg.Apps.develop(path="/absolute/path/to/Journalier")
```

The command shim is installed under `~/.julia/bin` by default. Add that directory to your `PATH`, then run `journalier`. The package app interface is experimental in Pkg, so the local `bin/journalier` launcher remains available as a reliable checkout-based option.

## First run and configuration

On the first interactive launch, Journalier asks for an optional Crossref contact email if the config file is missing. It creates a missing database, seeds the six starter economics journals, and attempts an initial Crossref collection. If that request fails, Journalier tells you to retry with `journalier collect`.

Without an interactive terminal, it skips the email prompt and creates a blank config. You can also run `journalier init` to perform first-run setup explicitly; journals can be managed from the TUI. `journalier paths` prints the active locations, and `journalier config` shows the configuration values.

The TOML file accepts these settings:

```toml
mailto = "reader@example.org"
records_per_journal = 100
```

`mailto` identifies the Crossref API client; when it is blank, Journalier uses `CROSSREF_MAILTO` if set. `records_per_journal` controls the maximum number fetched for each journal and must be between 1 and 1000. The file lives in the platform's user configuration directory. 

On Linux, the defaults are `~/.config/journalier/config.toml`, `~/.local/share/journalier/papers.db`, and `~/.local/state/journalier/collector.log`; XDG environment variables override those roots.

## Commands

| Command | Description |
| --- | --- |
| `journalier` or `journalier tui` | Open the terminal reader. |
| `journalier collect` | Fetch recent records from registered journals. |
| `journalier list` | Print stored papers. |
| `journalier schedule install [--time HH:MM]` | Enable daily collection at 07:00 by default. Linux uses a systemd user timer when available and falls back to cron. Requires the installed `journalier` executable on `PATH`. |
| `journalier schedule status` | Report the detected schedule. |
| `journalier schedule remove` | Remove Journalier's managed schedule. |
| `journalier help` | List the commands. |

Scheduling is opt-in. Cron output is appended to `collector.log` in the per-user state directory. Systemd captures service output in the user journal; view it with `journalctl --user -u journalier-collect.service`.

Schedules retain the XDG configuration, data, and state settings used at installation. Reinstall the schedule after changing these settings. Crontab read errors abort installation instead of replacing existing jobs.
