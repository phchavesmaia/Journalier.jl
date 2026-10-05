struct PreparedTitle
  title::String
  titlehtml::Union{Nothing,String}
  segments::Vector{Tuple{String,Bool}}
end

function _pushinline!(segments, text, italic)
  segment = replace(_decodehtml(text), r"\s+" => " ")
  isempty(segment) && return
  if !isempty(segments) && endswith(last(segments)[1], " ") && startswith(segment, " ")
    segment = lstrip(segment)
  end
  isempty(segment) || push!(segments, (segment, italic))
end

function _inlinehtmlsegments(text)
  segments = Tuple{String,Bool}[]
  italiclevel = 0
  cursor = firstindex(text)
  for tag in eachmatch(r"<[^>]*>", text)
    start = tag.offset
    if cursor < start
      _pushinline!(segments, text[cursor:prevind(text, start)], italiclevel > 0)
    end
    normalizedtag = lowercase(tag.match)
    if occursin(r"^<\s*(?:i|em)\b", normalizedtag)
      italiclevel += 1
    elseif occursin(r"^<\s*(?:/|\\)\s*(?:i|em)\s*>$", normalizedtag)
      italiclevel = max(0, italiclevel - 1)
    end
    cursor = nextind(text, start, length(tag.match))
  end
  cursor <= lastindex(text) && _pushinline!(segments, text[cursor:lastindex(text)], italiclevel > 0)
  segments
end

function _rawpapertitle(paper::Paper)
  paper.title_html === nothing || return paper.title_html
  replace(paper.title, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
end

function _preparedtitle(paper, cached)
  if cached !== nothing && cached.title == paper.title && cached.titlehtml == paper.title_html
    return PreparedTitle(paper.title, paper.title_html, cached.segments)
  end
  PreparedTitle(paper.title, paper.title_html, _inlinehtmlsegments(_rawpapertitle(paper)))
end
