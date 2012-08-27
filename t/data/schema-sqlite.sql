CREATE TABLE funcmap (
        funcid         INTEGER PRIMARY KEY AUTOINCREMENT,
        funcname       VARCHAR(255) NOT NULL,
        UNIQUE(funcname)
);

CREATE TABLE job (
        jobid           INTEGER PRIMARY KEY AUTOINCREMENT,
        funcid          INTEGER UNSIGNED NOT NULL,
        arg             MEDIUMBLOB,
        uniqkey         VARCHAR(255) NULL,
        insert_time     INTEGER UNSIGNED,
        run_after       INTEGER UNSIGNED NOT NULL,
        grabbed_until   INTEGER UNSIGNED NOT NULL,
        priority        SMALLINT UNSIGNED,
        coalesce        VARCHAR(255),
        UNIQUE(funcid,uniqkey)
);

CREATE TABLE error (
        error_time      INTEGER UNSIGNED NOT NULL,
        jobid           INTEGER NOT NULL,
        message         VARCHAR(255) NOT NULL,
        funcid          INT UNSIGNED NOT NULL DEFAULT 0
);

CREATE TABLE exitstatus (
        jobid           INTEGER PRIMARY KEY NOT NULL,
        funcid          INT UNSIGNED NOT NULL DEFAULT 0,
        status          SMALLINT UNSIGNED,
        completion_time INTEGER UNSIGNED,
        delete_after    INTEGER UNSIGNED
);
