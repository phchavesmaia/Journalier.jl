@testset "Paper ordering" begin
  mktempdir() do dir
    db = initializedb(joinpath(dir, "papers.db"))
    try
      upsertpaper(db; doi="10.1234/first-seen", title="First seen first")
      Journalier.DBInterface.execute(
        db,
        "UPDATE papers SET first_seen_at = ? WHERE doi = ?",
        ("2026-01-03 00:00:00", "10.1234/first-seen")
      )
      @test getpaper(db, "10.1234/first-seen").created_at === nothing

      upsertpaper(db; doi="10.1234/first-seen", title="First seen first", createdat="2025-01-01 00:00:00")
      upsertpaper(db; doi="10.1234/alpha", title="Alpha", createdat="2026-01-03 00:00:00")
      upsertpaper(db; doi="10.1234/beta", title="Beta", createdat="2026-01-03 00:00:00")
      upsertpaper(db; doi="10.1234/older", title="Older created", createdat="2026-01-02 00:00:00")
      Journalier.DBInterface.execute(
        db,
        "UPDATE papers SET first_seen_at = ? WHERE doi != ?",
        ("2026-01-02 00:00:00", "10.1234/first-seen")
      )

      expected = ["10.1234/alpha", "10.1234/beta", "10.1234/older", "10.1234/first-seen"]
      @test [paper.doi for paper in getpapers(db)] == expected
      @test only(getpapers(db; limit=1)).doi == "10.1234/alpha"
      @test [paper.doi for paper in Journalier.ReaderModel(db).papers] == expected
      upsertpaper(db; doi="10.1234/unknown-date", title="Unknown Crossref date")
      Journalier.DBInterface.execute(
        db,
        "UPDATE papers SET first_seen_at = ? WHERE doi = ?",
        ("2026-01-04 00:00:00", "10.1234/unknown-date")
      )
      @test last(getpapers(db)).doi == "10.1234/unknown-date"
      @test [paper.doi for paper in getpapers(db; firstseenafter="2026-01-03 00:00:00")] == ["10.1234/first-seen", "10.1234/unknown-date"]
    finally
      close(db)
    end
  end
end

@testset "ISSN counts and acronym collisions" begin
  db = initializedb(Journalier.SQLite.DB())
  try
    firstjournal = addjournal(db, "Same name", "ONE", "1234-5678")
    secondjournal = addjournal(db, "Same name", "TWO", "5678-9012")
    upsertpaper(db; doi="10.example/one", title="One", journal=firstjournal.name, journalissn=firstjournal.issn)
    upsertpaper(db; doi="10.example/two", title="Two", journal=secondjournal.name, journalissn=secondjournal.issn)
    upsertpaper(db; doi="10.example/alias", title="Alias", journal="Different title", journalissn=firstjournal.issn)
    upsertpaper(db; doi="10.example/unassigned", title="Unassigned")
    @test getjournalcounts(db) ==
          [(issn=nothing, papercount=1), (issn="1234-5678", papercount=2), (issn="5678-9012", papercount=1)]
    @test_logs (:warn, r"acronym ONE is already used by Same name") addjournal(db, "Collision", " one ", "9876-5432")
    @test getjournal(db, "9876-5432").acronym == "ONE"
    @test_throws Exception addjournal(db, "Duplicate ISSN", "OTHER", "12345678")
    @test length(Journalier._acronymcollisions(db, "one")) == 2
  finally
    close(db)
  end
end

@testset "Collector persistence" begin
  mktempdir() do dir
    db = initializedb(joinpath(dir, "papers.db"))
    try
      @test length(getjournals(db)) == 6
      addedjournal = addjournal(db, "Sample Journal", "SJ", "1234-567x")
      @test addedjournal.issn == "1234-567X"
      @test addedjournal.acronym == "SJ"
      @test getjournal(db, addedjournal.issn).name == addedjournal.name
      @test getjournal(db, addedjournal.issn).acronym == addedjournal.acronym
      @test removejournal(db, addedjournal.issn)
      @test !removejournal(db, addedjournal.issn)

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
        titlehtml=normalized.titlehtml,
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
        @test removejournal(db, journal.issn)
      end
      initializedb(db)
      @test isempty(getjournals(db))
    finally
      close(db)
    end
  end
end

@testset "Plain-text persistence" begin
  mktempdir() do dir
    path = joinpath(dir, "papers.db")
    db = initializedb(path)
    try
      examples = (
        ("When x &lt; y &gt; z", "When x < y > z"),
        ("A &amp;lt; B", "A &lt; B"),
        ("A &lt;i&gt;literal&lt;/i&gt;", "A <i>literal</i>")
      )
      for (index, (rawtext, expected)) in enumerate(examples)
        normalized = Journalier._normalizecrossref(
          Dict(
            "DOI" => "10.1234/text-$index",
            "title" => [rawtext],
            "abstract" => rawtext,
            "author" => [Dict("name" => rawtext)]
          ),
          "Example Journal"
        )
        paper = upsertpaper(db; normalized...)
        @test paper.title == expected
        @test paper.abstract_text == expected
        @test paper.authors == expected
        @test getpaper(db, paper.doi).title == expected
        segments = Journalier._inlinehtmlsegments(Journalier._rawpapertitle(paper))
        @test join(first.(segments)) == expected
      end
      paper = upsertpaper(db; doi="10.1234/plain", title="When x < y > z", abstracttext="A &lt; B")
      @test paper.title == "When x < y > z"
      @test paper.abstract_text == "A &lt; B"
      @test join(first.(Journalier._inlinehtmlsegments(Journalier._rawpapertitle(paper)))) == paper.title
      initializedb(db)
      @test getpaper(db, "10.1234/text-2").title == "A &lt; B"
    finally
      close(db)
    end
    db = initializedb(path)
    try
      @test getpaper(db, "10.1234/text-1").title == "When x < y > z"
      @test getpaper(db, "10.1234/text-2").abstract_text == "A &lt; B"
    finally
      close(db)
    end
  end
end

@testset "Source metadata lookup" begin
  mktempdir() do dir
    path = joinpath(dir, "papers.db")
    db = initializedb(path)
    metadata = JSON.json(Dict("title" => ["Unrelated source title"], "payload" => repeat("x", 100_000)))
    try
      upsertpaper(
        db;
        doi="10.1234/source",
        title="A formatted title",
        titlehtml="A <i>formatted</i> title",
        rawmetadata=metadata
      )
      paper = only(getpapers(db))
      @test !hasproperty(paper, :raw_metadata)
      @test paper.title_html == "A <i>formatted</i> title"
      @test getrawmetadata(db, paper.doi) == metadata
      @test getrawmetadata(db, "10.1234/unknown") === nothing
      model = Journalier.ReaderModel(db)
      @test model.titles[paper.doi].segments == [("A ", false), ("formatted", true), (" title", false)]
      @test !hasproperty(model.titles[paper.doi], :rawmetadata)
      @test Base.summarysize(model) < sizeof(metadata)
      second = upsertpaper(db; doi=paper.doi, title="Plain replacement", rawmetadata="{}")
      @test second.title_html === nothing
      @test getrawmetadata(db, paper.doi) == "{}"
    finally
      close(db)
    end
    db = initializedb(path)
    try
      @test getpaper(db, "10.1234/source").title == "Plain replacement"
      @test getrawmetadata(db, "10.1234/source") == "{}"
    finally
      close(db)
    end
  end
end

@testset "Unsupported database schema" begin
  mktempdir() do dir
    path = joinpath(dir, "unsupported.db")
    db = Journalier.SQLite.DB(path)
    try
      Journalier.DBInterface.execute(db, "CREATE TABLE papers (doi TEXT PRIMARY KEY, title TEXT NOT NULL)")
      Journalier.DBInterface.execute(db, "INSERT INTO papers VALUES ('10.1234/existing', 'Keep this record')")
      @test_throws ArgumentError initializedb(db)
      counts = [row.count for row in Journalier.DBInterface.execute(db, "SELECT COUNT(*) AS count FROM papers")]
      @test only(counts) == 1
      @test_throws ArgumentError initializedb(path)
    finally
      close(db)
    end
  end
  db = initializedb(Journalier.SQLite.DB())
  try
    Journalier.DBInterface.execute(db, "ALTER TABLE papers DROP COLUMN title_html")
    @test_throws ArgumentError initializedb(db)
  finally
    close(db)
  end
end
