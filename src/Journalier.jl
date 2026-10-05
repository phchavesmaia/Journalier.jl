module Journalier

using DBInterface
using Dates
using HTTP
using JSON
using SQLite
using Tachikoma

import Tachikoma: should_quit, update!, view

include("paper.jl")
include("journal.jl")
include("database.jl")
include("collector.jl")
include("paths.jl")
include("tui.jl")
include("cli.jl")

export Paper,
  Journal,
  INITIAL_JOURNALS,
  initializedb,
  upsertpaper,
  getpapers,
  getpaper,
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
  configpath,
  databasepath,
  runui,
  main
end
