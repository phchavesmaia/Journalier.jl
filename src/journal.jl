"""A journal configured for Crossref collection, identified by its ISSN."""
struct Journal
  issn::String
  name::String
  acronym::String
end

const INITIAL_JOURNALS = (
  Journal("0094-1190", "Journal of Urban Economics", "JUE"),
  Journal("0166-0462", "Regional Science and Urban Economics", "RSUE"),
  Journal("0034-6535", "Review of Economics and Statistics", "RESTAT"),
  Journal("0304-3878", "Journal of Development Economics", "JDE"),
  Journal("0002-8282", "American Economic Review", "AER"),
  Journal("0033-5533", "Quarterly Journal of Economics", "QJE")
)
