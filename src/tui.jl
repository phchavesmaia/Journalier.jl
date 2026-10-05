include("tui/model.jl")
include("tui/input.jl")
include("tui/view.jl")

"""Open the interactive reader for papers and journals stored in `db`."""
runui(db) = Tachikoma.app(ReaderModel(db))
