function _systemdquote(value)
  "\"" * replace(value, "\\" => "\\\\", "\"" => "\\\"", "%" => "%%") * "\""
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
