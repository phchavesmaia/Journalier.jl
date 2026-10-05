module Journalier

using DBInterface
using HTTP
using JSON
using SQLite

include("paper.jl")
include("journal.jl")
include("database.jl")
include("collector.jl")

export Paper, Journal, DEFAULT_JOURNALS, initializedb, upsertpaper, getpapers, getpaper, getjournals, markread, toggleread, togglesaved, collectjournal, collectpapers

end
