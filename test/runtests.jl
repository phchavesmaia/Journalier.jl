using Journalier
using HTTP
using JSON
using Dates
using Tachikoma
using Test

@testset "Reader model and view" begin
  mktempdir() do dir
    db = initializedb(joinpath(dir, "papers.db"))
    try
      recent = Dates.format(Dates.now(Dates.UTC), dateformat"yyyy-mm-dd HH:MM:SS")
      old = Dates.format(Dates.now(Dates.UTC) - Day(14), dateformat"yyyy-mm-dd HH:MM:SS")
      upsertpaper(
        db;
        doi="10.1234/first",
        title="First Sample Paper",
        authors="Ada Lovelace",
        journal="Journal of Urban Economics",
        abstracttext="A short abstract for the first paper.",
        url="https://doi.org/10.1234/first",
        rawmetadata=JSON.json(Dict("title" => ["First\n                    <i>Sample</i> Paper"]))
      )
      upsertpaper(
        db;
        doi="10.1234/second",
        title="Second Older Paper",
        authors="Grace Hopper",
        journal="The Quarterly Journal of Economics",
        abstracttext="An older paper abstract."
      )
      Journalier.DBInterface.execute(db, "UPDATE papers SET first_seen_at = ? WHERE doi = ?", (recent, "10.1234/first"))
      Journalier.DBInterface.execute(db, "UPDATE papers SET first_seen_at = ? WHERE doi = ?", (old, "10.1234/second"))
      togglesaved(db, "10.1234/first")

      model = Journalier.ReaderModel(db)
      @test length(model.papers) == 2
      @test model.journalindex == 1
      @test model.journalcounts["quarterly journal of economics"] == 1
      @test Journalier._isnew(model.papers[1])
      @test !Journalier._isnew(model.papers[2])
      @test !Tachikoma.should_quit(model)
      Tachikoma.update!(model, Tachikoma.KeyEvent(:down))
      @test model.paperindex == 2
      Tachikoma.update!(model, Tachikoma.KeyEvent('k'))
      @test model.paperindex == 1

      Tachikoma.update!(model, Tachikoma.KeyEvent('r'))
      @test getpaper(db, "10.1234/first").is_read
      Tachikoma.update!(model, Tachikoma.KeyEvent('s'))
      @test !getpaper(db, "10.1234/first").is_saved
      Tachikoma.update!(model, Tachikoma.KeyEvent('s'))
      @test getpaper(db, "10.1234/first").is_saved

      Tachikoma.update!(model, Tachikoma.KeyEvent('t'))
      @test length(model.papers) == 1
      Tachikoma.update!(model, Tachikoma.KeyEvent('w'))
      @test length(model.papers) == 1
      Tachikoma.update!(model, Tachikoma.KeyEvent('a'))
      @test length(model.papers) == 2
      Tachikoma.update!(model, Tachikoma.KeyEvent('f'))
      @test only(model.papers).doi == "10.1234/first"
      Tachikoma.update!(model, Tachikoma.KeyEvent('a'))
      targetqje = findfirst(journal -> journal.name == "Quarterly Journal of Economics", model.journals)
      Journalier._selectjournal!(model, targetqje + 1)
      @test only(model.papers).doi == "10.1234/second"
      @test model.journalcounts["quarterly journal of economics"] == 1
      Journalier._selectjournal!(model, 1)

      Tachikoma.update!(model, Tachikoma.KeyEvent('/'))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "Second")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test only(model.papers).doi == "10.1234/second"
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
      @test isempty(model.search)
      @test length(model.papers) == 2

      model.focus = :journals
      targetjournal = findfirst(journal -> journal.name == "Journal of Urban Economics", model.journals)
      Journalier._selectjournal!(model, targetjournal + 1)
      @test only(model.papers).journal == "Journal of Urban Economics"
      Tachikoma.update!(model, Tachikoma.KeyEvent('/'))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "First")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test only(model.papers).doi == "10.1234/first"
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
      @test only(model.papers).journal == "Journal of Urban Economics"
      Tachikoma.update!(model, Tachikoma.KeyEvent(:tab))
      @test model.focus == :papers

      Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
      @test model.mode == :journalname
      addbackend = Tachikoma.TestBackend(100, 30)
      addframe = Tachikoma.Frame(
        addbackend.buf,
        Tachikoma.Rect(1, 1, 100, 30),
        Tachikoma.GraphicsRegion[],
        Tachikoma.PixelSnapshot[]
      )
      Tachikoma.view(model, addframe)
      @test Tachikoma.find_text(addbackend, "Add journal") !== nothing
      Tachikoma.set_string!(addbackend.buf, 20, 17, "underlying text", Tachikoma.tstyle(:text))
      Journalier._renderdialog(model, addframe.area, addbackend.buf)
      @test all(Tachikoma.char_at(addbackend, x, 17) == ' ' for x in 20:81)
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
      @test model.mode == :reader
      Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "New Journal")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "5678-9012")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test any(journal -> journal.name == "New Journal", getjournals(db))
      @test model.journals[model.journalindex - 1].name == "New Journal"
      Tachikoma.update!(model, Tachikoma.KeyEvent('x'))
      Tachikoma.update!(model, Tachikoma.KeyEvent('y'))
      @test !any(journal -> journal.name == "New Journal", getjournals(db))
      @test getpaper(db, "10.1234/first") !== nothing

      Tachikoma.update!(model, Tachikoma.KeyEvent('a'))
      renderbackend = Tachikoma.TestBackend(120, 36)
      frame = Tachikoma.Frame(
        renderbackend.buf,
        Tachikoma.Rect(1, 1, 120, 36),
        Tachikoma.GraphicsRegion[],
        Tachikoma.PixelSnapshot[]
      )
      Tachikoma.view(model, frame)
      @test Tachikoma.find_text(renderbackend, "Today") !== nothing
      @test Tachikoma.find_text(renderbackend, "Journals") !== nothing
      @test Tachikoma.find_text(renderbackend, "JUE") !== nothing
      @test Tachikoma.find_text(renderbackend, "QJE") !== nothing
      @test Tachikoma.find_text(renderbackend, "First Sample Paper") !== nothing
      @test Tachikoma.find_text(renderbackend, "A short abstract") !== nothing
      @test Tachikoma.find_text(renderbackend, "NEW") !== nothing
      @test any(
        Tachikoma.char_at(renderbackend, x, y) == 'S' && Tachikoma.style_at(renderbackend, x, y).italic for
        y in 1:renderbackend.height for x in 1:renderbackend.width
      )
      @test Journalier._journalabbreviation(Journal("12345678", "New Journal of Economics", "1234-5678")) == "NJE"

      Tachikoma.update!(model, Tachikoma.KeyEvent('?'))
      helpbackend = Tachikoma.TestBackend(100, 30)
      helpframe = Tachikoma.Frame(
        helpbackend.buf,
        Tachikoma.Rect(1, 1, 100, 30),
        Tachikoma.GraphicsRegion[],
        Tachikoma.PixelSnapshot[]
      )
      Tachikoma.view(model, helpframe)
      @test Tachikoma.find_text(helpbackend, "Keyboard help") !== nothing
      helpcommands = (
        "t  Show papers added today",
        "w  Show papers added this week",
        "a  Show all papers",
        "f  Show saved papers",
        "Tab  Switch between journals and papers",
        "/  Search papers",
        "Esc  Cancel search or close dialog",
        "r  Toggle read/unread",
        "s  Save/unsave paper",
        "o, Enter  Open selected paper",
        "n  Add a journal",
        "x  Remove selected journal",
        "↑/↓, j/k  Move selection",
        "?  Show this help",
        "q  Quit",
      )
      helpresults = [Tachikoma.find_text(helpbackend, command) for command in helpcommands]
      helprows = [position.y for position in filter(position -> position !== nothing, helpresults)]
      @test length(unique(helprows)) == length(helpcommands)
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))

      Tachikoma.update!(model, Tachikoma.KeyEvent('q'))
      @test Tachikoma.should_quit(model)
    finally
      close(db)
    end
  end
end

@testset "Application paths" begin
  mktempdir() do dir
    configroot = joinpath(dir, "config")
    dataroot = joinpath(dir, "data")
    stateroot = joinpath(dir, "state")
    withenv(
      "XDG_CONFIG_HOME" => configroot,
      "XDG_DATA_HOME" => dataroot,
      "XDG_STATE_HOME" => stateroot
    ) do
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

@testset "Crossref normalization" begin
  record = Dict(
    "DOI" => "10.1234/AbC",
    "title" => ["  Housing <i>and</i> Prices  "],
    "author" => [Dict("given" => "Ada", "family" => "Lovelace"), Dict("name" => "The Research Society")],
    "container-title" => ["Journal of Economics"],
    "abstract" => "<jats:p>Housing&nbsp;<i>costs</i> &amp; supply.</jats:p>",
    "URL" => "https://doi.org/10.1234/AbC",
    "created" => Dict("date-time" => "2024-03-05T11:12:13Z", "date-parts" => [[2024, 3, 5]]),
    "published-online" => Dict("date-parts" => [[2024, 3, 4]]),
    "published-print" => Dict("date-parts" => [[2023, 12, 1]]),
    "issued" => Dict("date-parts" => [[2022]])
  )

  paper = Journalier._normalizecrossref(record, "Fallback Journal")
  @test paper.doi == "10.1234/abc"
  @test paper.title == "Housing and Prices"
  @test paper.authors == "Ada Lovelace; The Research Society"
  @test paper.journal == "Journal of Economics"
  @test paper.abstracttext == "Housing costs & supply."
  @test paper.publishedat == "2024-03-04"
  @test paper.createdat == "2024-03-05 11:12:13"
  @test Journalier._cleanhtml("<i>Inline</i> markup <\\i>") == "Inline markup"
  @test Journalier._crossrefcreated(Dict("created" => Dict("date-parts" => [[2024, 3, 5]]))) == "2024-03-05"
  @test JSON.parse(paper.rawmetadata)["DOI"] == "10.1234/AbC"

  @test Journalier._crossreftext(Dict{String,Any}(), "title"; default="Fallback") == "Fallback"
  @test Journalier._crossreftext(Dict("title" => String[]), "title"; default="Fallback") == "Fallback"
  @test Journalier._crossreftext(Dict("title" => ["  "]), "title"; default="Fallback") == "Fallback"
  @test Journalier._normalizecrossref(Dict("title" => ["No DOI"]), "Fallback Journal") === nothing
  @test Journalier._normalizecrossref(Dict("DOI" => "10.1234/no-url", "URL" => " "), "Fallback Journal").url === nothing
  @test Journalier._crossrefurl("0094-1190", "https://api.crossref.org") ==
        "https://api.crossref.org/journals/0094-1190/works"
  @test Journalier._crossrefquery(12; mailto="reader+test@example.org") == [
    "rows" => "12",
    "sort" => "created",
    "order" => "desc",
    "select" => "DOI,title,author,container-title,abstract,URL,created,published-online,published-print,issued",
    "mailto" => "reader+test@example.org"
  ]
  @test length(INITIAL_JOURNALS) == 6
end

@testset "Crossref collection requests" begin
  item = Dict{String,Any}(
    "DOI" => "10.1234/collector",
    "title" => ["First title"],
    "author" => [Dict("given" => "Ada", "family" => "Lovelace")],
    "container-title" => ["Journal of Urban Economics"],
    "URL" => "https://doi.org/10.1234/collector",
    "created" => Dict("date-time" => "2026-01-03T04:05:06Z", "date-parts" => [[2026, 1, 3]]),
    "published-online" => Dict("date-parts" => [[2026, 1, 2]])
  )
  missingdoi = Dict{String,Any}("title" => ["Record without DOI"])
  items = Ref(Any[item, missingdoi])
  failrequest = Ref(false)
  receivedmailtos = String[]
  server = HTTP.serve!("127.0.0.1", 0; listenany=true) do request
    query = HTTP.queryparams(HTTP.URI(request.target))
    push!(receivedmailtos, get(query, "mailto", ""))
    if failrequest[]
      HTTP.Response(503; body="Crossref unavailable")
    else
      HTTP.Response(200; body=JSON.json(Dict("message" => Dict("items" => items[]))))
    end
  end
  try
    mktempdir() do dir
      db = initializedb(joinpath(dir, "papers.db"))
      try
        journal = only(filter(candidate -> candidate.issn == "0094-1190", getjournals(db)))
        baseurl = "http://127.0.0.1:$(HTTP.port(server))"
        firstsummary = collectjournal(db, journal; recordsperjournal=2, mailto="reader+test@example.org", baseurl)
        @test firstsummary == (journal=journal.name, fetched=2, inserted=1, updated=0, skipped=1)

        paper = only(getpapers(db))
        @test paper.created_at == "2026-01-03 04:05:06"
        @test toggleread(db, paper.doi)
        @test togglesaved(db, paper.doi)
        firstseen = paper.first_seen_at

        updateditem = copy(item)
        updateditem["title"] = ["Updated title"]
        pop!(updateditem, "created")
        items[] = Any[updateditem, missingdoi]
        secondsummary = collectjournal(db, journal; recordsperjournal=2, mailto="reader+test@example.org", baseurl)
        @test secondsummary == (journal=journal.name, fetched=2, inserted=0, updated=1, skipped=1)
        paper = only(getpapers(db))
        @test paper.title == "Updated title"
        @test paper.first_seen_at == firstseen
        @test paper.created_at == "2026-01-03 04:05:06"
        @test paper.is_read
        @test paper.is_saved
        @test length(getpapers(db)) == 1

        failrequest[] = true
        @test_throws Exception collectjournal(
          db,
          journal;
          recordsperjournal=2,
          mailto="reader+test@example.org",
          baseurl
        )
        @test only(getpapers(db)).title == "Updated title"
        @test length(receivedmailtos) >= 3
        @test all(==("reader+test@example.org"), receivedmailtos)
      finally
        close(db)
      end
    end
  finally
    HTTP.forceclose(server)
  end
end

@testset "Paper ordering and schema migration" begin
  mktempdir() do dir
    db = Journalier.SQLite.DB(joinpath(dir, "legacy.db"))
    try
      Journalier.DBInterface.execute(
        db,
        """
        CREATE TABLE papers (
          doi TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          authors TEXT NOT NULL DEFAULT '',
          journal TEXT NOT NULL DEFAULT '',
          abstract TEXT,
          url TEXT,
          published_at TEXT,
          first_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          source TEXT NOT NULL DEFAULT 'crossref',
          raw_metadata TEXT NOT NULL DEFAULT '{}',
          is_read INTEGER NOT NULL DEFAULT 0,
          is_saved INTEGER NOT NULL DEFAULT 0
        )
        """
      )
      Journalier.DBInterface.execute(
        db,
        "INSERT INTO papers (doi, title, first_seen_at) VALUES (?, ?, ?)",
        ("10.1234/first-seen", "First <i>seen</i> first", "2026-01-03 00:00:00")
      )
      initializedb(db)
      @test getpaper(db, "10.1234/first-seen").created_at === nothing
      @test getpaper(db, "10.1234/first-seen").title == "First seen first"

      upsertpaper(db; doi="10.1234/first-seen", title="First seen first", createdat="2025-01-01 00:00:00")
      upsertpaper(db; doi="10.1234/alpha", title="Alpha", createdat="2026-01-03 00:00:00")
      upsertpaper(db; doi="10.1234/beta", title="Beta", createdat="2026-01-03 00:00:00")
      upsertpaper(db; doi="10.1234/older", title="Older created", createdat="2026-01-02 00:00:00")
      Journalier.DBInterface.execute(db, "UPDATE papers SET first_seen_at = ? WHERE doi != ?", ("2026-01-02 00:00:00", "10.1234/first-seen"))

      @test [paper.doi for paper in getpapers(db)] == [
        "10.1234/first-seen",
        "10.1234/alpha",
        "10.1234/beta",
        "10.1234/older"
      ]
    finally
      close(db)
    end
  end
end

@testset "Collector persistence" begin
  mktempdir() do dir
    db = initializedb(joinpath(dir, "papers.db"))
    try
      @test length(getjournals(db)) == 6
      addedjournal = addjournal(db, "Sample Journal", "1234-567x")
      @test addedjournal.issn == "1234-567X"
      @test getjournal(db, addedjournal.id).name == addedjournal.name
      @test getjournal(db, addedjournal.id).issn == addedjournal.issn
      @test removejournal(db, addedjournal.id)
      @test !removejournal(db, addedjournal.id)

      normalized = Journalier._normalizecrossref(
        Dict(
          "DOI" => "10.1234/example",
          "title" => ["Example Paper"],
          "author" => [Dict("given" => "Alex", "family" => "Smith")],
          "published-print" => Dict("date-parts" => [[2025, 8]])
        ),
        "Example Journal"
      )

      first = upsertpaper(
        db;
        doi=normalized.doi,
        title=normalized.title,
        authors=normalized.authors,
        journal=normalized.journal,
        abstracttext=normalized.abstracttext,
        url=normalized.url,
        publishedat=normalized.publishedat,
        rawmetadata=normalized.rawmetadata
      )
      @test first isa Paper
      @test first.published_at == "2025-08"
      @test first.is_read == false
      @test toggleread(db, first.doi) == true
      @test togglesaved(db, first.doi) == true

      second = upsertpaper(db; doi=first.doi, title="Updated title", rawmetadata="{}")
      @test second.title == "Updated title"
      @test second.first_seen_at == first.first_seen_at
      @test second.is_read == true
      @test second.is_saved == true
      @test only(getpapers(db; query="updated")).doi == first.doi

      for journal in getjournals(db)
        @test removejournal(db, journal.id)
      end
      initializedb(db)
      @test isempty(getjournals(db))
    finally
      close(db)
    end
  end
end
