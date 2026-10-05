@testset "Reader model and view" begin
  mktempdir() do dir
    db = initializedb(joinpath(dir, "papers.db"))
    try
      recent = Dates.format(Dates.now(Dates.UTC), dateformat"yyyy-mm-dd HH:MM:SS")
      old = Dates.format(Dates.now(Dates.UTC) - Day(14), dateformat"yyyy-mm-dd HH:MM:SS")
      upsertpaper(
        db;
        doi="10.1234/first",
        title="First Sample Paper",
        authors="Ada Lovelace",
        journal="Journal of Urban Economics",
        journalissn="0094-1190",
        abstracttext="A short abstract for the first paper.",
        url="https://doi.org/10.1234/first",
        rawmetadata=JSON.json(Dict("title" => ["First\n                    <i>Sample</i> Paper"]))
      )
      upsertpaper(
        db;
        doi="10.1234/second",
        title="Second Older Paper",
        authors="Grace Hopper",
        journal="The Quarterly Journal of Economics",
        journalissn="0033-5533",
        abstracttext="An older paper abstract."
      )
      Journalier.DBInterface.execute(db, "UPDATE papers SET first_seen_at = ? WHERE doi = ?", (recent, "10.1234/first"))
      Journalier.DBInterface.execute(db, "UPDATE papers SET first_seen_at = ? WHERE doi = ?", (old, "10.1234/second"))
      togglesaved(db, "10.1234/first")

      model = Journalier.ReaderModel(db)
      @test length(model.papers) == 2
      @test model.journalindex == 1
      @test model.journalcounts["0033-5533"] == 1
      @test Journalier._isnew(model.papers[1])
      @test !Journalier._isnew(model.papers[2])
      @test !Tachikoma.should_quit(model)
      Tachikoma.update!(model, Tachikoma.KeyEvent(:down))
      @test model.paperindex == 2
      Tachikoma.update!(model, Tachikoma.KeyEvent('k'))
      @test model.paperindex == 1

      Tachikoma.update!(model, Tachikoma.KeyEvent('r'))
      @test getpaper(db, "10.1234/first").is_read
      Tachikoma.update!(model, Tachikoma.KeyEvent('s'))
      @test !getpaper(db, "10.1234/first").is_saved
      Tachikoma.update!(model, Tachikoma.KeyEvent('s'))
      @test getpaper(db, "10.1234/first").is_saved

      Tachikoma.update!(model, Tachikoma.KeyEvent('t'))
      @test length(model.papers) == 1
      Tachikoma.update!(model, Tachikoma.KeyEvent('w'))
      @test length(model.papers) == 1
      Tachikoma.update!(model, Tachikoma.KeyEvent('a'))
      @test length(model.papers) == 2
      Tachikoma.update!(model, Tachikoma.KeyEvent('f'))
      @test only(model.papers).doi == "10.1234/first"
      Tachikoma.update!(model, Tachikoma.KeyEvent('a'))
      targetqje = findfirst(journal -> journal.name == "Quarterly Journal of Economics", model.journals)
      Journalier._selectjournal!(model, targetqje + 1)
      @test only(model.papers).doi == "10.1234/second"
      @test model.journalcounts["0033-5533"] == 1
      Journalier._selectjournal!(model, 1)

      Tachikoma.update!(model, Tachikoma.KeyEvent('/'))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "Second")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test only(model.papers).doi == "10.1234/second"
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
      @test isempty(model.search)
      @test length(model.papers) == 2

      model.focus = :journals
      targetjournal = findfirst(journal -> journal.name == "Journal of Urban Economics", model.journals)
      Journalier._selectjournal!(model, targetjournal + 1)
      @test only(model.papers).journal == "Journal of Urban Economics"
      Tachikoma.update!(model, Tachikoma.KeyEvent('/'))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "First")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test only(model.papers).doi == "10.1234/first"
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
      @test only(model.papers).journal == "Journal of Urban Economics"
      Tachikoma.update!(model, Tachikoma.KeyEvent(:tab))
      @test model.focus == :papers

      Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
      @test model.mode == :journalname
      addbackend = Tachikoma.TestBackend(100, 30)
      addframe = Tachikoma.Frame(
        addbackend.buf,
        Tachikoma.Rect(1, 1, 100, 30),
        Tachikoma.GraphicsRegion[],
        Tachikoma.PixelSnapshot[]
      )
      Tachikoma.view(model, addframe)
      @test Tachikoma.find_text(addbackend, "Add journal") !== nothing
      Tachikoma.set_string!(addbackend.buf, 20, 17, "underlying text", Tachikoma.tstyle(:text))
      Journalier._renderdialog(model, addframe.area, addbackend.buf)
      @test all(Tachikoma.char_at(addbackend, x, 17) == ' ' for x in 20:81)
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))
      @test model.mode == :reader
      Tachikoma.update!(model, Tachikoma.KeyEvent('n'))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "New Journal")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      foreach(character -> Tachikoma.update!(model, Tachikoma.KeyEvent(character)), "5678-9012")
      Tachikoma.update!(model, Tachikoma.KeyEvent(:enter))
      @test any(journal -> journal.name == "New Journal", getjournals(db))
      @test model.journals[model.journalindex - 1].name == "New Journal"
      Tachikoma.update!(model, Tachikoma.KeyEvent('x'))
      Tachikoma.update!(model, Tachikoma.KeyEvent('y'))
      @test !any(journal -> journal.name == "New Journal", getjournals(db))
      @test getpaper(db, "10.1234/first") !== nothing

      Tachikoma.update!(model, Tachikoma.KeyEvent('a'))
      renderbackend = Tachikoma.TestBackend(120, 36)
      frame = Tachikoma.Frame(
        renderbackend.buf,
        Tachikoma.Rect(1, 1, 120, 36),
        Tachikoma.GraphicsRegion[],
        Tachikoma.PixelSnapshot[]
      )
      Tachikoma.view(model, frame)
      @test Tachikoma.find_text(renderbackend, "Today") !== nothing
      @test Tachikoma.find_text(renderbackend, "Journals") !== nothing
      @test Tachikoma.find_text(renderbackend, "JUE") !== nothing
      @test Tachikoma.find_text(renderbackend, "QJE") !== nothing
      @test Tachikoma.find_text(renderbackend, "First Sample Paper") !== nothing
      @test Tachikoma.find_text(renderbackend, "A short abstract") !== nothing
      @test Tachikoma.find_text(renderbackend, "NEW") !== nothing
      @test any(
        Tachikoma.char_at(renderbackend, x, y) == 'S' && Tachikoma.style_at(renderbackend, x, y).italic for
        y in 1:renderbackend.height for x in 1:renderbackend.width
      )
      @test Journalier._journalabbreviation(Journal("12345678", "New Journal of Economics", "1234-5678")) == "NJE"

      Tachikoma.update!(model, Tachikoma.KeyEvent('?'))
      helpbackend = Tachikoma.TestBackend(100, 30)
      helpframe = Tachikoma.Frame(
        helpbackend.buf,
        Tachikoma.Rect(1, 1, 100, 30),
        Tachikoma.GraphicsRegion[],
        Tachikoma.PixelSnapshot[]
      )
      Tachikoma.view(model, helpframe)
      @test Tachikoma.find_text(helpbackend, "Keyboard help") !== nothing
      helpcommands = (
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
        "q  Quit"
      )
      helpresults = [Tachikoma.find_text(helpbackend, command) for command in helpcommands]
      helprows = [position.y for position in filter(position -> position !== nothing, helpresults)]
      @test length(unique(helprows)) == length(helpcommands)
      Tachikoma.update!(model, Tachikoma.KeyEvent(:escape))

      Tachikoma.update!(model, Tachikoma.KeyEvent('q'))
      @test Tachikoma.should_quit(model)
    finally
      close(db)
    end
  end
end

@testset "Journal identity" begin
  db = initializedb(Journalier.SQLite.DB())
  try
    upsertpaper(db; doi="10.1234/unassigned", title="Unassigned paper", journal="Journal of Urban Economics")
    model = Journalier.ReaderModel(db)
    @test model.papercount == 1
    @test length(model.papers) == 1
    journalindex = findfirst(journal -> journal.issn == "0094-1190", model.journals)
    Journalier._selectjournal!(model, journalindex + 1)
    @test isempty(model.papers)
    @test isempty(model.journalcounts)
    @test model.papercount == 1
  finally
    close(db)
  end
end
