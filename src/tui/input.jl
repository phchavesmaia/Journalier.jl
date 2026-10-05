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
        _refreshreader!(model; journalid=journal.id)
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
