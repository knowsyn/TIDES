# TIDES

Toolkit for Immunogenomic Data Exchange and Storage

## Docker Installation (recommended)

The Docker stack configuration is in the GitHub repository:

    git clone https://github.com/knowsyn/TIDES
    cd TIDES

The stack requires four secrets, which can be generated as follows (using
`bash` syntax and the `pwgen` command):

    mkdir secrets
    chmod 700 secrets
    for i in postgres tides www; do pwgen >secrets/$i.txt; done
    perl -MDigest::MD5=md5_base64 -l -e 'print md5_base64($$,time(),rand(9999))' >secrets/cgi.txt

Copy the desired SSL certificate file to `secrets/cert.txt` and the
key file to `secrets/key.txt`. Alternatively, to use the auto-generated
certificate, which by default will not be trusted by browsers, remove
all lines containing `cert` and `key` from `docker-compose.yml`.

TIDES requires the knowsyn/tides image as well as a postgres image prior
to release 12.  If there is no Docker swarm yet, `docker swarm init`
initializes one locally. Then, to bring up TIDES on port 443:

    docker pull knowsyn/tides:latest
    docker pull postgres:11
    docker stack deploy -c docker-compose.yml tides

Installation complete. TIDES should soon be running at
`https://localhost/`. The default user is `demo` (defined by `TIDES_USER`
in `docker-compose.yml`), and the default password is the contents of
`secrets/tides.txt`.

## Source Installation

To install the TIDES module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

To specify an installation root of `/home/foo`, replace the first line
above with

    perl Build.PL --install_base /home/foo

By default HTML and CSS files install to `/var/www/html`.  If you want
to install these files elsewhere, specify an `install_path` for `htdocs` to
the perl or install commands, e.g., either of

    perl Build.PL --install_path htdocs=/foo/path/html
    ./Build install --install_path htdocs=/foo/path/html

will cause installation of the HTML and CSS files to `/foo/path/html`.
If the `htdocs` directory is not the HTML document root, then the path to
`tides.css` in `lib/TIDES/header.tmpl` needs to be adjusted accordingly.

The top-level CGI script is `bin/tides` and needs to be installed as
appropriate for the web server configuration. On a default Debian Apache
installation, copy `bin/tides` to `/usr/lib/cgi-bin`.

### Database

TIDES uses a database to store information and has been developed and
tested with PostgreSQL. The following commands set up the database:

    createdb tides
    psql -f schema.sql tides

The schema assumes existence of a `tides` user for database access from
the web server. This user must exist in the PostgreSQL database before
creating the schema.

For an example alternative, the default Debian installation runs Apache
as user `www-data`. To accommodate such a configuration, add a `www-data`
user to Postgres, then change `tides` in the `GRANT` lines at the end of
`schema.sql` to user `"www-data"`. Then add

    db_user => '',

above the `gl_service` line in `bin/tides`.

### Dependencies

This module requires these other modules:

    CGI::Application
    CGI::Application::Plugin::TT
    CGI::Application::Plugin::Authentication
    DBD::Pg
    Digest::SHA
    File::MimeInfo
    File::Temp
    JSON
    Spreadsheet::ParseExcel
    Spreadsheet::XLSX
    Statistics::R along with the R disambiguateR package
    Template
    URI::Escape
    WWW::Curl::Easy
    XML::Twig

At build time you will need the above modules plus the following if you want
to run the tests:

    Module::Build
    Test::More
    Test::WWW::Mechanize::CGIApp

Further tests are enabled by setting the environment variable
`RELEASE_TESTING` to `1` and installing the following modules:

    Perl::Critic
    Pod::Coverage
    Pod::Simple
    Test::Perl::Critic
    Test::Pod
    Test::Pod::Coverage

They are all available on [CPAN](https://www.cpan.org/).

### Documentation

After installing, you can find documentation for this module with the perldoc
command.

    perldoc TIDES

## Copyright and Licence

Copyright 2019 Knowledge Synthesis Inc.

This program is released under the following license: gpl

The full text of the license can be found in the LICENSE file included
with this distribution.
