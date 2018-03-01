
=head1 NAME

TIDES::Vanilla - Vanilla parser

=head1 SYNOPSIS

    use TIDES::Vanilla;
    my $samples = TIDES::Vanilla::parse($fh);

=head1 ABSTRACT

Parse a vanilla GL String spreadsheet.

=cut

package TIDES::Vanilla;
use TIDES::Parser;
@ISA = qw(TIDES::Parser);

use warnings;
use strict;

=head1 PRIVATE METHODS

=head2 _process_row

=cut

sub _process_row {
    my($self, $r) = @_;
    return if $$r[0] eq 'sid';

    my $cur_id = $self->{cur_sample}{ID};
    if (!$cur_id || $cur_id != $$r[0]) {
        $self->_process_sample;
        $self->{cur_sample} = { ID => $$r[0] };
    }

    for my $a (split /\//, $$r[1]) {
        for my $b (split /\//, $$r[2]) {
            push @{$self->{cur_sample}{pairs}}, $a, $b;
        }
    }
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
