"""Fetch and store recent Crossref works for one journal."""
function collectjournal(
  db,
  journal::Journal;
  recordsperjournal=100,
  mailto=get(ENV, "CROSSREF_MAILTO", ""),
  baseurl="https://api.crossref.org"
)
  contact = isempty(strip(mailto)) ? nothing : strip(mailto)
  items = _fetchcrossref(journal.issn; recordsperjournal, mailto=contact, baseurl)
  collectjournal(db, journal, items)
end

"""Store already-fetched Crossref works for a journal without another request."""
function collectjournal(db, journal::Journal, items)
  inserted = 0
  updated = 0
  skipped = 0
  for record in items
    paper = _normalizecrossref(record, journal.name)
    if paper === nothing
      skipped += 1
      continue
    end
    existing = getpaper(db, paper.doi)
    upsertpaper(
      db;
      doi=paper.doi,
      title=paper.title,
      titlehtml=paper.titlehtml,
      authors=paper.authors,
      journal=paper.journal,
      journalissn=journal.issn,
      abstracttext=paper.abstracttext,
      url=paper.url,
      publishedat=paper.publishedat,
      createdat=paper.createdat,
      source="crossref",
      rawmetadata=paper.rawmetadata
    )
    existing === nothing ? (inserted += 1) : (updated += 1)
  end
  (journal=journal.name, fetched=length(items), inserted, updated, skipped)
end

"""Fetch and store recent Crossref works for each supplied journal."""
function collectpapers(
  db,
  journals=getjournals(db);
  recordsperjournal=100,
  mailto=get(ENV, "CROSSREF_MAILTO", ""),
  baseurl="https://api.crossref.org"
)
  summaries = NamedTuple[]
  for journal in journals
    push!(summaries, collectjournal(db, journal; recordsperjournal, mailto, baseurl))
  end
  summaries
end
