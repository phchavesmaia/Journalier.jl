function _normalizeissn(issn)
  compact = uppercase(replace(strip(issn), "-" => ""))
  occursin(r"^[0-9]{7}[0-9X]$", compact) || throw(ArgumentError("invalid ISSN: $issn"))
  compact[1:4] * "-" * compact[5:8]
end

"""Add a journal with its display acronym; duplicate acronyms are allowed and warn by default."""
function addjournal(db, name, acronym, issn; warncollision=true)
  journalname = strip(name)
  isempty(journalname) && throw(ArgumentError("journal name cannot be empty"))
  journalacronym = uppercase(strip(acronym))
  isempty(journalacronym) && throw(ArgumentError("journal acronym cannot be empty"))
  normalizedissn = _normalizeissn(issn)
  collisions = _acronymcollisions(db, journalacronym)
  journal = Journal(normalizedissn, journalname, journalacronym)
  DBInterface.execute(
    db,
    "INSERT INTO journals (issn, name, acronym) VALUES (?, ?, ?)",
    (journal.issn, journal.name, journal.acronym)
  )
  if warncollision && !isempty(collisions)
    @warn "Journal acronym $journalacronym is already used by $(join((journal.name for journal in collisions), ", "))."
  end
  journal
end

function _acronymcollisions(db, acronym)
  normalized = uppercase(strip(acronym))
  filter(journal -> journal.acronym == normalized, getjournals(db))
end

"""Return the configured journals, ordered by name."""
function getjournals(db)
  Journal[
    Journal(row.issn, row.name, row.acronym) for
    row in DBInterface.execute(db, "SELECT issn, name, acronym FROM journals ORDER BY name COLLATE NOCASE")
  ]
end

"""Return the configured journal identified by its ISSN, or nothing."""
function getjournal(db, issn)
  normalizedissn = _normalizeissn(issn)
  for row in DBInterface.execute(db, "SELECT issn, name, acronym FROM journals WHERE issn = ?", (normalizedissn,))
    return Journal(row.issn, row.name, row.acronym)
  end
  nothing
end

"""Remove a journal identified by ISSN without deleting its stored papers."""
function removejournal(db, issn)
  journal = getjournal(db, issn)
  journal === nothing && return false
  DBInterface.execute(db, "DELETE FROM journals WHERE issn = ?", (journal.issn,))
  true
end

"""Return stored paper counts by ISSN; unassigned papers have `issn=nothing`."""
function getjournalcounts(db)
  [
    (issn=_optionaltext(row.journal_issn), papercount=row.paper_count) for row in DBInterface.execute(
      db,
      """
      SELECT journal_issn, COUNT(*) AS paper_count
      FROM papers
      GROUP BY journal_issn
      ORDER BY journal_issn
      """
    )
  ]
end
