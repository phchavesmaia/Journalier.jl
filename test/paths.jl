@testset "Application paths" begin
  mktempdir() do dir
    configroot = joinpath(dir, "config")
    dataroot = joinpath(dir, "data")
    stateroot = joinpath(dir, "state")
    withenv("XDG_CONFIG_HOME" => configroot, "XDG_DATA_HOME" => dataroot, "XDG_STATE_HOME" => stateroot) do
      @test configdir() == joinpath(configroot, "journalier")
      @test datadir() == joinpath(dataroot, "journalier")
      @test statedir() == joinpath(stateroot, "journalier")
      @test configpath() == joinpath(configroot, "journalier", "config.toml")
      @test databasepath() == joinpath(dataroot, "journalier", "papers.db")
    end

    roaming = joinpath(dir, "roaming")
    localdata = joinpath(dir, "local")
    withenv(
      "XDG_CONFIG_HOME" => "relative-config",
      "XDG_DATA_HOME" => "relative-data",
      "XDG_STATE_HOME" => "relative-state",
      "APPDATA" => roaming,
      "LOCALAPPDATA" => localdata
    ) do
      if Sys.iswindows()
        @test configdir() == joinpath(roaming, "Journalier")
        @test datadir() == joinpath(localdata, "Journalier")
        @test statedir() == joinpath(localdata, "Journalier", "State")
      elseif Sys.isapple()
        @test configdir() == joinpath(homedir(), "Library", "Preferences", "Journalier")
        @test datadir() == joinpath(homedir(), "Library", "Application Support", "Journalier")
        @test statedir() == joinpath(homedir(), "Library", "Logs", "Journalier")
      else
        @test configdir() == joinpath(homedir(), ".config", "journalier")
        @test datadir() == joinpath(homedir(), ".local", "share", "journalier")
        @test statedir() == joinpath(homedir(), ".local", "state", "journalier")
      end
    end
  end
end
