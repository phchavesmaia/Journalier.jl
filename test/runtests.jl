using Journalier
using HTTP
using JSON
using Dates
using Tachikoma
using Test

@testset "Journalier" begin
  include("paths.jl")
  include("config.jl")
  include("database.jl")
  include("collector.jl")
  include("tui.jl")
  include("scheduler.jl")
  include("cli.jl")
end
