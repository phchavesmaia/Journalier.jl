"""A journal queried from Crossref by ISSN."""
struct Journal
  id::String
  name::String
  issn::String
end

const INITIAL_JOURNALS = (
  Journal("jue", "Journal of Urban Economics", "0094-1190"),
  Journal("rsue", "Regional Science and Urban Economics", "0166-0462"),
  Journal("restat", "Review of Economics and Statistics", "0034-6535"),
  Journal("jde", "Journal of Development Economics", "0304-3878"),
  Journal("aer", "American Economic Review", "0002-8282"),
  Journal("qje", "Quarterly Journal of Economics", "0033-5533")
)
