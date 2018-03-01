
=head1 NAME

TIDES::StripScan - StripScan parser

=head1 SYNOPSIS

    use TIDES::StripScan;
    my $samples = TIDES::StripScan::parse($fh);

=head1 ABSTRACT

Parse StripScan HLA data into GL Strings.

=cut

package TIDES::StripScan;

use warnings;
use strict;

=head2 new

  * Purpose: Parse StripScan data
  * Expected parameters: fh => filehandle
  * Function on success: returns StripScan object
  * Function on failure: returns undef

=cut

sub new {
    my $type = shift;
    my $self = { @_ };
    bless $self, $type;
}

=head1 parse

  * Purpose: Parse StripScan data
  * Expected parameters: filehandle
  * Function on success: returns hashref of Sample IDs to GL Strings
  * Function on failure: returns undef

=cut

sub parse {
    my $self = shift;
    my $fh = $self->{fh};

    # Check if input looks to be StripScan.
    return if <$fh> !~ /^StripScan /;

    my($locus, @hdr, %samples);
    while (<$fh>) {
        chomp;
        if (/\t/) {
            @hdr or @hdr = split (/\t/), next;

            my %line;
            @line{@hdr} = split /\t/;

            my %genotypes;
            for (split / or /, $line{Genotype}) {
                my @genotype;
                for (split / \+ /) {
                    my @alleles = map { "$locus*$_" } split /,/;
                    push @genotype, join('/', @alleles);
                }

                # Homozygotes do not have a '+'.
                push @genotype, $genotype[0] if @genotype == 1;

                # There can be redundant genotypes. Clean up.
                $genotypes{join('+', @genotype)} = 1;
            }

            $samples{$line{'Strip ID'}}{gls} = join('|', sort keys %genotypes);
        } elsif (/: /) {
            # header row
            my($key, $val) = split /: /;
            next unless $key eq 'Strip Type';

            # Locus name is everything after final '/'.
            s%.*/%%;
            $locus = $_;
        }
    }

    return \%samples;
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
