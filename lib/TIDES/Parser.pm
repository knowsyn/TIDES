
=head1 NAME

TIDES::Parser - Parser base class.

=head1 SYNOPSIS

    TIDES::Parser is an abstract class.  See TIDES::Fusion or TIDES::Conexio.

=head1 ABSTRACT

Parse spreadsheet data into GL Strings.

=cut

package TIDES::Parser;

use warnings;
use strict;
use Carp;

=head1 PUBLIC METHODS

=head2 new

  * Purpose: Parse spreadsheet data
  * Expected parameters: Spreadsheet::ParseExcel or Spreadsheet::XLSX worksheet
  * Function on success: returns Parser object
  * Function on failure: returns undef

=cut

sub new {
    my($type, %params) = @_;
    my $self = {
        ws => $params{worksheet},
        cur_sample => {},
        samples => {},
    };
    bless $self, $type;
}

=head2 parse

  * Purpose: Parse spreadsheet data
  * Expected parameters: none
  * Function on success: returns hashref of Sample IDs to GL Strings
  * Function on failure: returns undef

=cut

sub parse {
    my $self = shift;
    my $ws = $self->{ws};

    # Process data row by row.
    my($r_min, $r_max) = $ws->row_range;
    my($c_min, $c_max) = $ws->col_range;
    for my $r ($r_min .. $r_max) {
        my @row;
        for my $c ($c_min .. $c_max) {
            my $cell = $ws->get_cell($r, $c);
            push @row, $cell ? $cell->value : '';
        }
        $self->_process_row(\@row);
    }

    # Final sample in case there is no sample end signal.
    $self->_process_sample;

    return $self->{samples};
}

=head1 PRIVATE METHODS

=head2 _delete_pairs

=cut

sub _delete_pairs {
    my($pairs, $list_a, $list_b) = @_;
    for my $a (@$list_a) {
        for my $b (@$list_b) {
            delete $$pairs{$a}{$b};
            delete $$pairs{$a} unless %{$$pairs{$a}};
            next if $a eq $b;
            # FIX: faster to check $$pairs{$b}{$a}?

            delete $$pairs{$b}{$a};
            delete $$pairs{$b} unless %{$$pairs{$b}};
        }
    }
}

=head2 _condense_pairs_phased

=cut

sub _condense_pairs_phased {
    my $pairs = shift;
    my %genotype_pairs;

    # Order alphabetically.
    for my $a (sort keys %$pairs) {
        for my $b (sort keys %{$$pairs{$a}}) {
            my $fwd = "$a+$b";

            # Make sure we haven't seen the symmetric pair.
            my $rev = "$b+$a";
            next if $genotype_pairs{$rev};
            $genotype_pairs{$fwd} = 1;
        }
    }

    return \%genotype_pairs;
}

=head2 _condense_pairs

=cut

sub _condense_pairs {
    my($pairs, $locus) = @_;
    return _condense_pairs_phased($pairs) if $locus eq 'phased';

    my %homoz;
    for my $allele (keys %$pairs) {
        for (keys %{$$pairs{$allele}}) {
            $homoz{$allele} = 1 if $_ eq $allele;
        }
    }

    # FIX: rename at least %lists
    my(%collapsed, %lists);
    for my $allele_a (keys %$pairs) {
        my @list_b = sort keys %{$$pairs{$allele_a}};
        my $alleles_b = _allele_list($locus, \@list_b);
        $collapsed{$alleles_b}{$allele_a} = 1;
        $lists{$alleles_b} = \@list_b;

        # Always add homozygote alleles.
        for (keys %homoz) {
            $collapsed{$alleles_b}{$_} = 1;
        }
    }

    # Order by number of encoded pairs.
    my %pairs_count;
    for my $alleles_a (keys %collapsed) {
        my $a = $lists{$alleles_a};
        my $b = keys %{$collapsed{$alleles_a}};
        $pairs_count{$alleles_a} = @$a * $b;
    }

    my %genotype_pairs;

    # Order by number of encoded pairs.
    for my $alleles_a (sort {$pairs_count{$b} <=> $pairs_count{$a}} keys %collapsed) {
        my @list_b = sort keys %{$collapsed{$alleles_a}};
        my $alleles_b = _allele_list($locus, \@list_b);
        my $fwd = "$alleles_a+$alleles_b";

        # Make sure we haven't seen the symmetric pair.
        my $rev = "$alleles_b+$alleles_a";
        if ($alleles_a lt $alleles_b) {
            next if $genotype_pairs{$rev};
            $genotype_pairs{$fwd} = 1;
        } else {
            next if $genotype_pairs{$fwd};
            $genotype_pairs{$rev} = 1;
        }

        _delete_pairs($pairs, $lists{$alleles_a}, \@list_b);
        last unless %{$pairs};
    }

    return \%genotype_pairs;
}

=head2 _process_sample

=cut

sub _process_sample {
    my $self = shift;
    my $cur = $self->{cur_sample};
    my $cur_pairs = $$cur{pairs};
    return unless $cur_pairs;

    my %pairs_all;
    while (@$cur_pairs) {
        my $a = shift @$cur_pairs;
        my $b = shift @$cur_pairs;

        if ($a =~ /~/ && $b =~ /~/) {
            # We could add additional checks on phased data here.
            $pairs_all{phased}{$a}{$b} = 1;
            $pairs_all{phased}{$b}{$a} = 1;
            next;
        } elsif ($a =~ /~/ || $b =~ /~/) {
            carp "unpaired phased data: $a, $b";
        }

        my($loc_a, $allele_a) = _parse_allele($a);
        my($loc_b, $allele_b) = _parse_allele($b);

        $pairs_all{$loc_a}{$allele_a}{$allele_b} = 1;
        # FIX: check eq?
        $pairs_all{$loc_a}{$allele_b}{$allele_a} = 1;
    }

    my @gls;
    for my $locus (sort keys %pairs_all) {
        push @gls, _locus_gls(_condense_pairs($pairs_all{$locus}, $locus));
    }
    return unless @gls;
    $self->{samples}{$$cur{ID}}{gls} = join '^', @gls;
}

=head2 _parse_allele

=cut

sub _parse_allele {
    my $str = shift;
    my($loc, $allele) = split /\*/, $str;

    # DRB3/4/5 is special.
    return 'DRB345', $str if $loc =~ /^DRB[345]$/;

    return $loc, $allele;
}

=head2 _allele_list

=cut

sub _allele_list {
    my($locus, $alleles) = @_;

    # DRB3/4/5 is special.
    return join '/', @$alleles if $locus eq 'DRB345';

    return join '/', map { "$locus*$_" } @$alleles;
}

=head2 _locus_gls

=cut

sub _locus_gls {
    my $pairs = shift;
    my @terms = sort keys %$pairs;
    return unless @terms;
    return join '|', @terms;
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
