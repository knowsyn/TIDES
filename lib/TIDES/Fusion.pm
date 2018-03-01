
=head1 NAME

TIDES::Fusion - Fusion parser

=head1 SYNOPSIS

    use TIDES::Fusion;
    my $samples = TIDES::Fusion::parse($fh);

=head1 ABSTRACT

Parse HLA Fusion data into GL Strings.

=cut

package TIDES::Fusion;
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

    # Attempt to be robust to column positions, which change across versions.
    my @cells = grep !/^$/, @$r;
    return unless @cells;

    # Capture HLA data between "Possible Allele Pairs" and "Other Assignment".
    if ($cells[0] =~ /^Other Assignment:/) {
        # Check for Blank Well code in notes.
        if ($cells[1]) {
            return if $cells[1] =~ /XYXYXY/;
            $$cur{notes} = [ $cells[1] ];
        } else {
            $$cur{notes} = [];
        }

        $self->_check_missing;
        $self->_process_sample;
        $self->{prev_sample} = $cur;
        $self->{cur_sample} = {};
        $self->{pairs_section} = 0;
        return;
    }

    if ($self->{pairs_section}) {
        my @pairs = grep /^($self->{loci_pattern})\*/, @cells;

        # Ignore any pairs with excluded probes.
        @pairs = grep !/F(P|N)#/, @pairs;

        push @{$$cur{pairs}}, map { split / /, $_ } @pairs;
        return;
    }

    for ($cells[0]) {
        /^Sample ID:/        and $$cur{ID}   = $cells[1], return;
        /^Sample Date:/      and $$cur{Date} = $cells[-1], return;
        /^Session ID:/       and $self->_process_session(\@cells), return;
        /^Possible Allele Pairs:/ and $self->{pairs_section} = 1, return;
    }

    $self->_process_nomenclature(\@cells) if grep /^Imgt Ver:/, @cells;
}

=head2 _process_session

=cut

sub _process_session {
    my($self, $cells) = @_;
    my $cur = $self->{cur_sample};

    while (@$cells) {
        for (shift @$cells) {
            my $val = shift @$cells;
            /^Session ID:/ and $$cur{session} = $val, last;
            /^Catalog:/    and $self->{kit}   = $val, last;
            /^Locus:/      and $self->{loci}  = [ split(/,/, $val) ], last;
            /^Test Pos:/   and $$cur{pos}     = $val, last;
        }
    }
    $self->{loci_pattern} = join '|', @{$self->{loci}};
}

=head2 _process_nomenclature

Some versions have extra text before the Nomenclature and IMGT fields.

=cut

sub _process_nomenclature {
    my($self, $cells) = @_;
    my $cur = $self->{cur_sample};

    my($nom, $imgt);
    while (@$cells) {
        for (shift @$cells) {
            next unless /^(Nom|Imgt)/;

            my $val = shift @$cells;
            /^(Nom\.|Nomenclature) Date:/ and $nom  = $val, last;
            /^Imgt Ver:/                  and $imgt = $val, last;
        }
    }
    return unless $nom && $imgt;
    $$cur{release} = "$imgt -- $nom";
}

=head2 _check_missing

=cut

sub _check_missing {
    my $self = shift;
    my $cur = $self->{cur_sample};
    my $prev = $self->{prev_sample};

    my @missing;
    for ('Date', 'ID') {
        next if $$cur{$_};
        $$cur{$_} = $$prev{$_};
        push @missing, $_;
    }
    if (@missing) {
        push @{$$cur{notes}}, 'No Sample ' . join(' or ', @missing) .
                              ' in Fusion Output. ' . join(' and ', @missing) .
                              ' of preceding record used.';
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
