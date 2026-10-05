module Journalier

using DBInterface
using SQLite

include("database.jl")

export initialize_database, upsert_paper, get_papers, get_paper, get_journals, mark_read, toggle_read, toggle_saved

end
