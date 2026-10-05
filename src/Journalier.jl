module Journalier

using DBInterface
using Dates
using HTTP
using JSON
using PrecompileTools: @setup_workload, @compile_workload
using SQLite
using Tachikoma
using TOML

import Tachikoma: should_quit, update!, view

include("paper.jl")
include("journal.jl")
include("database.jl")
include("text.jl")
include("crossref.jl")
include("collector.jl")
include("paths.jl")
include("config.jl")
include("scheduler.jl")
include("tui.jl")
include("cli.jl")

export Paper,
  AppConfig,
  Journal,
  INITIAL_JOURNALS,
  initializedb,
  upsertpaper,
  getpapers,
  getpaper,
  getrawmetadata,
  addjournal,
  getjournal,
  getjournals,
  getjournalcounts,
  removejournal,
  markread,
  toggleread,
  togglesaved,
  collectjournal,
  collectpapers,
  configdir,
  datadir,
  statedir,
  loadconfig,
  configpath,
  databasepath,
  runui

include("precompile.jl")
end
