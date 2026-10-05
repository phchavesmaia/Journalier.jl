@testset "Package entry point" begin
  project = dirname(@__DIR__)
  julia = Base.julia_cmd()
  loadpath = join(("@", "@stdlib"), Sys.iswindows() ? ';' : ':')
  readchild = cmd -> read(addenv(cmd, "JULIA_LOAD_PATH" => loadpath), String)
  output = readchild(`$julia --startup-file=no --project=$project -e 'using Journalier; print("imported")' help`)
  @test output == "imported"
  appoutput = readchild(`$julia --startup-file=no --project=$project -e 'import Journalier: main' help`)
  @test occursin("Usage: journalier", appoutput)
  launcheroutput =
    readchild(`$julia --startup-file=no --project=$project $(joinpath(project, "bin", "journalier")) help`)
  @test occursin("Usage: journalier", launcheroutput)
end

@testset "CLI initialization" begin
  mktempdir() do dir
    withenv(
      "XDG_CONFIG_HOME" => joinpath(dir, "config"),
      "XDG_DATA_HOME" => joinpath(dir, "data"),
      "XDG_STATE_HOME" => joinpath(dir, "state")
    ) do
      fetchcalls = Ref(0)
      fetcher = (db; kwargs...) -> (fetchcalls[] += 1; [(fetched=3,)])
      journalcount = Journalier._withappdb(; fetcher) do db, config
        length(getjournals(db))
      end
      @test journalcount == 6
      @test fetchcalls[] == 1
      @test Journalier.main(["init"]) == 0
      @test isfile(configpath())
      @test isfile(databasepath())
      @test fetchcalls[] == 1
      db = initializedb(databasepath())
      try
        @test length(getjournals(db)) == 6
      finally
        close(db)
      end
    end
  end

  mktempdir() do dir
    db = initializedb(joinpath(dir, "papers.db"))
    try
      output = IOBuffer()
      fetcher = (db; kwargs...) -> error("offline")
      @test Journalier._collectinitial(db, AppConfig(), fetcher; io=output) === nothing
      message = String(take!(output))
      @test occursin("Initial Crossref collection failed: offline", message)
      @test occursin("journalier collect", message)
    finally
      close(db)
    end
  end
end
