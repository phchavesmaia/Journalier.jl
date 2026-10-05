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
