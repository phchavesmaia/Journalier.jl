# Exercise reader startup without accessing user files, the network, or a terminal.
@setup_workload begin
  db = SQLite.DB()
  backend = Tachikoma.TestBackend(100, 30)
  frame =
    Tachikoma.Frame(backend.buf, Tachikoma.Rect(1, 1, 100, 30), Tachikoma.GraphicsRegion[], Tachikoma.PixelSnapshot[])
  try
    @compile_workload begin
      initializedb(db)
      upsertpaper(
        db;
        doi="10.0000/precompile-formatted",
        title="Cities & regional growth α",
        titlehtml="Cities &amp; <i>regional growth</i> α",
        authors="Example Author",
        journal=INITIAL_JOURNALS[1].name,
        journalissn=INITIAL_JOURNALS[1].issn,
        abstracttext="An illustrative abstract describing cities, regional growth, and economic development.",
        publishedat="2026-01-01",
        createdat="2026-01-01"
      )
      upsertpaper(db; doi="10.0000/precompile-plain", title="Plain title <with> symbols")
      model = ReaderModel(
        db;
        fetchjournal=issn -> [Dict("DOI" => "10.0000/example", "container-title" => ["Example Journal"])]
      )
      view(model, frame)
      for event in (
        Tachikoma.KeyEvent(:down),
        Tachikoma.KeyEvent('r'),
        Tachikoma.KeyEvent('s'),
        Tachikoma.KeyEvent('4'),
        Tachikoma.KeyEvent('1'),
        Tachikoma.KeyEvent('2'),
        Tachikoma.KeyEvent('3'),
        Tachikoma.KeyEvent('/'),
        Tachikoma.KeyEvent('z'),
        Tachikoma.KeyEvent(:backspace),
        Tachikoma.KeyEvent(:escape),
        Tachikoma.KeyEvent(:tab),
        Tachikoma.KeyEvent(:down),
        Tachikoma.KeyEvent('?'),
        Tachikoma.KeyEvent(:escape),
        Tachikoma.KeyEvent('n'),
        Tachikoma.KeyEvent('1'),
        Tachikoma.KeyEvent('2'),
        Tachikoma.KeyEvent('3'),
        Tachikoma.KeyEvent('4'),
        Tachikoma.KeyEvent('5'),
        Tachikoma.KeyEvent('6'),
        Tachikoma.KeyEvent('7'),
        Tachikoma.KeyEvent('8'),
        Tachikoma.KeyEvent(:enter),
        Tachikoma.KeyEvent('X'),
        Tachikoma.KeyEvent(:backspace),
        Tachikoma.KeyEvent(:escape),
        Tachikoma.KeyEvent('x'),
        Tachikoma.KeyEvent(:escape)
      )
        update!(model, event)
        view(model, frame)
      end
    end
  finally
    close(db)
  end
end
