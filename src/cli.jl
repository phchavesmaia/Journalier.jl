function _collectinitial(db, config, fetcher; io=stderr)
  try
    println("Fetching initial papers from Crossref...")
    summaries = fetcher(db; recordsperjournal=config.recordsperjournal, mailto=_crossrefmailto(config))
    fetched = sum(summary.fetched for summary in summaries; init=0)
    println("Initial collection fetched $fetched records across $(length(summaries)) journals.")
  catch error
    error isa InterruptException && rethrow()
    println(io, "Initial Crossref collection failed: $(sprint(showerror, error))")
    println(io, "The database is ready. Retry later with `journalier collect`.")
  end
  nothing
end

function _withappdb(action; initialfetch=true, fetcher=collectpapers)
  config = _ensureconfig()
  path = databasepath()
  mkpath(dirname(path))
  newdatabase = !isfile(path)
  db = initializedb(path)
  try
    newdatabase && initialfetch && _collectinitial(db, config, fetcher)
    action(db, config)
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
  println(io, "  init     Create the default config and database")
  println(io, "  tui      Open the paper reader")
  println(io, "  collect  Fetch recent papers for registered journals")
  println(io, "  list     List papers stored in the local database")
  println(io, "  config   Show the active configuration")
  println(io, "  paths    Show Journalier's configuration and data paths")
  println(io, "  schedule Manage daily collection")
  println(io, "  help     Show this help")
  0
end

function _tuicommand()
  _withappdb() do db, config
    runui(db)
  end
  0
end

function _collectcommand()
  summaries = _withappdb(; initialfetch=false) do db, config
    collectpapers(db; recordsperjournal=config.recordsperjournal, mailto=_crossrefmailto(config))
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
  papers = _withappdb() do db, config
    getpapers(db)
  end
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

function _initcommand()
  _withappdb() do db, config
    println("Initialized Journalier.")
    println("Configuration: $(configpath())")
    println("Database:      $(databasepath())")
    println("Journals:      $(length(getjournals(db)))")
  end
  0
end

function _configcommand()
  config = _ensureconfig()
  println("Configuration:       $(configpath())")
  println("Crossref mailto:     $(isempty(config.mailto) ? "(not set)" : config.mailto)")
  println("Records per journal: $(config.recordsperjournal)")
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
function (@main)(args=ARGS)
  isempty(args) && return _tuicommand()
  command = first(args)
  if command in ("help", "-h", "--help") && length(args) == 1
    _cliusage()
  elseif command == "init" && length(args) == 1
    _initcommand()
  elseif command == "collect" && length(args) == 1
    _collectcommand()
  elseif command == "tui" && length(args) == 1
    _tuicommand()
  elseif command == "list" && length(args) == 1
    _listcommand()
  elseif command == "config" && length(args) == 1
    _configcommand()
  elseif command == "paths" && length(args) == 1
    _pathscommand()
  elseif command == "schedule"
    _schedulecommand(args[2:end])
  else
    println(stderr, "Unknown command or unexpected arguments: $(join(args, ' '))")
    _cliusage(stderr)
    2
  end
end
