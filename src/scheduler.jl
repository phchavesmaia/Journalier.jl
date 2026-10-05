const _SCHEDULER_MARKER = "# journalier-managed"
const _SCHEDULER_SERVICE = "journalier-collect"

function _validtime(value)
  occursin(r"^(?:[01]\d|2[0-3]):[0-5]\d$", value) || throw(ArgumentError("time must use 24-hour HH:MM format"))
  value
end

function _scheduleenvironment()
  settings = [name => get(ENV, name, "") for name in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME")]
  for (name, value) in settings
    any(character -> character in ('\n', '\r', '\0'), value) &&
      throw(ArgumentError("$name cannot contain newlines or NUL in a schedule"))
  end
  settings
end

include("scheduler/systemd.jl")
include("scheduler/cron.jl")

function _scheduleexecutable()
  executable = Sys.which("journalier")
  executable === nothing && throw(ArgumentError("install Journalier as a Julia app before installing a schedule"))
  realpath(executable)
end

function _installschedule(time)
  time = _validtime(time)
  _scheduleenvironment()
  executable = _scheduleexecutable()
  mkpath(statedir())
  if _systemdavailable()
    Sys.which("crontab") === nothing || _removecron()
    _writeunits(executable, time)
    println("Installed a daily systemd user timer at $time.")
  else
    existing = _readcron()
    entry = _cronentry(executable, time)
    _writecron(_updatedcron(existing; entry))
    _removesystemd()
    println("Installed a daily cron job at $time.")
  end
  0
end

function _scheduleinfo(io=stdout)
  timerpath = joinpath(_systemdunitdir(), "$_SCHEDULER_SERVICE.timer")
  if isfile(timerpath)
    timer = read(timerpath, String)
    matchresult = match(r"(?m)^OnCalendar=\*-\*-\* (\d{2}:\d{2}):00$", timer)
    time = matchresult === nothing ? "unknown" : matchresult.captures[1]
    state = if Sys.which("systemctl") === nothing || !_systemdavailable()
      "unavailable"
    else
      active = success(
        pipeline(
          ignorestatus(`$(Sys.which("systemctl")) --user is-active --quiet $_SCHEDULER_SERVICE.timer`),
          stderr=devnull
        )
      )
      active ? "active" : "inactive"
    end
    println(io, "Daily collection: systemd user timer ($state) at $time.")
    return true
  end
  if Sys.which("crontab") !== nothing
    existing = _readcron()
    line = findfirst(line -> occursin(_SCHEDULER_MARKER, line), split(existing, '\n'))
    if line !== nothing
      entry = split(existing, '\n')[line]
      println(io, "Daily collection: cron job installed.")
      println(io, "  $entry")
      return true
    end
  end
  println(io, "Daily collection: not installed.")
  false
end

function _removeschedule()
  removed = _removesystemd()
  removedcron = _removecron()
  if removed || removedcron
    println("Removed Journalier's daily collection schedule.")
  else
    println("No Journalier schedule was installed.")
  end
  0
end

function _schedulecommand(args)
  isempty(args) && return _scheduleusage(stderr)
  action = first(args)
  if action == "install"
    time = if length(args) == 1
      "07:00"
    elseif length(args) == 3 && args[2] == "--time"
      args[3]
    else
      return _scheduleusage(stderr)
    end
    _installschedule(time)
  elseif action == "status" && length(args) == 1
    _scheduleinfo()
    0
  elseif action == "remove" && length(args) == 1
    _removeschedule()
  else
    _scheduleusage(stderr)
  end
end

function _scheduleusage(io=stdout)
  println(io, "Usage: journalier schedule install [--time HH:MM] | status | remove")
  2
end
