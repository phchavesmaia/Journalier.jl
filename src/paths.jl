function _xdgappdir(variable)
  root = get(ENV, variable, "")
  (isempty(root) || !isabspath(root)) ? nothing : joinpath(root, "journalier")
end

function _environmentpath(variable, fallback)
  root = get(ENV, variable, "")
  (isempty(root) || !isabspath(root)) && (root = joinpath(homedir(), fallback...))
  root
end

function _platformappdir(xdgvariable, unixfallback, macfallback, windowsvariable, windowsfallback; suffix=())
  xdgdir = _xdgappdir(xdgvariable)
  xdgdir === nothing || return xdgdir
  if Sys.iswindows()
    joinpath(_environmentpath(windowsvariable, windowsfallback), "Journalier", suffix...)
  elseif Sys.isapple()
    joinpath(joinpath(homedir(), macfallback...), "Journalier")
  else
    joinpath(joinpath(homedir(), unixfallback...), "journalier")
  end
end

"""Return Journalier's per-user configuration directory."""
configdir() = _platformappdir(
  "XDG_CONFIG_HOME",
  (".config",),
  ("Library", "Preferences"),
  "APPDATA",
  ("AppData", "Roaming")
)

"""Return Journalier's per-user data directory."""
datadir() = _platformappdir(
  "XDG_DATA_HOME",
  (".local", "share"),
  ("Library", "Application Support"),
  "LOCALAPPDATA",
  ("AppData", "Local")
)

"""Return Journalier's per-user state directory."""
statedir() = _platformappdir(
  "XDG_STATE_HOME",
  (".local", "state"),
  ("Library", "Logs"),
  "LOCALAPPDATA",
  ("AppData", "Local");
  suffix=("State",)
)

"""Return the path to Journalier's TOML configuration file."""
configpath() = joinpath(configdir(), "config.toml")

"""Return the path to Journalier's SQLite database."""
databasepath() = joinpath(datadir(), "papers.db")
