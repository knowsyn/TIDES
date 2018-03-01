
=head1 NAME

TIDES::Input - Input parser

=head1 SYNOPSIS

    use TIDES::Input;
    my $samples = TIDES::Input::parse($fh);

=head1 ABSTRACT

Parse demo input data into the database.

=cut

package TIDES::Input;
use TIDES::Parser;
@ISA = qw(TIDES::Parser);

use warnings;
use strict;

=head1 PRIVATE METHODS

=head2 _process_row

=cut

sub _process_row {
    my($self, $r) = @_;
    my $cur = $self->{cur_sample};

    # First row contains the column names.
    if (!$$cur{header}) {
        $$cur{header} = $r;
        return;
    }

    my %fields;
    @fields{@{$$cur{header}}} = @$r;

    my $samples = $self->{samples};
    $$samples{keys %$samples} = \%fields;
}

=head2 _process_sample

=cut

sub _process_sample {
    # Override this Parser function since we're not processing HLA pair data.
    # Nothing to do since each row is a sample.
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
