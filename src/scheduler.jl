const _SCHEDULER_MARKER = "# journalier-managed"
const _SCHEDULER_SERVICE = "journalier-collect"

function _validtime(value)
  occursin(r"^(?:[01]\d|2[0-3]):[0-5]\d$", value) || throw(ArgumentError("time must use 24-hour HH:MM format"))
  value
end

function _systemdquote(value)
  "\"" * replace(value, "\\" => "\\\\", "\"" => "\\\"", "%" => "%%") * "\""
end

function _scheduleenvironment()
  settings = [name => get(ENV, name, "") for name in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME")]
  for (name, value) in settings
    any(character -> character in ('\n', '\r', '\0'), value) &&
      throw(ArgumentError("$name cannot contain newlines or NUL in a schedule"))
  end
  settings
end

function _systemdunits(executable, time)
  time = _validtime(time)
  environment = join(["Environment=$(_systemdquote("$name=$value"))" for (name, value) in _scheduleenvironment()], "\n")
  service = """
  [Unit]
  Description=Collect recent papers with Journalier

  [Service]
  Type=oneshot
  $environment
  ExecStart=$(_systemdquote(executable)) collect
  """
  timer = """
  [Unit]
  Description=Daily Journalier collection

  [Timer]
  OnCalendar=*-*-* $time:00
  Persistent=true
  Unit=$(_SCHEDULER_SERVICE).service

  [Install]
  WantedBy=timers.target
  """
  (service=service, timer=timer)
end

function _systemdunitdir()
  joinpath(dirname(configdir()), "systemd", "user")
end

function _systemdavailable()
  Sys.islinux() || return false
  systemctl = Sys.which("systemctl")
  systemctl === nothing && return false
  success(pipeline(ignorestatus(`$systemctl --user show-environment`), stdout=devnull, stderr=devnull))
end

function _writeunits(executable, time)
  units = _systemdunits(executable, time)
  unitdir = _systemdunitdir()
  mkpath(unitdir)
  write(joinpath(unitdir, "$_SCHEDULER_SERVICE.service"), units.service)
  write(joinpath(unitdir, "$_SCHEDULER_SERVICE.timer"), units.timer)
  run(`$(Sys.which("systemctl")) --user daemon-reload`)
  run(`$(Sys.which("systemctl")) --user enable --now $_SCHEDULER_SERVICE.timer`)
  unitdir
end

function _cronentry(executable, time)
  time = _validtime(time)
  hour, minute = parse.(Int, split(time, ':'))
  logpath = joinpath(statedir(), "collector.log")
  quotecron(value) = "'" * replace(replace(value, "'" => "'\\''"), "%" => "\\%") * "'"
  environment = join(["$name=$(quotecron(value))" for (name, value) in _scheduleenvironment()], " ")
  "$minute $hour * * * $environment $(quotecron(executable)) collect >> $(quotecron(logpath)) 2>&1 $_SCHEDULER_MARKER"
end

function _readcron()
  crontab = Sys.which("crontab")
  crontab === nothing && throw(ArgumentError("crontab is not available on this system"))
  output = IOBuffer()
  errors = IOBuffer()
  command = addenv(`$crontab -l`, "LC_ALL" => "C")
  process = run(pipeline(ignorestatus(command); stdout=output, stderr=errors))
  content = String(take!(output))
  diagnostic = strip(String(take!(errors)))
  success(process) && return content
  if process.exitcode == 1 && isempty(content) && occursin(r"^(?:crontab:\s*)?no crontab for \S+$", diagnostic)
    return ""
  end
  error("could not read crontab (exit code $(process.exitcode)): $diagnostic")
end

function _updatedcron(existing; entry=nothing)
  lines = filter(line -> !occursin(_SCHEDULER_MARKER, line), split(chomp(existing), '\n'; keepempty=false))
  entry === nothing || push!(lines, entry)
  isempty(lines) ? "" : join(lines, "\n") * "\n"
end

function _writecron(content)
  crontab = Sys.which("crontab")
  crontab === nothing && throw(ArgumentError("crontab is not available on this system"))
  process = open(`$crontab -`, "w")
  try
    write(process, content)
  finally
    close(process)
  end
  success(process) || error("crontab update failed with exit code $(process.exitcode)")
  nothing
end

function _scheduleexecutable()
  executable = Sys.which("journalier")
  executable === nothing && throw(ArgumentError("install Journalier as a Julia app before installing a schedule"))
  realpath(executable)
end

function _removesystemd()
  unitdir = _systemdunitdir()
  timerpath = joinpath(unitdir, "$_SCHEDULER_SERVICE.timer")
  servicepath = joinpath(unitdir, "$_SCHEDULER_SERVICE.service")
  removed = isfile(timerpath) || isfile(servicepath)
  if removed
    systemctl = Sys.which("systemctl")
    if systemctl !== nothing
      run(pipeline(ignorestatus(`$systemctl --user disable --now $_SCHEDULER_SERVICE.timer`), stderr=devnull))
    end
    isfile(timerpath) && rm(timerpath)
    isfile(servicepath) && rm(servicepath)
    if systemctl !== nothing && _systemdavailable()
      run(`$systemctl --user daemon-reload`)
    end
  end
  removed
end

function _removecron()
  Sys.which("crontab") === nothing && return false
  existing = _readcron()
  updated = _updatedcron(existing)
  updated == existing && return false
  _writecron(updated)
  true
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
