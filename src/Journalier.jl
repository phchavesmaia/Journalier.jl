module Journalier

using DBInterface
using HTTP
using JSON
using SQLite

include("paper.jl")
include("journal.jl")
include("database.jl")
include("collector.jl")

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
  collectpapers
end
