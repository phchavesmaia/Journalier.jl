Base.@kwdef struct AppConfig
  mailto::String = ""
  recordsperjournal::Int = 100
end

function _writeconfig(path; mailto="")
  mkpath(dirname(path))
  open(path, "w") do io
    write(io, "# Optional contact address for Crossref requests.\n")
    TOML.print(io, Dict("mailto" => mailto, "records_per_journal" => 100))
  end
  chmod(path, 0o600)
  path
end

function _ensureconfig(; input=stdin, output=stdout, prompt=input isa Base.TTY)
  path = configpath()
  if !isfile(path)
    mailto = ""
    if prompt
      print(output, "Crossref contact email (optional; press Enter to skip): ")
      flush(output)
      mailto = strip(readline(input))
    end
    _writeconfig(path; mailto)
  end
  loadconfig(; path)
end

"""Load Journalier settings, creating a default configuration on first use."""
function loadconfig(; path=configpath())
  isfile(path) || _writeconfig(path)
  settings = TOML.parsefile(path)
  unknown = setdiff(keys(settings), ("mailto", "records_per_journal"))
  isempty(unknown) || throw(ArgumentError("unknown setting(s) in $path: $(join(sort!(collect(unknown)), ", "))"))

  mailto = get(settings, "mailto", "")
  mailto isa AbstractString || throw(ArgumentError("mailto in $path must be a string"))
  recordsperjournal = get(settings, "records_per_journal", 100)
  recordsperjournal isa Integer && !(recordsperjournal isa Bool) ||
    throw(ArgumentError("records_per_journal in $path must be an integer"))
  1 <= recordsperjournal <= 1000 || throw(ArgumentError("records_per_journal in $path must be between 1 and 1000"))

  AppConfig(mailto=strip(mailto), recordsperjournal=recordsperjournal)
end

function _crossrefmailto(config)
  isempty(config.mailto) ? get(ENV, "CROSSREF_MAILTO", "") : config.mailto
end
