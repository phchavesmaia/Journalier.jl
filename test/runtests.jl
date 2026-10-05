using Journalier
using HTTP
using JSON
using Test

@testset "Crossref normalization" begin
  record = Dict(
    "DOI" => "10.1234/AbC",
    "title" => ["  Housing and Prices  "],
    "author" => [Dict("given" => "Ada", "family" => "Lovelace"), Dict("name" => "The Research Society")],
    "container-title" => ["Journal of Economics"],
    "abstract" => "<jats:p>Housing&nbsp;costs &amp; supply.</jats:p>",
    "URL" => "https://doi.org/10.1234/AbC",
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
    "sort" => "updated",
    "order" => "desc",
    "select" => "DOI,title,author,container-title,abstract,URL,published-online,published-print,issued",
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
        @test toggleread(db, paper.doi)
        @test togglesaved(db, paper.doi)
        firstseen = paper.first_seen_at

        updateditem = copy(item)
        updateditem["title"] = ["Updated title"]
        items[] = Any[updateditem, missingdoi]
        secondsummary = collectjournal(db, journal; recordsperjournal=2, mailto="reader+test@example.org", baseurl)
        @test secondsummary == (journal=journal.name, fetched=2, inserted=0, updated=1, skipped=1)
        paper = only(getpapers(db))
        @test paper.title == "Updated title"
        @test paper.first_seen_at == firstseen
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
