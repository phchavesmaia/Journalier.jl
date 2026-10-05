@testset "Scheduler helpers" begin
  @test Journalier._validtime("07:05") == "07:05"
  @test_throws ArgumentError Journalier._validtime("24:00")
  @test_throws ArgumentError Journalier._validtime("7:05")

  units = Journalier._systemdunits("/path with space/journalier", "07:05")
  @test occursin("ExecStart=\"/path with space/journalier\" collect", units.service)
  @test occursin("OnCalendar=*-*-* 07:05:00", units.timer)
  @test occursin("Unit=journalier-collect.service", units.timer)

  cron = Journalier._cronentry("/path with space/journalier", "07:05")
  @test startswith(cron, "5 7 * * * XDG_CONFIG_HOME=")
  @test endswith(cron, Journalier._SCHEDULER_MARKER)
  @test occursin("journalier' collect", cron)

  existing = "MAILTO=user@example.org\n0 8 * * * backup\n0 6 * * * old-job # journalier-managed\n"
  updated = Journalier._updatedcron(existing; entry=cron)
  @test occursin("MAILTO=user@example.org", updated)
  @test occursin("0 8 * * * backup", updated)
  @test !occursin("old-job", updated)
  @test count(line -> occursin(Journalier._SCHEDULER_MARKER, line), split(updated, '\n')) == 1
  @test Journalier._updatedcron(updated; entry=cron) == updated
  @test Journalier._updatedcron(updated) == "MAILTO=user@example.org\n0 8 * * * backup\n"
end

@testset "Schedule removal" begin
  if Sys.isunix()
    mktempdir() do dir
      withenv("XDG_CONFIG_HOME" => joinpath(dir, "config"), "PATH" => dir) do
        @test Journalier._removesystemd() === false
        @test Journalier.main(["schedule", "remove"]) == 0
        systemctl = joinpath(dir, "systemctl")
        write(systemctl, "#!/bin/sh\nexit 0\n")
        chmod(systemctl, 0o755)
        unitdir = Journalier._systemdunitdir()
        mkpath(unitdir)
        servicepath = joinpath(unitdir, "journalier-collect.service")
        timerpath = joinpath(unitdir, "journalier-collect.timer")
        write(servicepath, "service")
        write(timerpath, "timer")
        @test Journalier._removesystemd() === true
        @test !isfile(servicepath)
        @test !isfile(timerpath)
        write(timerpath, "timer")
        @test Journalier.main(["schedule", "remove"]) == 0
        @test !isfile(timerpath)

        cronpath = joinpath(dir, "crontab.txt")
        write(cronpath, "0 8 * * * backup\n0 7 * * * collect # journalier-managed\n")
        crontab = joinpath(dir, "crontab")
        write(
          crontab,
          raw"""#!/bin/sh
            if [ "$1" = "-l" ]; then
              while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done < "$JOURNALIER_TEST_CRONTAB"
            else
              while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done > "$JOURNALIER_TEST_CRONTAB"
            fi
          """
        )
        chmod(crontab, 0o755)
        withenv("JOURNALIER_TEST_CRONTAB" => cronpath) do
          @test Journalier.main(["schedule", "remove"]) == 0
          @test read(cronpath, String) == "0 8 * * * backup\n"
          @test Journalier.main(["schedule", "remove"]) == 0
        end
        write(
          crontab,
          "#!/bin/sh\nwhile IFS= read -r line || [ -n \"\$line\" ]; do printf '%s\\n' \"\$line\"; done > /dev/null\nexit 1\n"
        )
        @test_throws ErrorException Journalier._writecron("0 8 * * * backup\n")
      end
    end
  end
end

@testset "Crontab read failures" begin
  if Sys.isunix()
    mktempdir() do dir
      withenv(
        "PATH" => dir,
        "XDG_CONFIG_HOME" => joinpath(dir, "config"),
        "XDG_STATE_HOME" => joinpath(dir, "state")
      ) do
        crontab = joinpath(dir, "crontab")
        executable = joinpath(dir, "journalier")
        write(executable, "#!/bin/sh\nexit 0\n")
        chmod(executable, 0o755)
        write(crontab, "#!/bin/sh\nprintf 'no crontab for reader\\n' >&2\nexit 1\n")
        chmod(crontab, 0o755)
        @test Journalier._readcron() == ""
        write(crontab, "#!/bin/sh\nprintf 'crontab: no crontab for reader\\n' >&2\nexit 1\n")
        @test Journalier._readcron() == ""

        writepath = joinpath(dir, "unexpected-write")
        withenv("JOURNALIER_TEST_WRITE" => writepath) do
          for (diagnostic, exitcode) in (("permission denied", 1), ("", 2), ("no crontab for reader", 2))
            write(
              crontab,
              """
#!/bin/sh
if [ "\$1" = "-l" ]; then
  printf '%s\\n' '$diagnostic' >&2
  exit $exitcode
fi
while IFS= read -r line || [ -n "\$line" ]; do printf '%s\\n' "\$line"; done > "\$JOURNALIER_TEST_WRITE"
"""
            )
            @test_throws ErrorException Journalier._readcron()
            @test_throws ErrorException Journalier.main(["schedule", "install"])
            @test !isfile(writepath)
          end
          write(crontab, "#!/bin/sh\nprintf '0 8 * * * backup\\n'\nexit 1\n")
          @test_throws ErrorException Journalier._readcron()
          write(crontab, "#!/bin/sh\nprintf '0 8 * * * backup\\n'\nexit 0\n")
          @test Journalier._readcron() == "0 8 * * * backup\n"
        end
      end
    end
  end
end

@testset "Scheduled XDG environment" begin
  if Sys.isunix()
    mktempdir() do dir
      configroot = joinpath(dir, "config '\"%\$")
      dataroot = joinpath(dir, "data with spaces")
      stateroot = joinpath(dir, "state")
      executable = joinpath(dir, "journalier")
      write(
        executable,
        raw"""
#!/bin/sh
printf '%s\n' "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
"""
      )
      chmod(executable, 0o755)
      service, entry, logpath =
        withenv("XDG_CONFIG_HOME" => configroot, "XDG_DATA_HOME" => dataroot, "XDG_STATE_HOME" => stateroot) do
          mkpath(statedir())
          (
            Journalier._systemdunits(executable, "07:05").service,
            Journalier._cronentry(executable, "07:05"),
            joinpath(statedir(), "collector.log")
          )
        end
      @test occursin("Environment=\"XDG_DATA_HOME=$dataroot\"", service)
      @test occursin("Environment=\"XDG_STATE_HOME=$stateroot\"", service)
      @test occursin("config '\\\"%%\$", service)
      # Cron removes the escaping of percent characters before invoking its shell.
      command = replace(split(entry; limit=6)[6], "\\%" => "%")
      withenv(
        "XDG_CONFIG_HOME" => "/wrong/config",
        "XDG_DATA_HOME" => "/wrong/data",
        "XDG_STATE_HOME" => "/wrong/state"
      ) do
        run(`/bin/sh -c $command`)
      end
      @test read(logpath, String) == join((configroot, dataroot, stateroot), '\n') * "\n"
      withenv("XDG_CONFIG_HOME" => nothing, "XDG_DATA_HOME" => nothing, "XDG_STATE_HOME" => nothing) do
        units = Journalier._systemdunits(executable, "07:05")
        @test occursin("Environment=\"XDG_CONFIG_HOME=\"", units.service)
        @test occursin("XDG_CONFIG_HOME=''", Journalier._cronentry(executable, "07:05"))
      end
      withenv("XDG_DATA_HOME" => "bad\npath") do
        @test_throws ArgumentError Journalier._systemdunits(executable, "07:05")
        @test_throws ArgumentError Journalier._cronentry(executable, "07:05")
      end
    end
  end
end
