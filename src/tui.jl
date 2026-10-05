Base.@kwdef mutable struct ReaderModel <: Tachikoma.Model
  db = nothing
  papers::Vector{Paper} = Paper[]
  journals::Vector{Journal} = Journal[]
  journalcounts::Dict{String,Int} = Dict{String,Int}()
  period::Symbol = :all
  journalindex::Int = 1
  paperindex::Int = 1
  focus::Symbol = :papers
  search::String = ""
  mode::Symbol = :reader
  formname::String = ""
  formissn::String = ""
  message::String = ""
  quit::Bool = false
end

function ReaderModel(db)
  model = ReaderModel(db=db)
  _refreshreader!(model)
  model
end

should_quit(model::ReaderModel) = model.quit

_journalkey(name) = replace(lowercase(strip(name)), r"^the\s+" => "")

function _journalabbreviation(journal::Journal)
  all(isletter, journal.id) && return uppercase(journal.id)
  ignored = ("a", "an", "and", "for", "in", "of", "on", "the", "to", "with")
  words = [join(filter(isletter, word)) for word in split(journal.name)]
  words = filter(word -> !isempty(word) && !(lowercase(word) in ignored), words)
  isempty(words) ? "?" : uppercase(join(first(word) for word in words))
end

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

function _refreshreader!(model::ReaderModel; preservepaper=nothing, journalname=nothing)
  selectedjournal = journalname
  if selectedjournal === nothing && 1 < model.journalindex <= length(model.journals) + 1
    selectedjournal = model.journals[model.journalindex - 1].name
  end
  model.journals = getjournals(model.db)
  selectedindex = selectedjournal === nothing ? nothing : findfirst(journal -> journal.name == selectedjournal, model.journals)
  model.journalindex = selectedindex === nothing ? 1 : selectedindex + 1
  saved = model.period == :saved ? true : nothing
  firstseenafter = _periodstart(model.period)
  visiblepapers = getpapers(model.db; saved, query=model.search, firstseenafter)
  empty!(model.journalcounts)
  for paper in visiblepapers
    journalkey = _journalkey(paper.journal)
    model.journalcounts[journalkey] = get(model.journalcounts, journalkey, 0) + 1
  end
  selectedkey = selectedjournal === nothing ? nothing : _journalkey(selectedjournal)
  model.papers = selectedkey === nothing ? visiblepapers : filter(paper -> _journalkey(paper.journal) == selectedkey, visiblepapers)
  if preservepaper !== nothing
    found = findfirst(paper -> paper.doi == preservepaper, model.papers)
    found === nothing || (model.paperindex = found)
  end
  model.paperindex = clamp(model.paperindex, 1, max(length(model.papers), 1))
  model
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

_ischar(event, character) = event.key == :char && event.char == character

function _addjournalkey!(model::ReaderModel, event)
  if event.key in (:escape, :ctrl_c)
    model.mode = :reader
    model.formname = ""
    model.formissn = ""
    model.message = "Journal addition cancelled."
  elseif event.key == :backspace
    if model.mode == :journalname
      isempty(model.formname) || (model.formname = chop(model.formname))
    else
      isempty(model.formissn) || (model.formissn = chop(model.formissn))
    end
  elseif event.key == :enter
    if model.mode == :journalname
      if isempty(strip(model.formname))
        model.message = "Enter a journal name."
      else
        model.mode = :journalissn
        model.message = "Enter the journal ISSN."
      end
    else
      try
        journal = addjournal(model.db, model.formname, model.formissn)
        model.mode = :reader
        model.formname = ""
        model.formissn = ""
        _refreshreader!(model; journalname=journal.name)
        model.message = "Added $(journal.name)."
      catch error
        model.message = sprint(showerror, error)
      end
    end
  elseif event.key == :char && isprint(event.char)
    if model.mode == :journalname
      model.formname *= string(event.char)
    else
      model.formissn *= string(event.char)
    end
  end
end

function _removejournalkey!(model::ReaderModel, event)
  if event.key in (:escape, :ctrl_c) || _ischar(event, 'n')
    model.mode = :reader
    model.message = "Journal removal cancelled."
  elseif _ischar(event, 'y') || event.key == :enter
    journal = model.journals[model.journalindex - 1]
    removejournal(model.db, journal.id)
    model.journalindex = 1
    model.mode = :reader
    _refreshreader!(model)
    model.message = "Removed $(journal.name); stored papers were kept."
  end
end

function _searchkey!(model::ReaderModel, event)
  if event.key in (:escape, :ctrl_c)
    model.search = ""
    model.mode = :reader
    _refreshreader!(model)
  elseif event.key == :enter
    model.mode = :reader
  elseif event.key == :backspace
    isempty(model.search) || (model.search = chop(model.search))
    model.paperindex = 1
    _refreshreader!(model)
  elseif event.key == :char && isprint(event.char)
    model.search *= string(event.char)
    model.paperindex = 1
    _refreshreader!(model)
  end
end

function update!(model::ReaderModel, event::Tachikoma.KeyEvent)
  event.action == Tachikoma.key_release && return
  if model.mode in (:journalname, :journalissn)
    _addjournalkey!(model, event)
    return
  elseif model.mode == :removejournal
    _removejournalkey!(model, event)
    return
  elseif model.mode == :search
    _searchkey!(model, event)
    return
  elseif model.mode == :help
    event.key in (:escape, :enter) && (model.mode = :reader)
    return
  end

  if event.key == :escape && !isempty(model.search)
    model.search = ""
    model.paperindex = 1
    _refreshreader!(model)
  elseif event.key in (:escape, :ctrl_c) || _ischar(event, 'q') || _ischar(event, 'Q')
    model.quit = true
  elseif event.key == :tab
    model.focus = model.focus == :journals ? :papers : :journals
  elseif _ischar(event, 't')
    _setperiod!(model, :today)
  elseif _ischar(event, 'w')
    _setperiod!(model, :week)
  elseif _ischar(event, 'a')
    _setperiod!(model, :all)
  elseif _ischar(event, 'f')
    _setperiod!(model, :saved)
  elseif _ischar(event, '/')
    model.mode = :search
  elseif _ischar(event, '?')
    model.mode = :help
  elseif event.key in (:up, :down) || _ischar(event, 'j') || _ischar(event, 'k')
    direction = event.key == :up || _ischar(event, 'k') ? -1 : 1
    if model.focus == :journals
      _selectjournal!(model, model.journalindex + direction)
    elseif !isempty(model.papers)
      model.paperindex = clamp(model.paperindex + direction, 1, length(model.papers))
    end
  elseif _ischar(event, 'n')
    model.mode = :journalname
    model.formname = ""
    model.formissn = ""
    model.message = "Enter a journal name."
  elseif _ischar(event, 'x')
    if model.journalindex > 1
      model.mode = :removejournal
    else
      model.message = "Select a journal before removing it."
    end
  elseif _ischar(event, 'r')
    paper = _currentpaper(model)
    paper === nothing || begin
      state = toggleread(model.db, paper.doi)
      model.message = state ? "Marked as read." : "Marked as unread."
      _refreshreader!(model; preservepaper=paper.doi)
    end
  elseif _ischar(event, 's')
    paper = _currentpaper(model)
    paper === nothing || begin
      state = togglesaved(model.db, paper.doi)
      model.message = state ? "Saved paper." : "Removed from saved papers."
      _refreshreader!(model; preservepaper=paper.doi)
    end
  elseif event.key == :enter || _ischar(event, 'o')
    paper = _currentpaper(model)
    paper === nothing || _openpaper(model, paper)
  end
end

function _openpaper(model::ReaderModel, paper::Paper)
  url = paper.url === nothing || isempty(strip(paper.url)) ? "https://doi.org/$(paper.doi)" : paper.url
  command = if Sys.iswindows()
    `cmd /c start "" $url`
  elseif Sys.isapple()
    `open $url`
  else
    `xdg-open $url`
  end
  try
    run(command; wait=false)
    model.message = "Opened paper in browser."
  catch error
    model.message = "Could not open browser: $(sprint(showerror, error))"
  end
end

function _wraptext(text, width)
  width > 0 || return String[]
  lines = String[]
  line = ""
  for word in split(text)
    if isempty(line)
      line = word
    elseif textwidth(line) + 1 + textwidth(word) <= width
      line *= " " * word
    else
      push!(lines, line)
      line = word
    end
  end
  isempty(line) || push!(lines, line)
  lines
end

function _renderheader(model::ReaderModel, area, buf)
  labels = ((:today, "Today"), (:week, "This Week"), (:all, "All"), (:saved, "Saved"))
  x = area.x
  for (period, label) in labels
    text = period == model.period ? "[$label]" : " $label "
    set_string!(buf, x, area.y, text, tstyle(period == model.period ? :accent : :text_dim, bold=period == model.period), area)
    x += textwidth(text) + 1
  end
end

function _renderjournals(model::ReaderModel, area, buf)
  set_string!(buf, area.x, area.y, "▸ All  $(sum(values(model.journalcounts); init=0))", tstyle(model.journalindex == 1 ? :accent : :primary, bold=model.journalindex == 1), area)
  for (offset, journal) in enumerate(model.journals)
    y = area.y + offset
    y <= area.y + area.height - 1 || break
    marker = model.journalindex == offset + 1 ? "▸ " : "  "
    count = get(model.journalcounts, _journalkey(journal.name), 0)
    label = "$(marker)$(_journalabbreviation(journal))  $(count)"
    set_string!(buf, area.x, y, label, tstyle(model.journalindex == offset + 1 ? :accent : :primary), area)
  end
end

function _renderpapers(model::ReaderModel, area, buf)
  if isempty(model.papers)
    message = isempty(model.search) ? "No papers in this view." : "No papers match ‘$(model.search)’"
    set_string!(buf, area.x, area.y, message, tstyle(:text_dim), area)
    return
  end
  visiblecount = max(1, area.height ÷ 2)
  firstindex = max(1, model.paperindex - visiblecount + 1)
  lastindex = min(length(model.papers), firstindex + visiblecount - 1)
  for (offset, index) in enumerate(firstindex:lastindex)
    y = area.y + 2 * (offset - 1)
    paper = model.papers[index]
    selected = index == model.paperindex
    states = String[]
    _isnew(paper) && push!(states, "NEW")
    paper.is_read || push!(states, "UNREAD")
    paper.is_saved && push!(states, "SAVED")
    title = (selected ? "▸ " : "  ") * join(states, " · ") * (isempty(states) ? "" : "  ") * paper.title
    set_string!(buf, area.x, y, title, tstyle(selected ? :accent : :primary, bold=selected), area)
    y + 1 <= area.y + area.height - 1 || continue
    metadata = filter(part -> !isempty(part), (paper.authors, paper.journal, something(paper.published_at, "")))
    set_string!(buf, area.x + 2, y + 1, join(metadata, " · "), tstyle(:text_dim), area)
  end
end

function _renderdetails(model::ReaderModel, area, buf)
  paper = _currentpaper(model)
  paper === nothing && return set_string!(buf, area.x, area.y, "Select a paper to read its details.", tstyle(:text_dim), area)
  y = area.y
  set_string!(buf, area.x, y, paper.title, tstyle(:primary, bold=true), area)
  y += 1
  set_string!(buf, area.x, y, isempty(paper.authors) ? "Authors unavailable" : paper.authors, tstyle(:text_dim), area)
  y += 1
  metadata = filter(part -> !isempty(part), (paper.journal, something(paper.published_at, "")))
  set_string!(buf, area.x, y, join(metadata, " · "), tstyle(:accent), area)
  y += 1
  status = join(filter(part -> !isempty(part), (_isnew(paper) ? "NEW" : "", paper.is_read ? "Read" : "Unread", paper.is_saved ? "Saved" : "Not saved")), " · ")
  set_string!(buf, area.x, y, status, tstyle(:text_dim), area)
  y += 1
  y <= area.y + area.height - 1 || return
  set_string!(buf, area.x, y, "Abstract", tstyle(:title, bold=true), area)
  y += 1
  abstract = something(paper.abstract_text, "No abstract available.")
  for line in _wraptext(abstract, area.width)
    y <= area.y + area.height - 1 || break
    set_string!(buf, area.x, y, line, tstyle(:text), area)
    y += 1
  end
end

function _renderdialog(model::ReaderModel, area, buf)
  width = min(area.width - 4, 64)
  lines = if model.mode == :help
    [
      "t  Show papers added today",
      "w  Show papers added this week",
      "a  Show all papers",
      "f  Show saved papers",
      "Tab  Switch between journals and papers",
      "/  Search papers",
      "Esc  Cancel search or close dialog",
      "r  Toggle read/unread",
      "s  Save/unsave paper",
      "o, Enter  Open selected paper",
      "n  Add a journal",
      "x  Remove selected journal",
      "↑/↓, j/k  Move selection",
      "?  Show this help",
      "q  Quit",
    ]
  elseif model.mode == :removejournal
    ["Remove $(model.journals[model.journalindex - 1].name)?", "Stored papers will be kept.", "Press y to remove or Esc to cancel."]
  elseif model.mode == :journalname
    ["Journal name:", model.formname * "▏", "Enter to continue · Esc to cancel", model.message]
  else
    ["ISSN:", model.formissn * "▏", "Enter to save · Esc to cancel", model.message]
  end
  height = model.mode == :help ? length(lines) + 2 : model.mode == :removejournal ? 5 : 7
  (width < 20 || area.height < height + 2) && return
  x = area.x + (area.width - width) ÷ 2
  y = area.y + (area.height - height) ÷ 2
  dialog = Tachikoma.Rect(x, y, width, height)
  for row in dialog.y:(dialog.y + dialog.height - 1)
    set_string!(buf, dialog.x, row, " " ^ dialog.width, tstyle(:text), dialog)
  end
  title = model.mode == :help ? "Keyboard help" : model.mode == :removejournal ? "Remove journal" : "Add journal"
  inner = render(Block(title=title), dialog, buf)
  for (index, line) in enumerate(lines)
    index <= inner.height || break
    set_string!(buf, inner.x, inner.y + index - 1, line, tstyle(:primary), inner)
  end
end

function view(model::ReaderModel, frame::Tachikoma.Frame)
  buf = frame.buffer
  area = render(Block(title="Journalier"), frame.area, buf)
  rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), area)
  length(rows) == 3 || return
  _renderheader(model, rows[1], buf)
  panes = split_layout(Layout(Horizontal, [Fixed(18), Fill()]), rows[2])
  length(panes) == 2 || return
  journaltitle = model.focus == :journals ? "Journals •" : "Journals"
  selectedjournal = model.journalindex == 1 ? nothing : model.journals[model.journalindex - 1]
  paperlabel = selectedjournal === nothing ? "Papers" : "Papers — $(selectedjournal.name)"
  papertitle = model.focus == :papers ? "$(paperlabel) •" : paperlabel
  journalarea = render(Block(title=journaltitle), panes[1], buf)
  readerrows = split_layout(Layout(Vertical, [Percent(55), Fill()]), panes[2])
  length(readerrows) == 2 || return
  paperarea = render(Block(title=papertitle), readerrows[1], buf)
  detailarea = render(Block(title="Paper"), readerrows[2], buf)
  _renderjournals(model, journalarea, buf)
  _renderpapers(model, paperarea, buf)
  _renderdetails(model, detailarea, buf)
  searchlabel = model.mode == :search ? "/$(model.search)▏" : isempty(model.search) ? "" : "Search: $(model.search)"
  footer = "t today  w week  a all  f saved  Tab pane  / search  r read  s save  o open  n add  x remove selected journal  ? help  q quit  $(searchlabel)  $(model.message)"
  set_string!(buf, rows[3].x, rows[3].y, footer, tstyle(:text_dim), rows[3])
  model.mode in (:help, :journalname, :journalissn, :removejournal) && _renderdialog(model, frame.area, buf)
end

"""Open the interactive reader for papers and journals stored in `db`."""
runui(db) = Tachikoma.app(ReaderModel(db))
