@testset "Prepared reader titles" begin
  db = initializedb(Journalier.SQLite.DB())
  try
    doi = "10.1234/formatted"
    title = "A café & B"
    metadata = JSON.json(Dict("title" => ["A <i>café</i> &amp; B"]))
    upsertpaper(db; doi, title, titlehtml="A <i>café</i> &amp; B", rawmetadata=metadata)
    upsertpaper(db; doi="10.1234/plain", title="x < y & z", rawmetadata="invalid JSON")
    model = Journalier.ReaderModel(db)
    segments = model.titles[doi].segments
    @test segments == [("A ", false), ("café", true), (" & B", false)]
    @test model.titles["10.1234/plain"].segments == [("x < y & z", false)]

    for (width, height) in ((100, 30), (120, 36))
      backend = Tachikoma.TestBackend(width, height)
      frame = Tachikoma.Frame(
        backend.buf,
        Tachikoma.Rect(1, 1, width, height),
        Tachikoma.GraphicsRegion[],
        Tachikoma.PixelSnapshot[]
      )
      Tachikoma.view(model, frame)
      @test Tachikoma.find_text(backend, title) !== nothing
      @test any(
        Tachikoma.char_at(backend, x, y) == 'é' && Tachikoma.style_at(backend, x, y).italic for y in 1:height for
        x in 1:width
      )
      @test model.titles[doi].segments === segments
    end

    toggleread(db, doi)
    Journalier._refreshreader!(model)
    @test model.titles[doi].segments === segments
    upsertpaper(db; doi, title, titlehtml="A <i>café</i> &amp; B", rawmetadata="changed source JSON")
    Journalier._refreshreader!(model)
    @test model.titles[doi].segments === segments
    upsertpaper(db; doi, title, titlehtml="<em>A café</em> &amp; B", rawmetadata=metadata)
    Journalier._refreshreader!(model)
    @test model.titles[doi].segments !== segments
    @test model.titles[doi].segments == [("A café", true), (" & B", false)]

    upsertpaper(db; doi="10.1234/plain", title="Changed <literal> &amp; text", rawmetadata="invalid JSON")
    Journalier._refreshreader!(model)
    @test join(first.(model.titles["10.1234/plain"].segments)) == "Changed <literal> &amp; text"
    model.search = "café"
    Journalier._refreshreader!(model)
    @test Set(keys(model.titles)) == Set([doi])
    model.search = "no matching title"
    Journalier._refreshreader!(model)
    @test isempty(model.titles)
    model.search = ""
    Journalier._refreshreader!(model)
    @test length(model.titles) == length(model.papers) == 2
    @test model.titles[doi].segments == [("A café", true), (" & B", false)]
  finally
    close(db)
  end
end

@testset "Journal collection staging and rollback" begin
  db = initializedb(Journalier.SQLite.DB())
  records = Any[
    Dict("DOI" => "10.example/existing", "title" => ["Updated"], "container-title" => ["New Journal"]),
    Dict("DOI" => "10.example/bad", "author" => "invalid")
  ]
  try
    upsertpaper(db; doi="10.example/existing", title="Original")
    model = Journalier.ReaderModel(db; fetchjournal=issn -> records)
    for badresponse in (Any[], Any[Dict("DOI" => "10.example/unnamed")])
      model.fetchjournal = issn -> badresponse
      Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
      foreach(c -> Tachikoma.update!(model, Tachikoma.KeyEvent(c)), "12345678")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test model.mode == :journalissn
      @test occursin("no papers with a journal name", model.message)
      @test getjournal(db, "1234-5678") === nothing
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
    end
    model.fetchjournal = issn -> records
    Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
    foreach(c -> Tachikoma.update!(model, Tachikoma.KeyEvent(c)), "12345678")
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
    @test isempty(model.formpapers)
    @test getjournal(db, "1234-5678") === nothing
    @test getpaper(db, "10.example/existing").title == "Original"
    Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
    foreach(c -> Tachikoma.update!(model, Tachikoma.KeyEvent(c)), "12345678")
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    foreach(c -> Tachikoma.update!(model, Tachikoma.KeyEvent(c)), "NJ")
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test model.mode == :journalacronym
    @test getjournal(db, "1234-5678") === nothing
    @test getpaper(db, "10.example/existing").title == "Original"
    @test getpaper(db, "10.example/bad") === nothing
    @test occursin("author field must be an array", model.message)
    pop!(records)
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test model.mode == :reader
    @test getjournal(db, "1234-5678").name == "New Journal"
    @test only(model.papers).title == "Updated"
  finally
    close(db)
  end
end

@testset "ISSN lookup addition and retry" begin
  db = initializedb(Journalier.SQLite.DB())
  calls = String[]
  fail = Ref(true)
  lookup =
    issn -> begin
      push!(calls, issn)
      fail[] && error("Lookup service unavailable")
      [Dict("DOI" => "10.example/resolved", "title" => ["Resolved Paper"], "container-title" => ["Resolved Journal"])]
    end
  try
    model = Journalier.ReaderModel(db; fetchjournal=lookup)
    Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
    @test model.mode == :journalissn
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test isempty(calls)
    for character in "12345678"
      Tachikoma.update!(model, Tachikoma.KeyEvent(character))
    end
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test model.mode == :journalissn
    @test occursin("Lookup service unavailable", model.message)
    @test getjournal(db, "1234-5678") === nothing
    fail[] = false
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test model.mode == :journalacronym
    @test model.formissn == "1234-5678"
    @test model.formname == "Resolved Journal"
    backend = Tachikoma.TestBackend(100, 30)
    frame =
      Tachikoma.Frame(backend.buf, Tachikoma.Rect(1, 1, 100, 30), Tachikoma.GraphicsRegion[], Tachikoma.PixelSnapshot[])
    Tachikoma.view(model, frame)
    @test Tachikoma.find_text(backend, "Resolved Journal") !== nothing
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test model.mode == :journalacronym
    for character in "RJ"
      Tachikoma.update!(model, Tachikoma.KeyEvent(character))
    end
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test getjournal(db, "1234-5678").name == "Resolved Journal"
    @test getjournal(db, "1234-5678").acronym == "RJ"
    @test model.journals[model.journalindex - 1].issn == "1234-5678"
    @test calls == ["1234-5678", "1234-5678"]
    @test only(model.papers).doi == "10.example/resolved"
    Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
    for character in "12345678"
      Tachikoma.update!(model, Tachikoma.KeyEvent(character))
    end
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test occursin("already configured", model.message)
    @test length(calls) == 2
    Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
    @test model.mode == :reader
    @test model.formissn == model.formname == model.formacronym == ""
  finally
    close(db)
  end
end

@testset "Acronym display and collision warning" begin
  db = initializedb(Journalier.SQLite.DB())
  try
    model = Journalier.ReaderModel(
      db;
      fetchjournal=issn -> [Dict("DOI" => "10.example/another", "container-title" => ["Another Urban Journal"])]
    )
    Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
    for character in "1234-5678"
      Tachikoma.update!(model, Tachikoma.KeyEvent(character))
    end
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    for character in "jue"
      Tachikoma.update!(model, Tachikoma.KeyEvent(character))
    end
    @test model.mode == :journalacronym
    @test occursin("Warning: acronym already used", model.message)
    Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
    @test model.mode == :reader
    @test getjournal(db, "1234-5678").acronym == "JUE"
    @test occursin("Warning: acronym JUE is already in use", model.message)

    for (index, acronym) in enumerate(("LONGJOURNALACRONYM", repeat("界", 12)))
      journal = addjournal(db, "Long acronym $index", acronym, lpad(string(index), 8, '0'))
      Journalier._refreshreader!(model; journalissn=journal.issn)
      model.journalcounts[journal.issn] = 1234
      for width in (16, 10)
        backend = Tachikoma.TestBackend(width, 1)
        Journalier._renderjournals(model, Tachikoma.Rect(1, 1, width, 1), backend.buf)
        @test Tachikoma.find_text(backend, "1234") !== nothing
        @test Tachikoma.find_text(backend, "…") !== nothing
      end
    end
    @test Journalier._fitlabel("界界界", 4) == "界…"
    @test Journalier._fitlabel("ABC", 1) == "…"
    @test Journalier._fitlabel("ABC", 0) == ""
  finally
    close(db)
  end
end

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
        journalissn="0094-1190",
        abstracttext="A short abstract for the first paper.",
        url="https://doi.org/10.1234/first",
        titlehtml="First\n                    <i>Sample</i> Paper",
        rawmetadata=JSON.json(Dict("title" => ["First\n                    <i>Sample</i> Paper"]))
      )
      upsertpaper(
        db;
        doi="10.1234/second",
        title="Second Older Paper",
        authors="Grace Hopper",
        journal="The Quarterly Journal of Economics",
        journalissn="0033-5533",
        abstracttext="An older paper abstract."
      )
      Journalier.DBInterface.execute(db, "UPDATE papers SET first_seen_at = ? WHERE doi = ?", (recent, "10.1234/first"))
      Journalier.DBInterface.execute(db, "UPDATE papers SET first_seen_at = ? WHERE doi = ?", (old, "10.1234/second"))
      togglesaved(db, "10.1234/first")

      model = Journalier.ReaderModel(db)
      @test length(model.papers) == 2
      @test model.journalindex == 1
      @test model.journalcounts["0033-5533"] == 1
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

      Tachikoma.update!(model, Tachikoma.KeyEvent('1'))
      @test length(model.papers) == 1
      Tachikoma.update!(model, Tachikoma.KeyEvent('2'))
      @test length(model.papers) == 1
      Tachikoma.update!(model, Tachikoma.KeyEvent('3'))
      @test length(model.papers) == 2
      Tachikoma.update!(model, Tachikoma.KeyEvent('4'))
      @test only(model.papers).doi == "10.1234/first"
      Tachikoma.update!(model, Tachikoma.KeyEvent('3'))
      targetqje = findfirst(journal -> journal.name == "Quarterly Journal of Economics", model.journals)
      Journalier._selectjournal!(model, targetqje + 1)
      @test only(model.papers).doi == "10.1234/second"
      @test model.journalcounts["0033-5533"] == 1
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
      @test model.mode == :journalissn
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
      model.fetchjournal = issn -> [Dict("DOI" => "10.example/new", "container-title" => ["New Journal"])]
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "5678-9012")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "NJ")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test any(journal -> journal.name == "New Journal", getjournals(db))
      @test getjournal(db, "5678-9012").acronym == "NJ"
      @test model.journals[model.journalindex - 1].name == "New Journal"
      Tachikoma.update!(model, Tachikoma.KeyEvent('x'))
      Tachikoma.update!(model, Tachikoma.KeyEvent('y'))
      @test !any(journal -> journal.name == "New Journal", getjournals(db))
      @test getpaper(db, "10.1234/first") !== nothing
      @test getpaper(db, "10.example/new") !== nothing

      Tachikoma.update!(model, Tachikoma.KeyEvent('3'))
      Journalier._refreshreader!(model; preservepaper="10.1234/first")
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
      @test INITIAL_JOURNALS[1].acronym == "JUE"

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
        "1  Show papers added today",
        "2  Show papers added this week",
        "3  Show all papers",
        "4  Show saved papers",
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
        "q  Quit"
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

@testset "Journal identity" begin
  db = initializedb(Journalier.SQLite.DB())
  try
    upsertpaper(db; doi="10.1234/unassigned", title="Unassigned paper", journal="Journal of Urban Economics")
    model = Journalier.ReaderModel(db)
    @test model.papercount == 1
    @test length(model.papers) == 1
    journalindex = findfirst(journal -> journal.issn == "0094-1190", model.journals)
    Journalier._selectjournal!(model, journalindex + 1)
    @test isempty(model.papers)
    @test isempty(model.journalcounts)
    @test model.papercount == 1
  finally
    close(db)
  end
end

@testset "Journal sidebar scrolling" begin
  db = initializedb(Journalier.SQLite.DB())
  try
    for index in 1:20
      addjournal(db, "Example $index", "E$index", lpad(string(index), 8, '0'))
    end
    addjournal(db, "Zebra Quartz", "ZQ", "9876-5432")
    model = Journalier.ReaderModel(db)
    model.focus = :journals
    for height in (1, 3, 8)
      Journalier._selectjournal!(model, 1)
      for direction in (:down, :up)
        for step in eachindex(model.journals)
          Tachikoma.update!(model, Tachikoma.KeyEvent(direction))
          backend = Tachikoma.TestBackend(30, height)
          area = Tachikoma.Rect(1, 1, 30, height)
          Journalier._renderjournals(model, area, backend.buf)
          label = if model.journalindex == 1
            "All  0"
          else
            journal = model.journals[model.journalindex - 1]
            "▸ $(journal.acronym)  0"
          end
          @test Tachikoma.find_text(backend, label) !== nothing
        end
      end
      @test model.journalindex == 1
    end
    backend = Tachikoma.TestBackend(30, 1)
    Journalier._renderjournals(model, Tachikoma.Rect(1, 1, 30, 0), backend.buf)
    @test strip(Tachikoma.row_text(backend, 1)) == ""
  finally
    close(db)
  end
end
