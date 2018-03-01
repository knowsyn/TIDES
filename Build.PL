use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name        => 'TIDES',
    license            => 'gpl',
    dist_author        => 'Ken Yamaguchi <ken@knowledgesynthesis.com>',
    configure_requires => { 'Module::Build' => 0.38 },
    requires           => {
        'CGI::Application'                         => 4.04,
        'CGI::Application::Plugin::TT'             => 0,
        'CGI::Application::Plugin::Authentication' => 0,
        'DBD::Pg'                                  => 0,
        'Digest::SHA'                              => 0,
        'File::MimeInfo'                           => 0,
        'File::Temp'                               => 0,
        'JSON'                                     => 0,
        'Spreadsheet::ParseExcel'                  => 0,
        'Spreadsheet::XLSX'                        => 0,
        'Statistics::R'                            => 0,
        'Template'                                 => 0,
        'Test::More'                               => 0,
        'Test::WWW::Mechanize::CGIApp'             => 0,
        'Titanium'                                 => 0,
        'URI::Escape'                              => 0,
        'WWW::Curl::Easy'                          => 0,
    },
    css_files          => {
        'htdocs/delete.png' => 'htdocs/delete.png',
        'htdocs/tides.css'  => 'htdocs/tides.css',
        'htdocs/tides.png'  => 'htdocs/tides.png',
    },
    install_path       => { htdocs => '/var/www/html' },
);
$build->add_build_element('tmpl');
$build->add_build_element('css');
$build->add_build_element('fna');
$build->create_build_script;
