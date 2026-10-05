function _crossrefurl(issn, baseurl)
  occursin(r"^[0-9Xx-]+$", issn) || throw(ArgumentError("invalid ISSN: $issn"))
  "$(rstrip(baseurl, '/'))/journals/$issn/works"
end

function _crossrefquery(recordsperjournal; mailto=nothing)
  1 <= recordsperjournal <= 1000 || throw(ArgumentError("recordsperjournal must be between 1 and 1000"))
  query = Pair{String,String}[
    "rows" => string(recordsperjournal),
    "sort" => "created",
    "order" => "desc",
    "select" => "DOI,title,author,container-title,abstract,URL,published-online,published-print,issued"
  ]
  mailto === nothing || push!(query, "mailto" => mailto)
  query
end

function _crossreftext(record, key; default="")
  value = get(record, key, nothing)
  value isa AbstractVector && (value = isempty(value) ? nothing : first(value))
  value === nothing && return default
  text = strip(string(value))
  ifelse(isempty(text), default, text)
end

function _crossrefauthors(record)
  people = get(record, "author", nothing)
  people === nothing && return ""
  people isa AbstractVector || throw(ArgumentError("Crossref author field must be an array"))
  names = String[]
  for person in people
    person isa AbstractDict || throw(ArgumentError("Crossref author entries must be objects"))
    name = strip(string(get(person, "name", "")))
    if isempty(name)
      given = strip(string(get(person, "given", "")))
      family = strip(string(get(person, "family", "")))
      name = join(filter(part -> !isempty(part), (given, family)), " ")
    end
    isempty(name) || push!(names, name)
  end
  join(names, "; ")
end

"""Return a Crossref publication date, preferring online, print, then issued."""
function _crossrefdate(record)
  for key in ("published-online", "published-print", "issued")
    date = get(record, key, nothing)
    date isa AbstractDict || continue
    dateparts = get(date, "date-parts", nothing)
    dateparts isa AbstractVector && !isempty(dateparts) || continue
    parts = first(dateparts)
    parts isa AbstractVector && !isempty(parts) || continue
    values = string.(parts)
    values[1] = lpad(values[1], 4, '0')
    for index in 2:length(values)
      values[index] = lpad(values[index], 2, '0')
    end
    return join(values, "-")
  end
  nothing
end

function _cleanabstract(value)
  value === nothing && return nothing
  text = replace(string(value), r"<[^>]*>" => " ")
  for (entity, character) in
      (("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "))
    text = replace(text, entity => character)
  end
  text = replace(text, "&amp;" => "&")
  text = join(split(strip(text)), " ")
  isempty(text) ? nothing : text
end

"""Convert a Crossref work record to Journalier fields, or `nothing` without a DOI."""
function _normalizecrossref(record, journalname)
  record isa AbstractDict || throw(ArgumentError("Crossref work record must be an object"))
  doi = lowercase(strip(string(get(record, "DOI", ""))))
  isempty(doi) && return nothing
  title = _crossreftext(record, "title")
  journal = _crossreftext(record, "container-title"; default=journalname)
  abstract = _cleanabstract(get(record, "abstract", nothing))
  url = _crossreftext(record, "URL"; default=nothing)
  (
    doi=doi,
    title=title,
    authors=_crossrefauthors(record),
    journal=journal,
    abstracttext=abstract,
    url=url,
    publishedat=_crossrefdate(record),
    rawmetadata=JSON.json(record)
  )
end

"""Fetch Crossref work records for one ISSN."""
function _fetchcrossref(issn; recordsperjournal, mailto=nothing, baseurl)
  url = _crossrefurl(issn, baseurl)
  useragent = mailto === nothing ? "Journalier/0.1.0" : "Journalier/0.1.0 (mailto:$mailto)"
  response = HTTP.get(url, ["User-Agent" => useragent]; query=_crossrefquery(recordsperjournal; mailto))
  response.status == 200 || error("Crossref request for ISSN $issn returned HTTP $(response.status)")
  payload = JSON.parse(String(response.body))
  message = get(payload, "message", nothing)
  message isa AbstractDict || error("Crossref response for ISSN $issn is missing its message object")
  items = get(message, "items", nothing)
  items isa AbstractVector || error("Crossref response for ISSN $issn is missing its items array")
  items
end

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
      authors=paper.authors,
      journal=paper.journal,
      abstracttext=paper.abstracttext,
      url=paper.url,
      publishedat=paper.publishedat,
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
