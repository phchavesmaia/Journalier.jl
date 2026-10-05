_optionaltext(value) = ismissing(value) ? nothing : String(value)

function _paper(row)
  Paper(
    String(row.doi),
    String(row.title),
    String(row.authors),
    String(row.journal),
    _optionaltext(getproperty(row, Symbol("abstract"))),
    _optionaltext(row.url),
    _optionaltext(row.published_at),
    _optionaltext(row.created_at),
    String(row.first_seen_at),
    String(row.source),
    String(row.raw_metadata),
    Bool(row.is_read),
    Bool(row.is_saved),
    _optionaltext(row.journal_issn)
  )
end

"""Insert plain-text paper metadata or refresh it while preserving local state."""
function upsertpaper(
  db;
  doi,
  title,
  authors="",
  journal="",
  journalissn=nothing,
  abstracttext=nothing,
  url=nothing,
  publishedat=nothing,
  createdat=nothing,
  source="crossref",
  rawmetadata="{}"
)
  journalissn = journalissn === nothing ? nothing : _normalizeissn(journalissn)
  DBInterface.execute(
    db,
    """
	INSERT INTO papers (
		doi, title, authors, journal, journal_issn, abstract, url, published_at, created_at, source, raw_metadata
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON CONFLICT(doi) DO UPDATE SET
		title = excluded.title,
		authors = excluded.authors,
		journal = excluded.journal,
		journal_issn = COALESCE(excluded.journal_issn, papers.journal_issn),
		abstract = excluded.abstract,
		url = excluded.url,
		published_at = excluded.published_at,
		created_at = COALESCE(excluded.created_at, papers.created_at),
		source = excluded.source,
		raw_metadata = excluded.raw_metadata
""",
    (doi, title, authors, journal, journalissn, abstracttext, url, publishedat, createdat, source, rawmetadata)
  )
  getpaper(db, doi)
end

"""Return filtered papers by Crossref creation date, first-seen time, then title."""
function getpapers(db; journal=nothing, saved=nothing, query=nothing, firstseenafter=nothing, limit=nothing)
  conditions = String[]
  params = Any[]

  if journal !== nothing
    push!(conditions, "journal = ?")
    push!(params, journal)
  end
  if saved !== nothing
    push!(conditions, "is_saved = ?")
    push!(params, saved ? 1 : 0)
  end
  if query !== nothing && !isempty(strip(query))
    push!(conditions, "(title LIKE ? OR authors LIKE ? OR journal LIKE ? OR abstract LIKE ?)")
    pattern = "%$(strip(query))%"
    append!(params, (pattern, pattern, pattern, pattern))
  end
  if firstseenafter !== nothing
    push!(conditions, "first_seen_at >= ?")
    push!(params, firstseenafter)
  end

  sql = "SELECT * FROM papers"
  isempty(conditions) || (sql *= " WHERE " * join(conditions, " AND "))
  sql *= " ORDER BY created_at DESC, first_seen_at DESC, title COLLATE NOCASE ASC"
  if limit !== nothing
    limit > 0 || throw(ArgumentError("limit must be positive"))
    sql *= " LIMIT ?"
    push!(params, limit)
  end
  Paper[_paper(row) for row in DBInterface.execute(db, sql, Tuple(params))]
end

"""Return one paper by DOI, or `nothing` when it is not in the database."""
function getpaper(db, doi)
  for row in DBInterface.execute(db, "SELECT * FROM papers WHERE doi = ?", (doi,))
    return _paper(row)
  end
  nothing
end

"""Set a paper's read state. Returns the database execution result."""
function markread(db, doi; value=true)
  DBInterface.execute(db, "UPDATE papers SET is_read = ? WHERE doi = ?", (value ? 1 : 0, doi))
end

"""Toggle and return a paper's read state, or `nothing` if the DOI is unknown."""
function toggleread(db, doi)
  DBInterface.execute(db, "UPDATE papers SET is_read = 1 - is_read WHERE doi = ?", (doi,))
  paper = getpaper(db, doi)
  paper === nothing ? nothing : paper.is_read
end

"""Toggle and return a paper's saved state, or `nothing` if the DOI is unknown."""
function togglesaved(db, doi)
  DBInterface.execute(db, "UPDATE papers SET is_saved = 1 - is_saved WHERE doi = ?", (doi,))
  paper = getpaper(db, doi)
  paper === nothing ? nothing : paper.is_saved
end
