
=head1 NAME

TIDES - Toolkit for Immunogenomic Data Exchange and Storage

=head1 SYNOPSIS

    use TIDES;
    my $app = TIDES->new;
    $app->run;

=head1 ABSTRACT

TIDES converts HLA data to GL Strings, registers the GL Strings with the
GL Service, and provides access to the GL Strings and sample information.

=cut

package TIDES;

use warnings;
use strict;
use base 'Titanium';
use TIDES::Collections;
use TIDES::Conexio;
use TIDES::Fusion;
use TIDES::HML;
use TIDES::Input;
use TIDES::Properties;
use TIDES::Samples;
use TIDES::Spreadsheet;
use TIDES::StripScan;
use TIDES::Vanilla;
use CGI::Application::Plugin::TT;
use CGI::Application::Plugin::Authentication;
use File::Temp;
use JSON;
use URI::Escape;
use WWW::Curl::Easy;
use Statistics::R;

=head1 VERSION

This document describes TIDES Version 3.02.

=cut

our $VERSION = '3.02';

=head1 DESCRIPTION

TIDES parses HLA data into GL Strings and stores the GL Strings with GL
Service. TIDES stores sample information, GL Strings, and the GL Service
URLs. The toolkit also provides for querying samples and exporting to
various immunogenomic analysis file formats.

=head1 METHODS

=head2 SUBCLASSED METHODS

=head3 cgiapp_init

Called automatically right before the setup().

=cut

sub cgiapp_init {
    my $c = shift;

    $c->dbh_config("dbi:Pg:dbname=tides", '', '', {AutoCommit => 0});
    return;

    # FIX: DB sessions
    $c->session_config(
        CGI_SESSION_OPTIONS => [
            'driver:postgresql;serializer:freezethaw',
            $c->query,
            { Handle => $c->dbh, ColumnType => 'binary' }
        ],
        COOKIE_PARAMS       => {
            -expires => '+4h',
            -secure  => 1,
        },
        DEFAULT_EXPIRY      => '+4h',
    );
}

=head3 setup

Sets up the run mode dispatch table and the start, error, and default run modes.
If the template path is not set, sets it to a default value.

=cut

sub setup {
    my $c = shift;
    my @protected_runmodes = qw/
        add_collection
        add_samples
        add_hla
        add_ngs
        delete
        input
        post
        save
        search
        export
    /;

    $c->start_mode('search');
    $c->error_mode('error');
    $c->run_modes([@protected_runmodes, 'login', 'logout']);

    for my $inc (@INC) {
        next unless -d "$inc/TIDES";
        $c->tt_include_path($inc);
        last;
    }
    $c->run_modes(AUTOLOAD => 'search');

    $c->authen->config(
        DRIVER => ['DBI',
            TABLE       => 'users',
            CONSTRAINTS => {
                'name'                 => '__CREDENTIAL_1__',
                'SHA1_base64:password' => '__CREDENTIAL_2__'
            },
            # FIX: Use COLUMNS and custom filter to implement salted SHA1
        ],
        STORE              => ['Cookie'],
        LOGIN_FORM         => { DISPLAY_CLASS => 'Basic' },
        LOGIN_RUNMODE      => 'login',
        LOGOUT_RUNMODE     => 'logout',
        POST_LOGIN_RUNMODE => $c->query->url(-absolute => 1),
    );
    $c->authen->protected_runmodes(@protected_runmodes);
    $c->param('properties', TIDES::Properties->new(dbh => $c->dbh));
    $c->param('collections', TIDES::Collections->new(dbh => $c->dbh));

    return;
}

=head3 teardown

Clean up.

=cut

sub teardown {
    my $c = shift;
    $c->session->flush if $c->session_loaded;
    $c->dbh->disconnect;
}

# Set up Template Toolkit singleton.
TIDES->tt_config(TEMPLATE_OPTIONS => {
    PRE_CHOMP => 1,
    POST_CHOMP => 1,
    VARIABLES  => { version => $VERSION },
});

=pod

TODO: Other methods inherited from CGI::Application go here.

=head2 RUN MODES

=head3 add_collection

  * Purpose: Define a new collection
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub add_collection {
    my $c = shift;
    my $q = $c->query;

    return $c->tt_process({
        title => 'Add Collection',
        form  => $q->start_multipart_form .
                 $q->b('New Collection: ') .
                 $q->textfield(-name => 'collection', -size => 40) .
                 $q->hidden(-name => 'rm', -value => 'add_samples', -override => 1) .
                 $q->submit(-label => 'Add') .
                 $q->end_form,
        url   => $q->url(-absolute => 1),
    });
}

=head3 add_samples

  * Purpose: Upload sample data
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub add_samples {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;

    my $collection = $q->param('collection');
    if ($collection) {
        my $sth = $dbh->prepare("INSERT INTO collections (name) VALUES (?)");
        $sth->execute($collection) or return $c->error($dbh->errstr);
        $collection = $dbh->last_insert_id(undef, undef, 'collections', undef);
        $dbh->commit or return $c->error($dbh->errstr);
    }

    my $collections = $c->param('collections');
    my %labels;
    for ($collections->get_names) {
        $labels{$collections->get_id($_)} = $_;
    }
    %labels or return $c->error('Please first define a Collection.');
    my @values = sort {$labels{$a} cmp $labels{$b}} keys %labels;

    return $c->tt_process({
        title => 'Add Sample Data',
        form  => $q->start_multipart_form .
                 $q->b('Sample File: ') .
                 $q->filefield(-name => 'file', -size => 20) .
                 $q->hidden(-name => 'rm', -value => 'input', -override => 1) .
                 $q->submit(-label => 'Add') . $q->br .
                 $q->b('Collection: ') .
                 $q->popup_menu(-name   => 'collection',
                                -class  => 'propertyselect',
                                -values => \@values,
                                -labels => \%labels) .
                 $q->end_form,
        props => $c->param('properties'),
        url   => $q->url(-absolute => 1),
    });
}

=head3 add_hla

  * Purpose: Upload HLA data
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub add_hla {
    my $c = shift;
    my $q = $c->query;

    my $collections = $c->param('collections');
    my %labels;
    for ($collections->get_names) {
        $labels{$collections->get_id($_)} = $_;
    }
    %labels or return $c->error('Please first define a Collection.');
    my @values = sort {$labels{$a} cmp $labels{$b}} keys %labels;

    return $c->tt_process({
        title => 'Add HLA Data',
        form  => $q->start_multipart_form .
                 $q->b('HLA File: ') .
                 $q->filefield(-name => 'file', -size => 20) .
                 $q->hidden(-name => 'rm', -value => 'save', -override => 1) .
                 $q->submit(-label => 'Add') . $q->br .
                 $q->b('Collection: ') .
                 $q->popup_menu(-name   => 'collection',
                                -class  => 'propertyselect',
                                -values => \@values,
                                -labels => \%labels) .
                 $q->end_form,
        url   => $q->url(-absolute => 1),
    });
}

=head3 save

  * Purpose: Save HLA data
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub save {
    my $c = shift;
    my $q = $c->query;

    my($tmpf, $mime) = $c->_get_file('file');
    ref $tmpf or return $c->error($tmpf);
    my $samples = _hla_parser($tmpf, $mime);
    ref $samples or return $c->error($samples);

    # FIX: Check for known samples here?
    my @ids = keys %$samples;
    my @gls = map { $$samples{$_}{gls} } @ids;
    my @gfe;
    for my $sample (@ids) {
        my $sample_gfe = $$samples{$sample}{gfe};
        $sample_gfe or $$samples{$sample}{n_gfe} = 0, next;

        my @seqs;
        for my $locus (sort keys %$sample_gfe) {
            push @seqs, map { "$locus:$_" } sort keys %{$$sample_gfe{$locus}};
        }
        push @gfe, join ',', @seqs;
        $$samples{$sample}{n_gfe} = scalar @seqs;
    }
    my $imgt = _imgt_version(\@gls);

    return $c->tt_process({
        title   => 'Parsed Output',
        samples => $samples,
        imgt    => $imgt,
        form    => $q->start_form .
                   $q->hidden(-name => 'collection') .
                   $q->hidden(-name => 'ids', -value => \@ids) .
                   $q->hidden(-name => 'gls', -value => \@gls) .
                   $q->hidden(-name => 'gfe', -value => \@gfe) .
                   $q->hidden(-name => 'imgt', -value => $imgt) .
                   $q->hidden(-name => 'rm', -value => 'post', -override => 1) .
                   $q->submit(-label => 'Commit to TIDES and the GL and GFE Services') .
                   $q->end_form .
                   $q->start_form .
                   $q->hidden(-name => 'rm', -value => 'add_hla', -override => 1) .
                   $q->submit(-label => 'Cancel') .
                   $q->end_form,
        url     => $q->url(-absolute => 1),
    });
}

=head3 post

  * Purpose: Commit HLA data to GL Service and the DB
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub post {
    my $c = shift;
    my $q = $c->query;
    my @names = $q->multi_param('ids'); # FIX? names/ids mismatch
    my @gls = $q->multi_param('gls');
    my @gfe = $q->multi_param('gfe');

    my $dbh = $c->dbh;
    my $sth = $dbh->prepare(qq{
        INSERT INTO uploads (who) SELECT id FROM users WHERE name = ?
    }) or return $c->error($dbh->errstr);
    $sth->execute($c->authen->username) or return $c->error($dbh->errstr);
    my $upload = $dbh->last_insert_id(undef, undef, 'uploads', undef);

    my $collection = $q->param('collection');
    my $db_samples = TIDES::Samples->new(dbh        => $dbh,
                                         collection => $collection,
                                         upload     => $upload);
    my $collection_name = $c->param('collections')->get_name($collection);
    my %samples;
    for my $name (@names) {
        my $id = $db_samples->get($name)
            or return $c->error("Cannot add or retrieve sample $name.");
        $samples{$id}{name}       = $name;
        $samples{$id}{collection} = $collection_name;
        $samples{$id}{gls}        = shift @gls;
        $samples{$id}{gfe_seqs}   = shift @gfe;
    }

    my $ret = $c->_post_gl_service(\%samples, $upload);
    return $ret if $ret;
    $ret = $c->_post_gfe_service(\%samples, $upload);
    return $ret if $ret;
    $ret = $c->_store_loci(\%samples);
    return $ret if $ret;
    $dbh->commit or return $c->error($dbh->errstr);

    return $c->tt_process({
        title   => 'Uploaded Data',
        samples => \%samples,
        url     => $q->url(-absolute => 1),
    });
}

=head3 search

  * Purpose: Query HLA data
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub search {
    my $c = shift;
    my $q = $c->query;

    # Add criterion if specified.
    if (defined $q->param('val')) {
        if ($q->param('op')) {
            # property type != fixed
            $q->append('props', scalar $q->param('property'));
            $q->append('ops',   scalar $q->param('op'));
            $q->append('vals',  join("\n", $q->multi_param('val')));
        } else {
            # property type == fixed
            $q->append('props', scalar $q->param('property'));
            $q->append('ops',   '');
            $q->append('vals',  join("\n", $q->multi_param('val')));
        }
    }

    if ($q->param('submit')) {
        for (scalar $q->param('submit')) {
            /^Add$/    and return $c->_search_add;
            /^Search$/ and return $c->_search_list;
        }
    }

    # Process delete button click.
    for ($q->param) {
        next unless /^delete(\d+)\.x/;
        for my $p ('props', 'ops', 'vals') {
            my @v = $q->param($p);
            splice @v, $1, 1;
            if (@v) {
                $q->param($p, @v);
            } else {
                $q->delete($p);
            }
        }
        last;
    }

    # We're adding the first search criterion.
    my $p = $c->param('properties');
    my %labels;
    for my $name (sort $p->get_names) {
        $labels{$p->get_id($name)} = $name;
    }
    $labels{name} = 'Sample Name';
    $labels{collection} = 'Collection';
    my @values = sort {$labels{$a} cmp $labels{$b}} keys %labels;

    return $c->tt_process({
        title => 'Search HLA Data',
        form  => $q->start_multipart_form .
                 $q->popup_menu(-name   => 'property',
                                -class  => 'propertyselect',
                                -values => \@values,
                                -labels => \%labels) .
                 $q->hidden('props') .
                 $q->hidden('ops') .
                 $q->hidden('vals') .
                 $q->hidden('rm') .
                 $q->submit('submit', 'Add') .
                 $q->submit('submit', 'Search') .
                 $c->_search_criteria(1) .
                 $q->end_form,
        url   => $q->url(-absolute => 1),
    });
}

=head3 input

  * Purpose: Input sample data
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub input {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;

    my($tmpf, $mime) = $c->_get_file('file');
    ref $tmpf or return $c->error($tmpf);
    my $ss = TIDES::Spreadsheet->new(file => $tmpf, mime => $mime);
    ref $ss or return $c->error($ss);
    my $samples = TIDES::Input->new(worksheet => $ss->worksheet)->parse;

    my $sth = $dbh->prepare(qq{
        INSERT INTO uploads (who) SELECT id FROM users WHERE name = ?
    }) or return $c->error($dbh->errstr);
    $sth->execute($c->authen->username) or return $c->error($dbh->errstr);
    my $upload = $dbh->last_insert_id(undef, undef, 'uploads', undef);

    my $collection = $q->param('collection');
    my $db_samples = TIDES::Samples->new(dbh        => $dbh,
                                         collection => $collection,
                                         upload     => $upload);
    my $p = $c->param('properties');
    my %props;
    for ($p->get_names) {
        $props{lc $_} = $p->get_id($_);
    }

    # 'Sample Name' is special.
    my(@cols, %add, @skip, $name_col);
    for (keys %$samples) {
        my $sample = $$samples{$_};
        @cols or do {
            @cols = sort keys %$sample;
            for (@cols) {
                if (/^sample name$/i) {
                    $name_col = $_;
                    next;
                }

                # Don't allow specification of the Locus property.
                my $p_id = $props{lc $_};
                if ($p_id && !/^locus$/i) {
                    $add{$_} = $p_id;
                } else {
                    push @skip, $_;
                }
            }
            last unless $name_col && %add;
        };

        my $name = $$sample{$name_col};
        my $s_id = $db_samples->get($name)
            or return $c->error("Cannot add or retrieve sample $name.");
        for my $field (keys %add) {
            my $p_id = $add{$field};
            my $type = $p->get_type($p_id);
            my $val  = $$sample{$field};

            if ($type eq 'fixed') {
                my $sth = $dbh->prepare(qq{
                    SELECT id FROM fixed_values
                    WHERE property = ? AND LOWER(value) = LOWER(?)
                });
                $sth->execute($p_id, $val) or return $c->error($dbh->errstr);
                ($val) = $sth->fetchrow_array;
                $val or return $c->error("$val is not allowed for $field.");

                $sth = $dbh->prepare(qq{
                    INSERT INTO sample_fixed_properties VALUES (?,?)
                });
                $sth->execute($s_id, $val) or return $c->error($dbh->errstr);
                next;
            }

            my $sth = $dbh->prepare(qq{
                INSERT INTO sample_${type}_properties VALUES (?,?,?)
            });
            $sth->execute($s_id, $p_id, $val) or return $c->error($dbh->errstr);
        }
    }
    $dbh->commit or return $c->error($dbh->errstr);
    $add{'Sample Name'} = 0;

    return $c->tt_process({
        title   => 'Added Sample Data',
        count   => scalar(keys %$samples),
        added   => [ sort keys %add ],
        skipped => \@skip,
        url     => $q->url(-absolute => 1),
    });
}

=head3 export

  * Purpose: Export HLA data
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub export {
    my $c = shift;
    my $q = $c->query;

    for (scalar $q->param('submit')) {
        /Sampl/ and return $c->samples;
        /GL/    and return $c->g_l_strings;
        /PLINK/ and return $c->plink;
        /PyPop/ and return $c->pypop;
    }

    return $c->error("Unknown export format");
}

=head3 delete

  * Purpose: Delete uploaded data
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub delete {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;

    # Process delete button click.
    for ($q->param) {
        next unless /^delete(\d+)\.x/;

        # Only allow deletes by the uploading user.
        my $sth = $dbh->prepare(qq{
            SELECT name FROM users
            WHERE id = (SELECT who FROM uploads WHERE id = ?)
        });
        $sth->execute($1) or return $c->error($dbh->errstr);
        my($name) = $sth->fetchrow_array;
        $name eq $c->authen->username or return $c->error(qq{
            Deletions are limited to the account that uploaded the data.
        });

        # Authorized. Delete.
        $sth = $dbh->prepare("DELETE FROM uploads WHERE id = ?");
        $sth->execute($1) or return $c->error($dbh->errstr);
        $dbh->commit or return $c->error($dbh->errstr);
        last;
    }

    my @rows = ($q->th(['Uploader', 'Time', 'Type', 'Count', 'Delete']));
    my $sth = $dbh->prepare("SELECT * FROM v_uploads");
    $sth->execute or return $c->error($dbh->errstr);

    my %row;
    $sth->bind_columns(\(@row{ @{$sth->{NAME_lc}} }));
    while ($sth->fetch) {
        push @rows, $q->td([
            $row{name},
            $row{time},
            $row{type},
            $row{count},
            $q->image_button(-name  => "delete$row{id}",
                             -class => 'deletebutton',
                             -src   => '/delete.png',
                             -align => 'middle')
        ]);
    }

    return $c->tt_process({
        title => 'Delete Data',
        form  => $q->start_multipart_form .
                 $q->hidden('rm') .
                 $q->table($q->Tr(\@rows)) .
                 $q->end_form,
        url   => $q->url(-absolute => 1),
    });
}

=head3 login

  * Purpose: Log in.
  * Expected parameters: None
  * Function on success
  * Function on failure

=cut

sub login {
    my $c = shift;
    return $c->tt_process({
        url => $c->query->url(-absolute => 1),
    });
}

=head3 logout

  * Purpose: Log out.
  * Expected parameters: None
  * Function on success
  * Function on failure

=cut

sub logout {
    my $c = shift;
    $c->authen->logout;
    return $c->redirect($c->query->url);
}

=head2 OTHER METHODS

=head3 samples

  * Purpose: Output sample annotations
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub samples {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;
    $c->header_add(-type => 'text/plain', -attachment => 'samples.txt');

    my @ids = $q->multi_param('samples');
    my $ssh = $dbh->prepare(qq{SELECT name FROM samples WHERE id = ?});
    my $sfh = $dbh->prepare(qq{
        SELECT fv.property, fv.value
            FROM sample_fixed_properties sp
                JOIN fixed_values fv ON fv.id = sp.fixed_value
                JOIN properties p ON p.id = fv.property
        WHERE sample = ? AND p.name != 'Locus'
    });
    my $sth = $dbh->prepare(qq{
        SELECT * FROM sample_text_properties WHERE sample = ?
    });
    my $snh = $dbh->prepare(qq{
        SELECT * FROM sample_numeric_properties WHERE sample = ?
    });
    my $sdh = $dbh->prepare(qq{
        SELECT * FROM sample_date_properties WHERE sample = ?
    });

    my(%samples, %properties);
    for my $id (@ids) {
        # name
        $ssh->execute($id) or return $c->error($dbh->errstr);
        $samples{$id}{name} = ($ssh->fetchrow_array)[0];

        # fixed, text, numeric, date properties
        # Assume sample-property is one-to-one. Locus is the only exception,
        # and we're skipping Locus for this report.
        for ($sfh, $sth, $snh, $sdh) {
            $_->execute($id) or return $c->error($dbh->errstr);

            my %row;
            $_->bind_columns(\(@row{ @{$_->{NAME_lc}} }));
            while ($_->fetch) {
                $samples{$id}{$row{property}} = $row{value};
                $properties{$row{property}} = 1;
            }
        }
    }

    my @hdr = ('Sample Name');
    my @prop_ids = sort {$a <=> $b} keys %properties;
    my $sph = $dbh->prepare(qq{SELECT name FROM properties WHERE id = ?});
    for (@prop_ids) {
        $sph->execute($_) or return $c->error($dbh->errstr);
        push @hdr, ($sph->fetchrow_array)[0];
    }

    my @ret = (join "\t", @hdr);
    unshift @prop_ids, 'name';
    for my $id (@ids) {
        my @line;
        for (@prop_ids) {
            push @line, exists $samples{$id}{$_} ? $samples{$id}{$_} : '';
        }
        push @ret, join "\t", @line;
    }

    return join "\n", @ret;
}

=head3 plink

  * Purpose: Output PLINK format
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub plink {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;
    $c->header_add(-type => 'text/plain', -attachment => 'plink.txt');

    my @ids = $q->multi_param('samples');
    my $qs = join ',', ('?') x @ids;
    my $sth = $dbh->prepare("SELECT * FROM v_plink WHERE individual IN ($qs)");
    $sth->execute(@ids) or return $c->error($dbh->errstr);
    my $r = $sth->fetchall_arrayref;

    if (@$r == 0) {
        return <<_EOD_;
The PLINK export contains no data. PLINK export requires the following sample annotations: Family ID, Paternal ID, Maternal ID, Sex, and Phenotype. Any samples without these annotations will not be exported.
_EOD_
    }

    # PyPop-format genotype data
    my $data = $c->_gl_to_pypop;
    my $loci = shift @$data;
    my $hdr = join ' ',
        'family_id',
        'individual_id',
        'paternal_id',
        'maternal_id',
        'sex',
        'phenotype',
        $loci =~ s/\t/ /gr;

    # Each ID may have multiple genotypes. Discard the sample name.
    my %id2pypop;
    for (@$data) {
        push @{$id2pypop{$$_[0]}}, $$_[2] =~ s/\t/ /gr;
    }

    my @ret = ($hdr);
    for my $plink (@$r) {
        # Second field is the ID.
        for (@{$id2pypop{$$plink[1]}}) {
            push @ret, join ' ', @$plink, $_;
        }
    }

    return join "\n", @ret;
}

=head3 pypop

  * Purpose: Output PyPop format
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub pypop {
    my $c = shift;
    $c->header_add(-type => 'text/plain', -attachment => 'pypop.txt');

    my $data = $c->_gl_to_pypop;
    my $hdr = "id\t" . shift @$data;
    return join "\n", $hdr, map { "$$_[1]\t$$_[2]" } @$data;
}

=head3 g_l_strings

  * Purpose: Output GL String export
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub g_l_strings {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;
    $c->header_add(-type => 'text/plain', -attachment => 'gls.txt');

    my @ids = $q->multi_param('samples');
    my $qs = join ',', ('?') x @ids;
    my $sth = $dbh->prepare(qq{
        SELECT s.name AS sample, c.name AS collection, g.uri, g.str
        FROM samples s JOIN g_l_strings g ON g.sample = s.id
                       JOIN collections c ON c.id = s.collection
        WHERE s.id in ($qs)
    });
    $sth->execute(@ids) or return $c->error($dbh->errstr);

    my $hdr = join "\t", 'sample', 'collection', 'GL Service URI', 'GL String';
    my(@data, $sample, $collection, $uri, $gl);
    $sth->bind_columns(\$sample, \$collection, \$uri, \$gl);
    while ($sth->fetch) {
        push @data, join "\t", $sample, $collection, $uri, $gl;
    }
    return join "\n", $hdr, @data;
}

=head3 error

  * Purpose: Display an error.

=cut

sub error {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;

    # just in case we're in a transaction
    $dbh->rollback;

    return $c->tt_process('TIDES/error.tmpl', {
        title => 'Error',
        msg   => shift,
        url   => $q->url(-absolute => 1),
    });
}

=head2 PRIVATE METHODS

=head3 _get_file

  * Purpose: Input sample data
  * Expected parameters
  * Function on success: Returns filehandle and MIME type
  * Function on failure: Returns error string

=cut

sub _get_file {
    my($c, $field) = @_;
    my $q = $c->query;

    my $file = $q->upload($field);
    $file or return 'Please select a file before clicking Upload.';

    my($bytes_i, $bytes_n, $buf);
    my $bufsize = 1024;
    my $limit_mb = 50; # 50MB limit
    my $limit = $limit_mb * 1024 * 1024;
    my $tmpf = File::Temp->new;
    while ($bytes_i = read($file, $buf, $bufsize)) {
        $bytes_n += $bytes_i;
        last if $bytes_n > $limit;
        print $tmpf $buf;
    }
    $tmpf->seek(0, SEEK_SET);

    defined($bytes_i) or return 'Read failure';
    defined($bytes_n) or return "Could not read $file, or the file was empty.";
    $bytes_n > $limit and return "File exceeds size limit of ${limit_mb}MB.";

    return ($tmpf, $q->uploadInfo($file)->{'Content-Type'});
}

=head3 _get_locus_ids

  * Purpose: Return locus property values. Add to DB if necessary.
  * Expected parameters: hashref with loci as keys
  * Function on success: Returns hashref of locus => fixed_values ID
  * Function on failure:

=cut

sub _get_locus_ids {
    my($c, $loci) = @_;
    my $dbh = $c->dbh;

    my $prop_id = $c->param('properties')->get_id('Locus');
    my $sh = $dbh->prepare(qq{
        SELECT id FROM fixed_values WHERE property = $prop_id AND value = ?
    });
    my($ih, %ids);
    for my $locus (keys %$loci) {
        $sh->execute($locus) or return $c->error($dbh->errstr);
        my($id) = $sh->fetchrow_array;
        unless ($id) {
            $ih = $dbh->prepare(qq{
                INSERT INTO fixed_values (property,value) VALUES ($prop_id,?)
            }) unless $ih;
            $ih->execute($locus) or return $c->error($dbh->errstr);
            $id = $dbh->last_insert_id(undef, undef, 'fixed_values', undef);
        }
        $ids{$locus} = $id;
    }

    return \%ids;
}

=head3 _hla_parser

  * Purpose: Figure out the HLA data format, and call the correct parser.
  * Function on success: Returns hashref of sample_ID => GL String
  * Function on failure: Returns error string

=cut

sub _hla_parser {
    my($file, $mime) = @_;

    for ($mime) {
        /^text\/plain$/ and return TIDES::StripScan->new(fh => $file)->parse;
        /^text\/xml$/   and return TIDES::HML->new(fh => $file)->parse;
        /^application\/octet-stream$/ and return <<_EOD_;
Your browser does not know the type of file you selected. Please change
the file type, for instance by changing the file extension according to
the values on the previous page, then retry the submission.
_EOD_
    }

    my $ss = TIDES::Spreadsheet->new(file => $file, mime => $mime);
    ref $ss or return 'TIDES::Spreadsheet: ' . $ss;
    my $ws = $ss->worksheet;
    for ($ss->type) {
        /^conexio$/ and return TIDES::Conexio->new(worksheet => $ws)->parse;
        /^fusion$/  and return TIDES::Fusion->new(worksheet => $ws)->parse;
        /^vanilla$/ and return TIDES::Vanilla->new(worksheet => $ws)->parse;
    }
    return "Unable to determine type of data in spreadsheet.";
}

=head3 _g_l_string_loci

  * Purpose: Extract loci from a GL String.

=cut

sub _g_l_string_loci {
    my $str = shift;
    my %loci;
    for (split /\^/, $str) {
        for (split /\|/) {
            for (split /\+/) {
                for (split /~/) {
                    for (split /\//) {
                        s/\*.*//;
                        $loci{$_} = 1;
                    }
                }
            }
        }
    }
    return [ keys %loci ];
}

=head3 _imgt_version

  * Purpose: Determine IMGT HLA version for an arrayref of GL Strings
  * Function on success: Returns IMGT version string
  * Function on failure:

=cut

sub _imgt_version {
    my $gls = shift;

    # Taint mode
    $ENV{PATH} = '/bin:/usr/bin';
    delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

    my $r = Statistics::R->new;

    # Passing the arrayref directly results in the strings being double-quoted!
    $r->set('gls', [ @$gls ]);

    my $cmds = <<_EOD_;
library(disambiguateR)
loadHLAdata()
ver <- guessimgtversion(gls)
_EOD_
    $r->run($cmds);

    my $ver = $r->get('ver');
    return 'nonstrict' if $ver eq 'NA';
    my($rel, $maj, $min) = $ver =~ /(\d)(\d{2})(\d)/;
    return "imgt-hla/$rel.$maj.$min";
}

=head3 _post_gl_service

  * Purpose: POST GL Strings to GL Service and the DB
  * Expected parameters: samples hashref, upload ID
  * Function on success: Returns 0. URI in $samples{id}{gls_uri}.
  * Function on failure: Returns error message

=cut

sub _post_gl_service {
    my($c, $samples, $upload) = @_;

    my $response;
    open(my $fp, ">", \$response) or return $c->error($!);

    my $q = $c->query;
    my $imgt = $q->param('imgt');
    my $gl_service = $c->param('gl_service');
    $gl_service .= "$imgt/multilocus-unphased-genotype";

    my $curl = WWW::Curl::Easy->new;
    $curl->setopt(CURLOPT_URL, $gl_service);
    $curl->setopt(CURLOPT_HEADER, 1);
    $curl->setopt(CURLOPT_POST, 1);
    $curl->setopt(CURLOPT_HTTPHEADER, ['content-type: text/plain']);
    $curl->setopt(CURLOPT_WRITEDATA, $fp);

    my $dbh = $c->dbh;
    $dbh->do("COPY g_l_strings(sample,str,uri,upload) FROM STDIN")
        or return $c->error($dbh->errstr);

    for my $id (keys %$samples) {
        if ($response) {
            # Reset output.
            $response = '';
            seek($fp, 0, 0);
        }

        my $str = $$samples{$id}{gls};
        $curl->setopt(CURLOPT_POSTFIELDS, $str);
        my $ret = $curl->perform;
        if ($ret) {
            return $c->error('Communication with GL Service: ' . $curl->strerror($ret));
        }

        my($uri) = $response =~ /\nLocation: (\S+)/;
        unless ($uri) {
            ($$samples{$id}{gls_err}) = $response =~ /\r\n\r\n(.+)$/;
            next;
        }

        $$samples{$id}{gls_uri} = $uri;
        $dbh->pg_putcopydata("$id\t$str\t$uri\t$upload\n");

        # Extract loci.
        $$samples{$id}{loci} = _g_l_string_loci($str);
    }
    $dbh->pg_putcopyend or return $c->error($dbh->errstr);
    close $fp or return $c->error($!);

    return 0;
}

=head3 _post_gfe_service

  * Purpose: POST sequences to GFE Service and the DB
  * Expected parameters: samples hashref, upload ID
  * Function on success: Returns 0. GFEs in $$samples{id}{gfe}.
  * Function on failure: Returns error message

=cut

sub _post_gfe_service {
    my($c, $samples, $upload) = @_;

    my $response;
    open(my $fp, ">", \$response) or return $c->error($!);

    my $curl = WWW::Curl::Easy->new;
    $curl->setopt(CURLOPT_URL, $c->param('gfe_service'));
    $curl->setopt(CURLOPT_POST, 1);
    $curl->setopt(CURLOPT_HTTPHEADER, ['content-type: application/json']);
    $curl->setopt(CURLOPT_WRITEDATA, $fp);

    my $dbh = $c->dbh;
    $dbh->do("COPY gfes(sample,gfe,upload) FROM STDIN")
        or return $c->error($dbh->errstr);

    for my $id (keys %$samples) {
        next unless $$samples{$id}{gfe_seqs};
        for (split /,/, $$samples{$id}{gfe_seqs}) {
            if ($response) {
                # Reset output.
                $response = '';
                seek($fp, 0, 0);
            }

            my($loc, $seq) = split /:/;
            my $json = encode_json({locus => $loc, sequence => $seq});
            $curl->setopt(CURLOPT_POSTFIELDS, $json);
            my $ret = $curl->perform;
            $ret and return $c->error('Communication with GFE Service: ' . $curl->strerror($ret));

            my $res = decode_json($response);
            $$res{Message} and return $c->error("GFE Service: $$res{Message}");
            $$res{gfe}     or  return $c->error('No GFE from GFE Service');

            push @{$$samples{$id}{gfe}}, $$res{gfe};
            $dbh->pg_putcopydata("$id\t$$res{gfe}\t$upload\n");
        }
    }
    $dbh->pg_putcopyend or return $c->error($dbh->errstr);
    close $fp or return $c->error($!);

    return 0;
}

=head3 _store_loci

  * Purpose: Store loci for the GL Strings
  * Expected parameters
  * Function on success: Returns 0
  * Function on failure: Returns error message

=cut

sub _store_loci {
    my($c, $samples) = @_;

    # Get loci for the samples.
    my %loci;
    for my $s_id (keys %$samples) {
        for (@{$$samples{$s_id}{loci}}) {
            $loci{$_} = 1;
        }
    }
    %loci or return $c->error('No loci in GL Strings');

    # Get Locus fixed_values.
    my $locus_ids = $c->_get_locus_ids(\%loci);
    return $locus_ids unless ref $locus_ids;

    # Record loci for the GL Strings.
    my $dbh = $c->dbh;
    my $sh = $dbh->prepare(qq{
        SELECT sample FROM sample_fixed_properties
        WHERE sample = ? AND fixed_value = ?
    });
    my $ih;
    for my $s_id (keys %$samples) {
        for (@{$$samples{$s_id}{loci}}) {
            # Check if sample already has data for this locus.
            my $locus_id = $$locus_ids{$_};
            $sh->execute($s_id, $locus_id) or return $c->error($dbh->errstr);
            next if $sh->fetch;

            # Add locus for this sample.
            $ih = $dbh->prepare(qq{
                INSERT INTO sample_fixed_properties VALUES (?,?)
            }) unless $ih;
            $ih->execute($s_id, $locus_id) or return $c->error($dbh->errstr);
        }
    }

    return 0;
}

=head3 _search_add

  * Purpose: Add criterion for a search
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub _search_add {
    my $c = shift;
    my $r = shift;
    my $q = $c->query;
    my $p = $c->param('properties');

    my $add_id = $q->param('property');
    my($add_type, $add_name);
    for ($add_id) {
        /^name$/       and $add_type = 'text',  $add_name = 'Sample Name', last;
        /^collection$/ and $add_type = 'fixed', $add_name = 'Collection',  last;
        $add_type = $p->get_type($add_id);
        $add_name = $p->get_name($add_id);
    }
    $add_type or return $c->error("Unknown property ID $add_id");

    # Allow type-based specification of criterion value.
    my $choices;
    if ($add_type eq 'fixed') {
        my $dbh = $c->dbh;
        my $l;
        if ($add_id eq 'collection') {
            $l = $dbh->selectall_arrayref("SELECT id, name FROM collections");
        } else {
            my $sth = $dbh->prepare(q{
                SELECT id, value FROM fixed_values WHERE property = ?
            });
            $sth->execute($add_id) or return $c->error($dbh->errstr);
            $l = $sth->fetchall_arrayref;
        }

        my %labels;
        for (@$l) {
            my($id, $val) = @$_;
            $id = "$id\t$val";
            $labels{$id} = $val;
        }
        my @values = sort {$labels{$a} cmp $labels{$b}} keys %labels;

        $choices = $q->scrolling_list(-name => 'val',
                                      -values => \@values,
                                      -multiple => 'true',
                                      -labels => \%labels);
    } else {
        my $num_ops = ['<', '<=', '=', '>=', '>'];
        for ($add_type) {
            /^text$/    and $choices = $q->popup_menu('op', ['=', 'contains']);
            /^numeric$/ and $choices = $q->popup_menu('op', $num_ops, '=');
            /^date$/    and $choices = $q->popup_menu('op', $num_ops, '>');
        }
        $choices .= $q->textfield('val');
    }

    return $c->tt_process('TIDES/search.tmpl', {
        title => 'Search HLA Data',
        form  => $q->start_multipart_form .
                 $q->b($add_name) . ' ' .
                 $choices .
                 $q->hidden('property') .
                 $q->hidden('props') .
                 $q->hidden('ops') .
                 $q->hidden('vals') .
                 $q->hidden('rm') .
                 $q->submit('submit', 'Add Another') .
                 $q->submit('submit', 'Search') .
                 $c->_search_criteria(1) .
                 $q->end_form,
        url   => $q->url(-absolute => 1),
    });
}

=head3 _search_criteria

  * Purpose: List critera for a search
  * Expected parameters: 0 or 1 to indicate output of delete buttons
  * Function on success
  * Function on failure

=cut

sub _search_criteria {
    my($c, $del_button) = @_;
    my $q = $c->query;
    my $p = $c->param('properties');

    my @props = $q->multi_param('props');
    return '' unless @props;

    my @ops = $q->multi_param('ops');
    my @vals = $q->multi_param('vals');

    my @li;
    my $i = 0;
    while (@props) {
        my $prop = shift @props;
        my $op   = shift @ops;
        my $val  = shift @vals;

        my $name;
        for ($prop) {
            /^name$/       and $name = 'Sample Name', last;
            /^collection$/ and $name = 'Collection', last;
            $name = $p->get_name($prop);
        }

        my $cond;
        if ($op) {
            $cond = "$name $op $val";
        } else {
            # type is 'fixed'
            my @sel;
            for (split /\n/, $val) {
                my($id, $desc) = split /\t/, $_, 2;
                push @sel, $desc;
            }
            $cond = "$name is " . join(' or ', @sel);
        }
        $cond .= $q->image_button(-name  => "delete$i",
                                  -class => 'deletebutton',
                                  -src   => '/delete.png',
                                  -align => 'middle') if $del_button;
        push @li, $cond;
        $i++;
    }
    return $q->p('Search criteria:') . $q->ol($q->li(\@li));
}

=head3 _search_list

  * Purpose: List HLA data from a search
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub _search_list {
    my $c = shift;
    my $q = $c->query;
    my $p = $c->param('properties');
    my $dbh = $c->dbh;

    my @props = $q->multi_param('props');
    my @ops = $q->multi_param('ops');
    my @vals = $q->multi_param('vals');

    my(@q, @q_vals, @where, @where_vals);
    while (@props) {
        my $prop  = shift @props;
        my $op    = shift @ops;
        my $val   = shift @vals;

        if ($op && $op eq 'contains') {
            $op = 'LIKE';
            $val = "%$val%";
        }

        if ($prop eq 'name') {
            push @where, "s.name $op ?";
            push @where_vals, $val;
            next;
        }
        if ($prop eq 'collection') {
            my @ids;
            for (split /\n/, $val) {
                s/\t.*//;
                push @ids, $_;
            }
            push @where, "c.id IN (" . join(',', ('?') x @ids) . ')';
            push @where_vals, @ids;
            next;
        }

        # properties tables
        my $type  = $p->get_type($prop);
        my $table = "sample_${type}_properties";
        if ($op) {
            # FIX: filter $op
            push @q, "SELECT sample FROM $table WHERE property = ? AND value $op ?";
            push @q_vals, $prop, $val;
        } else {
            # type is 'fixed'
            my @ids;
            for (split /\n/, $val) {
                s/\t.*//;
                push @ids, $_;
            }
            push @q, "SELECT sample FROM $table WHERE property = ? AND value IN (" . join(',', ('?') x @ids) . ')';
            push @q_vals, $prop, @ids;
        }
    }

    my $prop_sql = '';
    if (@q) {
        my $intersect = join ' INTERSECT ', @q;
        $prop_sql = "JOIN ($intersect) q ON q.sample = s.id";
    }

    my $where_sql = @where ? 'WHERE ' . join(' AND ', @where) : '';

    # URIs and GFEs may be duplicated with this query. Resolved below.
    my $sth = $dbh->prepare(qq{
        SELECT s.id, c.name AS collection, s.name, uri, gfe FROM samples s
            $prop_sql
            LEFT JOIN g_l_strings gl ON gl.sample = s.id
            LEFT JOIN gfes gf ON gf.sample = s.id
            JOIN collections c ON c.id = s.collection
            $where_sql
    });
    $sth->execute(@q_vals, @where_vals) or return $c->error($dbh->errstr);

    my(%samples, %row, %uris, %gfes);
    $sth->bind_columns(\(@row{ @{$sth->{NAME_lc}} }));
    while ($sth->fetch) {
        $samples{$row{id}}{name} = $row{name};
        $samples{$row{id}}{collection} = $row{collection};
        $row{uri} and $uris{$row{id}}{$row{uri}} = 1;
        $row{gfe} and $gfes{$row{id}}{$row{gfe}} = 1;
    }
    for (keys %samples) {
        # undef gls_uri or gfe prints default message in template
        $samples{$_}{gls_uri} = $uris{$_} ? [ sort keys %{$uris{$_}} ] : [];
        $samples{$_}{gfe}     = $gfes{$_} ? [ sort keys %{$gfes{$_}} ] : [];
    }

    return $c->tt_process('TIDES/post.tmpl', {
        title   => 'Samples',
        samples => \%samples,
        form    => $c->_search_criteria(0) .
                   $q->start_form .
                   $q->hidden(-name => 'samples', -value => [ keys %samples ]) .
                   $q->hidden(-name => 'rm', -value => 'export', -override => 1) .
                   $q->submit('submit', 'Export Sample Annotations') .
                   $q->submit('submit', 'Export GL Strings') .
                   $q->submit('submit', 'Export to Modified PLINK Format') .
                   $q->submit('submit', 'Export to PyPop Format') .
                   $q->end_form,
        url     => $q->url(-absolute => 1),
    });
}

=head3 _gl_to_pypop

  * Purpose: Return data for PyPop format
  * Expected parameters
  * Function on success: Returns arrayref of [ id, name, pypop ]
  * Function on failure

=cut

sub _gl_to_pypop {
    my $c = shift;
    my $q = $c->query;
    my $dbh = $c->dbh;

    my @ids = $q->multi_param('samples');
    my $qs = join ',', ('?') x @ids;
    my $sth = $dbh->prepare(qq{
        SELECT g.id AS gl_id, s.id AS sample_id, s.name, g.str
            FROM samples s JOIN g_l_strings g ON g.sample = s.id
        WHERE s.id in ($qs)
    });
    $sth->execute(@ids) or return $c->error($dbh->errstr);

    # We're retrieving GL String IDs here since the same sample may have
    # multiple (and currently possibly identical) GL Strings.
    my(%row, %alleles, %names, %loci, %sample_ids);
    $sth->bind_columns(\(@row{ @{$sth->{NAME_lc}} }));
    while ($sth->fetch) {
        my $id = $row{gl_id};
        $names{$id} = $row{name};
        $sample_ids{$id} = $row{sample_id};

        for (split /\^/, $row{str}) {
            for (split /\|/) {
                # Some homozygotes have only a single allele.
                my @alleles = split /\+/;
                @alleles == 1 and push @alleles, $alleles[0];
                for my $allele (@alleles) {
                    my $locus;
                    # FIX: how handle haplotype data?
                    #for (split /~/, $type) {
                        for (split /\//) {
                            # Take first locus identifier.
                            ($locus) = split /\*/;
                            $loci{$locus} = 1;
                            last;
                        }
                    #}
                    # Strip locus identifiers.
                    $allele =~ s%[^~/]+\*%%g;
                    push @{$alleles{$id}{$locus}}, $allele;
                }
            }
        }
    }

    my @loci_sorted = sort keys %loci;
    my @data;
    push @data, join "\t", map {("${_}_1", "${_}_2")} @loci_sorted;
    for my $id (sort {$names{$a} cmp $names{$b}} keys %names) {
        # Genotype lists (|-delimited) trigger extra lines for same sample.
        my $repeat;
        do {
            $repeat = 0;
            my @pypop;
            for (@loci_sorted) {
                my $locus_alleles = $alleles{$id}{$_};
                $locus_alleles or push(@pypop, ('****') x 2), next;
                push @pypop, @{$locus_alleles}[0,1];
                if (!$repeat && @$locus_alleles > 2) {
                    $repeat = 1;
                    splice @$locus_alleles, 0, 2;
                }
            }
            push @data, [ $sample_ids{$id}, $names{$id}, join "\t", @pypop ];
        } while $repeat;
    }

    return \@data;
}

=head1 BUGS AND LIMITATIONS

There are no known problems with this module.

=head1 SEE ALSO

L<CGI::Application>

=head1 THANKS

Dr. Jill Hollenbach, University of California San Francisco (UCSF)
Dr. Steve Mack, Children's Hospital Oakland Research Institute (CHORI)

=head1 AUTHOR

Ken Yamaguchi, C<< <ken at knowledgesynthesis.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2018 Knowledge Synthesis Inc., all rights reserved.

This program is released under the following license: gpl

The full text of the license can be found in the LICENSE file included
with this distribution.

=cut

1;

__END__
