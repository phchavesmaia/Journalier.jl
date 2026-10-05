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

      @test [paper.doi for paper in getpapers(db)] == ["10.1234/first-seen", "10.1234/alpha", "10.1234/beta", "10.1234/older"]
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
end
