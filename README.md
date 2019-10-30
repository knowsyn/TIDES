TIDES

Toolkit for Immunogenomic Data Exchange and Storage

DOCKER

TIDES requires the knowsyn/tides image as well as a postgres image.
Additionally, the Docker stack requires four secrets, which can be
generated as follows (using bash syntax and the pwgen command):

	mkdir secrets
	chmod 700 secrets
	for i in postgres tides www; do pwgen >secrets/$i.txt; done
	perl -MDigest::MD5=md5_base64 -l -e 'print md5_base64($$,time(),rand(9999))' >secrets/cgi.txt

Then, to bring up TIDES on port 443:

	time docker pull knowsyn/tides:latest
	time docker pull postgres:latest
	docker stack deploy -c docker-compose.yml tides

TIDES should soon be running at https://localhost/.

DATABASE

TIDES uses a database to store information and has been developed and
tested with PostgreSQL. The following commands set up the database:

	createdb tides
	psql -f schema.sql tides

The schema assumes existence of a www-data user for database access from
the web server.

INSTALLATION

To install this module, run the following commands:

	perl Build.PL
	./Build
	./Build test
	./Build install

To specify an installation root of /home/foo, replace the first line
above with

	perl Build.PL --install_base /home/foo

By default HTML and CSS files install to /var/www/html.  If you want
to install these files elsewhere, specify an install_path for htdocs to
the perl or install commands, e.g., either of

	perl Build.PL --install_path htdocs=/foo/path/html
	./Build install --install_path htdocs=/foo/path/html

will cause installation of the HTML and CSS files to /foo/path/html.
If the htdocs directory is not the HTML document root, then the path to
tides.css in lib/TIDES/header.tmpl needs to be adjusted accordingly.

DEPENDENCIES

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

Further tests are enabled by setting the environment variable RELEASE_TESTING
to 1 and installing the following modules:

Perl::Critic           1.098
Pod::Coverage          0.18
Pod::Simple            3.07
Test::Perl::Critic     1.01
Test::Pod              1.26
Test::Pod::Coverage    1.08

They are all available on CPAN (https://www.cpan.org/).

SUPPORT AND DOCUMENTATION

After installing, you can find documentation for this module with the perldoc
command.

    perldoc TIDES

COPYRIGHT AND LICENCE

Copyright 2019 Knowledge Synthesis Inc.

This program is released under the following license: gpl

The full text of the license can be found in the LICENSE file included
with this distribution.