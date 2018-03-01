
=head1 NAME

TIDES::Spreadsheet - Spreadsheet parser

=head1 SYNOPSIS

    TIDES::Spreadsheet is an abstract class.  See TIDES::Fusion or
    TIDES::Conexio.

=head1 ABSTRACT

Parse Spreadsheet data into GL Strings.

=cut

package TIDES::Spreadsheet;

use warnings;
use strict;
use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;

=head1 PUBLIC METHODS

=head2 new

  * Purpose: Parse spreadsheet data
  * Expected parameters:
        file: filehandle or filename
        mime: MIME type
  * Function on success: returns hashref of Sample IDs to GL Strings
  * Function on failure: returns undef

=cut

sub new {
    my($type, %params) = @_;
    my $file = $params{file};
    my $mime = $params{mime};

    # Handle binary and XML Excel files.
    my $wb;
    if ($mime eq 'application/vnd.ms-excel') {
        my $xl = Spreadsheet::ParseExcel->new;
        $wb = $xl->parse($file);
        defined $wb or return $xl->error;
    } elsif ($mime eq 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
        # Using just the File::Temp filehandle results in a spreadsheet with
        # no worksheets.  Spreadsheet::XLSX uses Archive::Zip's
        # readFromFileHandle if passed a filehandle, but Archive::Zip seems
        # to really want a filename.  So, we heed the warning from File::Temp
        # and pass a Unix-specific filename based on the file descriptor.
        # Archive::Zip fails with the '<&=' file descriptor syntax.
        $wb = Spreadsheet::XLSX->new('/dev/fd/' . fileno($file));
    } else {
        return "Unsupported file type $mime\n";
    }
    my $ws = $wb->worksheet(0);
    return "Cannot successfully read the Excel file.\n" unless $ws;

    my $self = { ws => $ws };
    bless $self, $type;
}

=head2 worksheet

  * Purpose: Return worksheet object
  * Expected parameters: none

=cut

sub worksheet {
    my $self = shift;
    return $self->{ws};
}

=head2 type

  * Purpose: Attempt to determine type of data in spreadsheet
  * Expected parameters: none
  * Function on success: returns "fusion", "conexio", or "vanilla"
  * Function on failure: undef

=cut

sub type {
    my $self = shift;
    my $ws = $self->{ws};

    # Try HLA Fusion
    my $cell = $ws->get_cell(0, 0);
    return 'fusion' if $cell && $cell->value =~ /^ALF/;

    # Try vanilla
    return 'vanilla' if $cell && $cell->value eq 'sid';

    # Try Conexio 454
    $cell = $ws->get_cell(1, 0);
    return 'conexio' if $cell && $cell->value =~ /^Created/;

    return;
}

=head1 BUGS AND LIMITATIONS

There are no known problems with this module.

=head1 SEE ALSO

L<TIDES>

=head1 AUTHOR

Ken Yamaguchi, C<< <ken at knowledgesynthesis.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2018 Knowledge Synthesis Inc.

This program is released under the following license: gpl

The full text of the license can be found in the LICENSE file included
with this distribution.

=cut

1;

__END__
