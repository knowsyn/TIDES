CREATE TABLE sessions (
    id        CHAR(32) PRIMARY KEY,
    a_session BYTEA NOT NULL
);

CREATE TABLE users (
    id       SERIAL PRIMARY KEY,
    name     TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL
);
CREATE INDEX users_name_idx ON users (name);

CREATE TABLE uploads (
    id   SERIAL PRIMARY KEY,
    who  INTEGER REFERENCES users ON DELETE CASCADE NOT NULL,
    time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE collections (
    id   SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE samples (
    id         SERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    collection INTEGER REFERENCES collections ON DELETE CASCADE NOT NULL,
    upload     INTEGER REFERENCES uploads ON DELETE CASCADE NOT NULL,
    UNIQUE(name, collection)
);
CREATE INDEX samples_collection_idx ON samples (collection);

CREATE TABLE studies (
    id   SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE study_samples (
    study  INTEGER REFERENCES studies ON DELETE CASCADE NOT NULL,
    sample INTEGER REFERENCES samples ON DELETE CASCADE NOT NULL,
    UNIQUE(study, sample)
);

CREATE TYPE TYPE_T AS ENUM (
    'fixed',
    'text',
    'numeric',
    'date'
);

CREATE TABLE properties (
    id   SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    type TYPE_T NOT NULL
);

CREATE TABLE fixed_values (
    id       SERIAL PRIMARY KEY,
    property INTEGER REFERENCES properties ON DELETE CASCADE NOT NULL,
    value    TEXT,
    UNIQUE(property, value)
);

-- Some sample_fixed_properties are one-to-many, e.g., sample -> Locus.
CREATE TABLE sample_fixed_properties (
    sample      INTEGER REFERENCES samples ON DELETE CASCADE NOT NULL,
    fixed_value INTEGER REFERENCES fixed_values ON DELETE CASCADE NOT NULL,
    UNIQUE(sample, fixed_value)
);

-- Will we need one-to-many text properties?
CREATE TABLE sample_text_properties (
    sample   INTEGER REFERENCES samples ON DELETE CASCADE NOT NULL,
    property INTEGER REFERENCES properties ON DELETE CASCADE NOT NULL,
    value    TEXT NOT NULL,
    PRIMARY KEY(sample, property)
);

-- Will we need one-to-many numeric properties?
CREATE TABLE sample_numeric_properties (
    sample   INTEGER REFERENCES samples ON DELETE CASCADE NOT NULL,
    property INTEGER REFERENCES properties ON DELETE CASCADE NOT NULL,
    value    NUMERIC NOT NULL,
    PRIMARY KEY(sample, property)
);

-- Will we need one-to-many date properties?
CREATE TABLE sample_date_properties (
    sample   INTEGER REFERENCES samples ON DELETE CASCADE NOT NULL,
    property INTEGER REFERENCES properties ON DELETE CASCADE NOT NULL,
    value    TIMESTAMP NOT NULL,
    PRIMARY KEY(sample, property)
);

CREATE TABLE g_l_strings (
    id     SERIAL PRIMARY KEY,
    sample INTEGER REFERENCES samples ON DELETE CASCADE NOT NULL,
    str    TEXT NOT NULL,
    uri    TEXT NOT NULL,
    upload INTEGER REFERENCES uploads ON DELETE CASCADE NOT NULL
);

CREATE TABLE gfes (
    id     SERIAL PRIMARY KEY,
    sample INTEGER REFERENCES samples ON DELETE CASCADE NOT NULL,
    gfe    TEXT NOT NULL,
    upload INTEGER REFERENCES uploads ON DELETE CASCADE NOT NULL
);

--
-- Views
--

-- PLINK:
--     Family ID
--     Individual ID
--     Paternal ID
--     Maternal ID
--     Sex (1=male; 2=female; other=unknown)
--     Phenotype (1=unaffected, 2=affected)
CREATE VIEW v_plink AS
    SELECT f.value AS family,
           s.id AS individual,
           p.value AS paternal,
           m.value AS maternal,
           g.value AS sex,
           t.value AS phenotype
    FROM samples s
        JOIN (SELECT sample, value FROM sample_text_properties
              WHERE property = (
                  SELECT id FROM properties
                  WHERE name = 'Family ID')) f ON f.sample = s.id
        JOIN (SELECT sample, value FROM sample_numeric_properties
              WHERE property = (
                  SELECT id FROM properties
                  WHERE name = 'Paternal ID')) p ON p.sample = s.id
        JOIN (SELECT sample, value FROM sample_numeric_properties
              WHERE property = (
                  SELECT id FROM properties
                  WHERE name = 'Maternal ID')) m ON m.sample = s.id
        JOIN (SELECT sample, CASE WHEN fv.value = 'male' THEN 1
                                  WHEN fv.value = 'female' THEN 2
                                  ELSE -9
                             END AS value
              FROM sample_fixed_properties sp
                  JOIN fixed_values fv ON fv.id = sp.fixed_value
                  JOIN properties p ON p.id = fv.property
              WHERE p.name = 'Sex') g ON g.sample = s.id
        JOIN (SELECT sample, value FROM sample_numeric_properties
              WHERE property = (
                  SELECT id FROM properties
                  WHERE name = 'Phenotype')) t ON t.sample = s.id;

CREATE VIEW v_uploads AS
    SELECT u.id,
           w.name,
           to_char(u.time, 'Dy Mon DD HH24:MI:SS YYYY TZ') AS time,
           c.type,
           c.count
    FROM uploads u
        JOIN (SELECT upload, count(id), 'Sample' AS type FROM samples
                  GROUP BY upload
              UNION
              SELECT upload, count(id), 'GL String' AS type FROM g_l_strings
                  GROUP BY upload) c ON c.upload = u.id
        JOIN users w ON w.id = u.who
    ORDER BY u.time DESC;

-- Some data we will always have.
INSERT INTO properties (name,type) VALUES ('Family ID','text');
INSERT INTO properties (name,type) VALUES ('Paternal ID','numeric');
INSERT INTO properties (name,type) VALUES ('Maternal ID','numeric');
INSERT INTO properties (name,type) VALUES ('Sex','fixed');
INSERT INTO fixed_values (property,value) VALUES (
    (SELECT id FROM properties WHERE name = 'Sex'), 'male'
);
INSERT INTO fixed_values (property,value) VALUES (
    (SELECT id FROM properties WHERE name = 'Sex'), 'female'
);
INSERT INTO properties (name,type) VALUES ('Phenotype','numeric');
INSERT INTO properties (name,type) VALUES ('Locus','fixed');

-- Permissions for web server
GRANT SELECT, INSERT ON collections TO "www-data";
GRANT SELECT, UPDATE ON collections_id_seq TO "www-data";
GRANT SELECT, INSERT, DELETE ON g_l_strings TO "www-data";
GRANT SELECT, UPDATE ON g_l_strings_id_seq TO "www-data";
GRANT SELECT, INSERT, DELETE ON gfes TO "www-data";
GRANT SELECT, UPDATE ON gfes_id_seq TO "www-data";
GRANT SELECT, INSERT ON properties TO "www-data";
GRANT SELECT, UPDATE ON properties_id_seq TO "www-data";
GRANT SELECT, INSERT ON fixed_values TO "www-data";
GRANT SELECT, UPDATE ON fixed_values_id_seq TO "www-data";
GRANT SELECT, INSERT, DELETE ON samples TO "www-data";
GRANT SELECT, UPDATE ON samples_id_seq TO "www-data";
GRANT SELECT, INSERT ON sample_text_properties TO "www-data";
GRANT SELECT, INSERT ON sample_fixed_properties TO "www-data";
GRANT SELECT, INSERT ON sample_numeric_properties TO "www-data";
GRANT SELECT, INSERT ON sample_date_properties TO "www-data";
GRANT SELECT, INSERT, UPDATE, DELETE ON sessions TO "www-data";
GRANT SELECT, INSERT, DELETE ON uploads TO "www-data";
GRANT SELECT, UPDATE ON uploads_id_seq TO "www-data";
GRANT SELECT ON users TO "www-data";
GRANT SELECT ON v_plink TO "www-data";
GRANT SELECT ON v_uploads TO "www-data";
