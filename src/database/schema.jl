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
        title_html TEXT,
    		authors TEXT NOT NULL DEFAULT '',
    		journal TEXT NOT NULL DEFAULT '',
    		abstract TEXT,
        url TEXT,
        published_at TEXT,
        created_at TEXT,
        journal_issn TEXT,
        first_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    		source TEXT NOT NULL DEFAULT 'crossref',
    		raw_metadata TEXT NOT NULL DEFAULT '{}',
    		is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
    		is_saved INTEGER NOT NULL DEFAULT 0 CHECK (is_saved IN (0, 1))
    	)
    """
  )
  papercolumns = Set(String(row.name) for row in DBInterface.execute(db, "PRAGMA table_info(papers)"))
  expectedcolumns = Set((
    "doi",
    "title",
    "title_html",
    "authors",
    "journal",
    "abstract",
    "url",
    "published_at",
    "created_at",
    "journal_issn",
    "first_seen_at",
    "source",
    "raw_metadata",
    "is_read",
    "is_saved"
  ))
  papercolumns == expectedcolumns ||
    throw(ArgumentError("unsupported papers schema; create a new database for this beta version"))
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
  DBInterface.execute(db, "DROP INDEX IF EXISTS papers_order_idx")
  DBInterface.execute(
    db,
    "CREATE INDEX IF NOT EXISTS papers_created_order_idx ON papers (created_at DESC, first_seen_at DESC, title COLLATE NOCASE)"
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
