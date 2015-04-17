{
  ### Copy this file into ext/local/t to contain custom database information
  package DW::PRIVATE;

  %DBINFO = (
    master => {
      dbname => "test_master",
      user => "testuser",
      pass => "",
    },

    c01 => {
      dbname => "test_c01",
      user => "testuser",
      pass => "",
    },

    c02 => {
      dbname => "test_c02",
      user => "testuser",
      pass => "",
    },

    theschwartz => {
      dbname => "test_schwartz",
      user => "testuser",
      pass => "",
    }
  );
}

1;
