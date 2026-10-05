"""Decode common HTML character entities."""
function _decodehtml(value)
  text = string(value)
  for (entity, character) in
      (("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "))
    text = replace(text, entity => character)
  end
  replace(text, "&amp;" => "&")
end

"""Remove inline HTML markup, decode common entities, and normalize whitespace."""
function _cleanhtml(value)
  text = replace(string(value), r"<[^>]*>" => " ")
  text = _decodehtml(text)
  join(split(strip(text)), " ")
end

function _cleanabstract(value)
  value === nothing && return nothing
  text = _cleanhtml(value)
  isempty(text) ? nothing : text
end
