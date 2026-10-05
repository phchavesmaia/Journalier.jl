@testset "Configuration" begin
  mktempdir() do dir
    path = joinpath(dir, "nested", "config.toml")
    config = loadconfig(; path)
    @test config.mailto == ""
    @test config.recordsperjournal == 100
    @test isfile(path)
    @test loadconfig(; path) == config

    write(path, "mailto = \" reader@example.org \"\nrecords_per_journal = 250\n")
    config = loadconfig(; path)
    @test config.mailto == "reader@example.org"
    @test config.recordsperjournal == 250
    withenv("CROSSREF_MAILTO" => "environment@example.org") do
      @test Journalier._crossrefmailto(AppConfig()) == "environment@example.org"
      @test Journalier._crossrefmailto(config) == "reader@example.org"
    end

    write(path, "records_per_journal = 0\n")
    @test_throws ArgumentError loadconfig(; path)
    write(path, "unknown = true\n")
    @test_throws ArgumentError loadconfig(; path)
    write(path, "mailto = 123\n")
    @test_throws ArgumentError loadconfig(; path)
  end

  mktempdir() do dir
    withenv("XDG_CONFIG_HOME" => joinpath(dir, "config")) do
      input = IOBuffer("reader@example.org\n")
      output = IOBuffer()
      config = Journalier._ensureconfig(; input, output, prompt=true)
      @test config.mailto == "reader@example.org"
      @test occursin("Crossref contact email", String(take!(output)))
      @test loadconfig().mailto == "reader@example.org"
    end
  end
end
