function _fetchconfiguredjournal(issn)
  config = loadconfig()
  contact = strip(_crossrefmailto(config))
  _fetchcrossref(
    issn;
    recordsperjournal=config.recordsperjournal,
    mailto=isempty(contact) ? nothing : contact,
    baseurl="https://api.crossref.org",
    requesttimeout=15,
    retry=false
  )
end

Base.@kwdef mutable struct ReaderModel <: Tachikoma.Model
  db = nothing
  fetchjournal = _fetchconfiguredjournal
  papers::Vector{Paper} = Paper[]
  titles::Dict{String,PreparedTitle} = Dict{String,PreparedTitle}()
  journals::Vector{Journal} = Journal[]
  journalcounts::Dict{String,Int} = Dict{String,Int}()
  papercount::Int = 0
  period::Symbol = :all
  journalindex::Int = 1
  paperindex::Int = 1
  focus::Symbol = :papers
  search::String = ""
  mode::Symbol = :reader
  formname::String = ""
  formacronym::String = ""
  formissn::String = ""
  formpapers = Any[]
  message::String = ""
  quit::Bool = false
end

function ReaderModel(db; fetchjournal=_fetchconfiguredjournal)
  model = ReaderModel(db=db, fetchjournal=fetchjournal)
  _refreshreader!(model)
  model
end

should_quit(model::ReaderModel) = model.quit

function _periodstart(period; localnow=Dates.now(), utcnow=Dates.now(Dates.UTC))
  localday = Date(localnow)
  startday = if period == :today
    localday
  elseif period == :week
    localday - Day(Dates.dayofweek(localday) - 1)
  else
    return nothing
  end
  utcstart = DateTime(startday) - (localnow - utcnow)
  Dates.format(utcstart, dateformat"yyyy-mm-dd HH:MM:SS")
end

function _refreshreader!(model::ReaderModel; preservepaper=nothing, journalissn=nothing)
  selectedissn = journalissn
  if selectedissn === nothing && 1 < model.journalindex <= length(model.journals) + 1
    selectedissn = model.journals[model.journalindex - 1].issn
  end
  model.journals = getjournals(model.db)
  selectedindex =
    selectedissn === nothing ? nothing : findfirst(journal -> journal.issn == selectedissn, model.journals)
  model.journalindex = selectedindex === nothing ? 1 : selectedindex + 1
  selectedjournal = selectedindex === nothing ? nothing : model.journals[selectedindex]
  saved = model.period == :saved ? true : nothing
  firstseenafter = _periodstart(model.period)
  visiblepapers = getpapers(model.db; saved, query=model.search, firstseenafter)
  model.papercount = length(visiblepapers)
  empty!(model.journalcounts)
  for paper in visiblepapers
    paper.journal_issn === nothing && continue
    model.journalcounts[paper.journal_issn] = get(model.journalcounts, paper.journal_issn, 0) + 1
  end
  model.papers =
    selectedjournal === nothing ? visiblepapers :
    filter(paper -> _matchesjournal(paper, selectedjournal), visiblepapers)
  model.titles =
    Dict(paper.doi => _preparedtitle(paper, get(model.titles, paper.doi, nothing)) for paper in model.papers)
  if preservepaper !== nothing
    found = findfirst(paper -> paper.doi == preservepaper, model.papers)
    found === nothing || (model.paperindex = found)
  end
  model.paperindex = clamp(model.paperindex, 1, max(length(model.papers), 1))
  model
end

function _matchesjournal(paper, journal)
  paper.journal_issn == journal.issn
end

function _setperiod!(model::ReaderModel, period)
  model.period = period
  model.paperindex = 1
  _refreshreader!(model)
end

function _selectjournal!(model::ReaderModel, index)
  model.journalindex = clamp(index, 1, length(model.journals) + 1)
  model.paperindex = 1
  _refreshreader!(model)
end

function _currentpaper(model::ReaderModel)
  isempty(model.papers) ? nothing : model.papers[model.paperindex]
end

function _isnew(paper::Paper; now=Dates.now(Dates.UTC))
  firstseen = try
    DateTime(paper.first_seen_at, dateformat"yyyy-mm-dd HH:MM:SS")
  catch
    return false
  end
  firstseen >= now - Day(1)
end
