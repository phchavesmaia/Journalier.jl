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

function _renderinline!(buf, x, y, segments, area; color=:primary, bold=false)
  for (segment, italic) in segments
    set_string!(buf, x, y, segment, tstyle(color; bold, italic), area)
    x += textwidth(segment)
  end
end

function _renderheader(model::ReaderModel, area, buf)
  labels = ((:today, "1 Today"), (:week, "2 This Week"), (:all, "3 All"), (:saved, "4 Saved"))
  x = area.x
  for (period, label) in labels
    text = period == model.period ? "[$label]" : " $label "
    set_string!(
      buf,
      x,
      area.y,
      text,
      tstyle(period == model.period ? :accent : :text_dim, bold=period == model.period),
      area
    )
    x += textwidth(text) + 1
  end
end

function _fitlabel(text, width)
  width > 0 || return ""
  textwidth(text) <= width && return text
  prefix = IOBuffer()
  used = 0
  for character in text
    used + textwidth(character) <= width - 1 || break
    print(prefix, character)
    used += textwidth(character)
  end
  String(take!(prefix)) * "…"
end

function _renderjournals(model::ReaderModel, area, buf)
  area.height > 0 || return
  firstindex = max(1, model.journalindex - area.height + 1)
  lastindex = min(length(model.journals) + 1, firstindex + area.height - 1)
  for (offset, index) in enumerate(firstindex:lastindex)
    selected = model.journalindex == index
    journal = index == 1 ? nothing : model.journals[index - 1]
    count = journal === nothing ? model.papercount : get(model.journalcounts, journal.issn, 0)
    acronym = journal === nothing ? "All" : journal.acronym
    marker = journal === nothing ? " " : selected ? "▸ " : "  "
    counttext = string(count)
    labelwidth = area.width - textwidth(counttext) - 2
    label = _fitlabel(marker * acronym, labelwidth) * "  " * counttext
    if labelwidth < 0
      label = _fitlabel(counttext, area.width)
    end
    set_string!(buf, area.x, area.y + offset - 1, label, tstyle(selected ? :accent : :primary, bold=selected), area)
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
    prefix = (selected ? "▸ " : "  ") * join(states, " · ") * (isempty(states) ? "" : "  ")
    set_string!(buf, area.x, y, prefix, tstyle(selected ? :accent : :primary, bold=selected), area)
    _renderinline!(
      buf,
      area.x + textwidth(prefix),
      y,
      model.titles[paper.doi].segments,
      area;
      color=selected ? :accent : :primary,
      bold=selected
    )
    y + 1 <= area.y + area.height - 1 || continue
    metadata = filter(part -> !isempty(part), (paper.authors, paper.journal, something(paper.published_at, "")))
    set_string!(buf, area.x + 2, y + 1, join(metadata, " · "), tstyle(:text_dim), area)
  end
end

function _renderdetails(model::ReaderModel, area, buf)
  paper = _currentpaper(model)
  paper === nothing &&
    return set_string!(buf, area.x, area.y, "Select a paper to read its details.", tstyle(:text_dim), area)
  y = area.y
  _renderinline!(buf, area.x, y, model.titles[paper.doi].segments, area; color=:primary, bold=true)
  y += 1
  set_string!(buf, area.x, y, isempty(paper.authors) ? "Authors unavailable" : paper.authors, tstyle(:text_dim), area)
  y += 1
  metadata = filter(part -> !isempty(part), (paper.journal, something(paper.published_at, "")))
  set_string!(buf, area.x, y, join(metadata, " · "), tstyle(:accent), area)
  y += 1
  status = join(
    filter(
      part -> !isempty(part),
      (_isnew(paper) ? "NEW" : "", paper.is_read ? "Read" : "Unread", paper.is_saved ? "Saved" : "Not saved")
    ),
    " · "
  )
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
      "1  Show papers added today",
      "2  Show papers added this week",
      "3  Show all papers",
      "4  Show saved papers",
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
      "q  Quit"
    ]
  elseif model.mode == :removejournal
    [
      "Remove $(model.journals[model.journalindex - 1].name)?",
      "Stored papers will be kept.",
      "Press y to remove or Esc to cancel."
    ]
  elseif model.mode == :journalacronym
    [
      model.formname,
      "Journal acronym/abbreviation:",
      model.formacronym * "▏",
      "Enter to save · Esc to cancel",
      model.message
    ]
  else
    ["ISSN:", model.formissn * "▏", "Enter to look up name · Esc to cancel", model.message]
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
  area = render(Block(title="Journalier", border_style=tstyle(:text_dim)), frame.area, buf)
  rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), area)
  length(rows) == 3 || return
  _renderheader(model, rows[1], buf)
  panes = split_layout(Layout(Horizontal, [Fixed(18), Fill()]), rows[2])
  length(panes) == 2 || return
  journaltitle = model.focus == :journals ? "Journals •" : "Journals"
  selectedjournal = model.journalindex == 1 ? nothing : model.journals[model.journalindex - 1]
  paperlabel = selectedjournal === nothing ? "Papers" : "Papers — $(selectedjournal.name)"
  papertitle = model.focus == :papers ? "$(paperlabel) •" : paperlabel
  journalstyle = tstyle(model.focus == :journals ? :accent : :text_dim, bold=model.focus == :journals)
  journalarea = render(Block(title=journaltitle, title_style=journalstyle, border_style=journalstyle), panes[1], buf)
  readerrows = split_layout(Layout(Vertical, [Percent(55), Fill()]), panes[2])
  length(readerrows) == 2 || return
  paperstyle = tstyle(model.focus == :papers ? :accent : :text_dim, bold=model.focus == :papers)
  paperarea = render(Block(title=papertitle, title_style=paperstyle, border_style=paperstyle), readerrows[1], buf)
  detailarea =
    render(Block(title="Paper", title_style=tstyle(:text_dim), border_style=tstyle(:text_dim)), readerrows[2], buf)
  _renderjournals(model, journalarea, buf)
  _renderpapers(model, paperarea, buf)
  _renderdetails(model, detailarea, buf)
  searchlabel = model.mode == :search ? "/$(model.search)▏" : isempty(model.search) ? "" : "Search: $(model.search)"
  footer = "Tab pane  / search  r read  s save  o open  n add  x remove selected journal  ? help  q quit  $(searchlabel)  $(model.message)"
  set_string!(buf, rows[3].x, rows[3].y, footer, tstyle(:text_dim), rows[3])
  model.mode in (:help, :journalacronym, :journalissn, :removejournal) && _renderdialog(model, frame.area, buf)
end
