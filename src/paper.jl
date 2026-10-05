struct Paper
  doi::String
  title::String
  authors::String
  journal::String
  abstract_text::Union{Nothing,String}
  url::Union{Nothing,String}
  published_at::Union{Nothing,String}
  first_seen_at::String
  source::String
  raw_metadata::String
  is_read::Bool
  is_saved::Bool
end
