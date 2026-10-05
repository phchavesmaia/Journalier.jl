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

function _removecron()
  Sys.which("crontab") === nothing && return false
  existing = _readcron()
  updated = _updatedcron(existing)
  updated == existing && return false
  _writecron(updated)
  true
end
