function _withappdb(action)
  path = databasepath()
  mkpath(dirname(path))
  db = initializedb(path)
  try
    action(db)
  finally
    close(db)
  end
end

function _cliusage(io=stdout)
  println(io, "Journalier — economics paper collector")
  println(io, "Run `journalier` to open the paper reader.")
  println(io, "Usage: journalier <command>")
  println(io, "")
  println(io, "Commands:")
  println(io, "  tui      Open the paper reader")
  println(io, "  collect  Fetch recent papers for registered journals")
  println(io, "  list     List papers stored in the local database")
  println(io, "  paths    Show Journalier's configuration and data paths")
  println(io, "  help     Show this help")
  0
end

function _tuicommand()
  _withappdb() do db
    runui(db)
  end
  0
end

function _collectcommand()
  summaries = _withappdb() do db
    collectpapers(db)
  end
  for summary in summaries
    println(
      "$(summary.journal): fetched $(summary.fetched), inserted $(summary.inserted), " *
      "updated $(summary.updated), skipped $(summary.skipped)"
    )
  end
  0
end

function _listcommand()
  papers = _withappdb(getpapers)
  if isempty(papers)
    println("No papers collected yet. Run `journalier collect`.")
  else
    for (index, paper) in enumerate(papers)
      println("$index. $(paper.title)")
      isempty(paper.authors) || println("   $(paper.authors)")
      print("   $(paper.journal)")
      paper.published_at === nothing || print(" · $(paper.published_at)")
      println()
    end
  end
  0
end

function _pathscommand()
  println("Configuration directory: $(configdir())")
  println("Configuration file:     $(configpath())")
  println("Data directory:          $(datadir())")
  println("Database:                $(databasepath())")
  println("State directory:         $(statedir())")
  0
end

"""Run Journalier's command-line interface with `args` (defaults to `ARGS`)."""
function main(args=ARGS)
  isempty(args) && return _tuicommand()
  command = first(args)
  if command in ("help", "-h", "--help") && length(args) == 1
    _cliusage()
  elseif command == "collect" && length(args) == 1
    _collectcommand()
  elseif command == "tui" && length(args) == 1
    _tuicommand()
  elseif command == "list" && length(args) == 1
    _listcommand()
  elseif command == "paths" && length(args) == 1
    _pathscommand()
  else
    println(stderr, "Unknown command or unexpected arguments: $(join(args, ' '))")
    _cliusage(stderr)
    2
  end
end
