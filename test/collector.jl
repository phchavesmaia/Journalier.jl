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
  @test paper.titlehtml == "Housing <i>and</i> Prices"
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
        journal = addjournal(db, "Urban economics", "1234-5678")
        baseurl = "http://127.0.0.1:$(HTTP.port(server))"
        firstsummary = collectjournal(db, journal; recordsperjournal=2, mailto="reader+test@example.org", baseurl)
        @test firstsummary == (journal=journal.name, fetched=2, inserted=1, updated=0, skipped=1)

        paper = only(getpapers(db))
        @test paper.journal_issn == journal.issn
        @test paper.title_html == "First title"
        @test JSON.parse(getrawmetadata(db, paper.doi))["title"] == ["First title"]
        model = Journalier.ReaderModel(db)
        Journalier._selectjournal!(model, findfirst(candidate -> candidate.id == journal.id, model.journals) + 1)
        @test only(model.papers).doi == paper.doi
        @test model.journalcounts[journal.issn] == 1
        officialindex = findfirst(candidate -> candidate.issn == "0094-1190", model.journals)
        Journalier._selectjournal!(model, officialindex + 1)
        @test isempty(model.papers)
        @test removejournal(db, journal.id)
        journal = addjournal(db, "Economics alias", journal.issn)
        Journalier._refreshreader!(model; journalid=journal.id)
        @test only(model.papers).doi == paper.doi
        duplicate = addjournal(db, journal.name, "5678-9012")
        Journalier._refreshreader!(model)
        @test model.journals[model.journalindex - 1].id == journal.id
        @test removejournal(db, duplicate.id)
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
        @test paper.title_html == "Updated title"
        @test paper.first_seen_at == firstseen
        @test paper.created_at == "2026-01-03 04:05:06"
        @test paper.is_read
        @test paper.is_saved
        @test paper.journal_issn == journal.issn
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
