
=head1 NAME

TIDES::Conexio - Conexio parser

=head1 SYNOPSIS

    use TIDES::Conexio;
    my $samples = TIDES::Conexio::parse($fh);

=head1 ABSTRACT

Parse Conexio 454 data into GL Strings.

=cut

package TIDES::Conexio;
use TIDES::Parser;
@ISA = qw(TIDES::Parser);

use warnings;
use strict;

=head1 PRIVATE METHODS

=head2 _process_row

=cut

sub _process_row {
    my($self, $r) = @_;

    if ($$r[0] =~ /^Sample:/) {
        $self->_process_sample;
        $self->{cur_sample} = { ID => $$r[1] };
        return;
    }
    push @{$self->{cur_sample}{pairs}}, grep /\*/, @$r;
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
