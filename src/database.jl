"""Create the initial papers table and indexes in an open SQLite database."""
function initializedb(db)
  existingjournalstable =
    !isempty(collect(DBInterface.execute(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'journals'")))
  DBInterface.execute(
    db,
    """
    	CREATE TABLE IF NOT EXISTS papers (
    		doi TEXT PRIMARY KEY,
    		title TEXT NOT NULL,
    		authors TEXT NOT NULL DEFAULT '',
    		journal TEXT NOT NULL DEFAULT '',
    		abstract TEXT,
		url TEXT,
		published_at TEXT,
		created_at TEXT,
		first_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    		source TEXT NOT NULL DEFAULT 'crossref',
    		raw_metadata TEXT NOT NULL DEFAULT '{}',
    		is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
    		is_saved INTEGER NOT NULL DEFAULT 0 CHECK (is_saved IN (0, 1))
    	)
    """
  )
  papercolumns = Set(String(row.name) for row in DBInterface.execute(db, "PRAGMA table_info(papers)"))
  "created_at" in papercolumns || DBInterface.execute(db, "ALTER TABLE papers ADD COLUMN created_at TEXT")
  DBInterface.execute(
    db,
    """
    CREATE TABLE IF NOT EXISTS journals (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      issn TEXT NOT NULL UNIQUE
    )
    """
  )
  DBInterface.execute(db, "CREATE INDEX IF NOT EXISTS papers_journal_idx ON papers (journal)")
  DBInterface.execute(
    db,
    "CREATE INDEX IF NOT EXISTS papers_order_idx ON papers (first_seen_at DESC, created_at DESC, title COLLATE NOCASE)"
  )
  DBInterface.execute(db, "CREATE INDEX IF NOT EXISTS papers_first_seen_idx ON papers (first_seen_at)")
  if !existingjournalstable
    for journal in INITIAL_JOURNALS
      DBInterface.execute(
        db,
        "INSERT INTO journals (id, name, issn) VALUES (?, ?, ?)",
        (journal.id, journal.name, journal.issn)
      )
    end
  end
  db
end

"""Open `path`, initialize its schema, and return the open SQLite connection."""
function initializedb(path::AbstractString)
  db = SQLite.DB(path)
  try
    initializedb(db)
  catch
    close(db)
    rethrow()
  end
  db
end

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
    Bool(row.is_saved)
  )
end

"""Insert a paper or refresh its metadata while preserving local state."""
function upsertpaper(
  db;
  doi,
  title,
  authors="",
  journal="",
  abstracttext=nothing,
  url=nothing,
  publishedat=nothing,
  createdat=nothing,
  source="crossref",
  rawmetadata="{}"
)
  DBInterface.execute(
    db,
    """
	INSERT INTO papers (
		doi, title, authors, journal, abstract, url, published_at, created_at, source, raw_metadata
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON CONFLICT(doi) DO UPDATE SET
		title = excluded.title,
		authors = excluded.authors,
		journal = excluded.journal,
		abstract = excluded.abstract,
		url = excluded.url,
		published_at = excluded.published_at,
		created_at = COALESCE(excluded.created_at, papers.created_at),
		source = excluded.source,
		raw_metadata = excluded.raw_metadata
""",
	(doi, title, authors, journal, abstracttext, url, publishedat, createdat, source, rawmetadata)
  )
  getpaper(db, doi)
end

"""Return filtered papers by first-seen time, Crossref creation date, then title."""
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
  sql *= " ORDER BY first_seen_at DESC, created_at DESC, title COLLATE NOCASE ASC"
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

function _normalizeissn(issn)
  compact = uppercase(replace(strip(issn), "-" => ""))
  occursin(r"^[0-9]{7}[0-9X]$", compact) || throw(ArgumentError("invalid ISSN: $issn"))
  compact[1:4] * "-" * compact[5:8]
end

"""Add a journal to the persistent collection list."""
function addjournal(db, name, issn)
  journalname = strip(name)
  isempty(journalname) && throw(ArgumentError("journal name cannot be empty"))
  normalizedissn = _normalizeissn(issn)
  journal = Journal(lowercase(replace(normalizedissn, "-" => "")), journalname, normalizedissn)
  DBInterface.execute(
    db,
    "INSERT INTO journals (id, name, issn) VALUES (?, ?, ?)",
    (journal.id, journal.name, journal.issn)
  )
  journal
end

"""Return the configured journals, ordered by name."""
function getjournals(db)
  Journal[
    Journal(row.id, row.name, row.issn) for
    row in DBInterface.execute(db, "SELECT id, name, issn FROM journals ORDER BY name COLLATE NOCASE")
  ]
end

"""Return the configured journal identified by its ID, or nothing."""
function getjournal(db, id)
  for row in DBInterface.execute(db, "SELECT id, name, issn FROM journals WHERE id = ?", (id,))
    return Journal(row.id, row.name, row.issn)
  end
  nothing
end

"""Remove a journal from the collection list without deleting stored papers."""
function removejournal(db, id)
  journal = getjournal(db, id)
  journal === nothing && return false
  DBInterface.execute(db, "DELETE FROM journals WHERE id = ?", (id,))
  true
end

"""Return stored paper counts by Crossref journal title."""
function getjournalcounts(db)
  [
    (journal=row.journal, papercount=row.paper_count) for row in DBInterface.execute(
      db,
      """
      SELECT journal, COUNT(*) AS paper_count
      FROM papers
      GROUP BY journal
      ORDER BY journal COLLATE NOCASE
      """
    )
  ]
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
