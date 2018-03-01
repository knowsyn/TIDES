
=head1 NAME

TIDES::HML - MIRING-compliant HML parser

=head1 SYNOPSIS

    use TIDES::HML;
    my $samples = TIDES::HML::parse($fh);

=head1 ABSTRACT

Parse MIRING-compliant HML data into GL Strings.

=cut

package TIDES::HML;

use warnings;
use strict;
use XML::Twig;

=head2 new

  * Purpose: Parse HML data
  * Expected parameters: fh => filehandle
  * Function on success: returns HML object
  * Function on failure: returns undef

=cut

sub new {
    my $type = shift;
    my $self = { @_ };
    bless $self, $type;
}

=head1 parse

  * Purpose: Parse HML data
  * Expected parameters: filehandle
  * Function on success: returns hashref of Sample IDs to GL Strings
  * Function on failure: returns undef

=cut

sub parse {
    my $self = shift;

    my $t = XML::Twig->new;
    $t->parse($self->{fh});

    my(%gls, %samples);
    for my $sample ($t->root->children('sample')) {
        my $sid = $sample->att('id');
        return "multiple samples with ID $sid" if $gls{$sid};
        for my $typing ($sample->children('typing')) {
            for my $assignment ($typing->children('allele-assignment')) {
                for my $gls ($assignment->children('glstring')) {
                    next if $gls->att('uri');

                    # glstring may be empty
                    next unless $gls->trimmed_text;
                    push @{$gls{$sid}}, $gls->trimmed_text;
                }
            }

            my $locus;
            for my $consensus ($typing->children('consensus-sequence')) {
                for my $db ($consensus->children('reference-database')) {
                    for my $ref ($db->children('reference-sequence')) {
                        # Grab the locus name for the sequence.
                        my $name = $ref->att('name') =~ s/\*.*//r;
                        $locus && $locus eq $name and next;
                        $locus or $locus = $name, next;
                        return "$locus and $name in same <typing> block";
                    }
                }

                # We're not considering phase across loci.
                # Blocks may occur in arbitary order.
                my(%refs, %blocks);
                for my $block ($consensus->children('consensus-sequence-block')) {
                    my $ref = $block->att('reference-sequence-id');

                    # phase-set is optional
                    my $phase = $block->att('phase-set');
                    if (defined($phase)) {
                        if (exists($refs{$phase})) {
                            return "different ref sequences in phase-set $phase"
                                if $refs{$phase} ne $ref;
                        } else {
                            $refs{$phase} = $ref;
                        }
                    }

                    if (!defined($block->att('start'))) {
                        return "consensus-sequence-block is missing start";
                    }

                    push @{$blocks{$ref}{$block->att('start')}}, [
                        $ref,
                        $block->att('start'),
                        $block->att('end'),
                        $block->trimmed_field('sequence') =~ s/ //gr,
                        $phase,
                    ];
                }

                for ($self->_get_consensus_seqs(\%blocks)) {
                    # check for error messages
                    return $_ if / /;
                    $samples{$sid}{gfe}{$locus}{$_} = 1;
                }
            }
        }
    }
    for (keys %gls) {
        $samples{$_}{gls} = join '^', @{$gls{$_}};
    }

    return \%samples;
}

=head1 _get_consensus_seqs

  * Purpose: Turn consensus blocks into consensus sequences
  * Expected parameters: filehandle
  * Function on success: returns hashref of Sample IDs to GL Strings
  * Function on failure: returns undef

=cut

sub _get_consensus_seqs {
    my($self, $blocks) = @_;

    # block is {ref => start => [ref, start, stop, seq, phase]}
    my @dfs;
    my %sorted;
    my $n;
    for my $ref (keys %$blocks) {
        $n or $n = keys %{$$blocks{$ref}};
        return "blocks mismatch for $ref" if $n != keys %{$$blocks{$ref}};
        $sorted{$ref} = [ sort {$a <=> $b} keys %{$$blocks{$ref}} ];
    }

    for (my $i = 0; $i < $n; $i++) {
        for my $ref (keys %sorted) {
            push @{$dfs[$i]}, @{$$blocks{$ref}{$sorted{$ref}[$i]}};
        }
    }

    my %phase;
    return $self->_dfs_consensus_seqs(
        dfs          => \@dfs,
        dfs_i        => 0,
        seq          => '',
        my_phase     => \%phase,
        prev_phase   => \%phase,
        prev_ref     => '',
        prev_ref_end => -1,
    );
}

=head1 _dfs_consensus_seqs

  * Purpose: Depth-first-search for consensus sequences
  * Expected parameters: DFS arrayref, index
  * Function on success: consensus sequence
  * Function on failure:

=cut

sub _dfs_consensus_seqs {
    my($self, %args) = @_;

    # End of recursion?
    my $dfs = $args{dfs};
    my $dfs_i = $args{dfs_i};
    my $seq = $args{seq};
    return $seq if $dfs_i > $#$dfs;
    my $n = @{$$dfs[$dfs_i]};

    my $my_phase = $args{my_phase};
    my $prev_phase = $args{prev_phase};
    my $prev_ref = $args{prev_ref};
    my $prev_ref_end = $args{prev_ref_end};

    # Pass all phases seen to the next recursion.
    my %all_phase = %$prev_phase;
    for (my $j = 0; $j < $n; $j++) {
        my $phase = $$dfs[$dfs_i][$j][4];
        defined $phase and $all_phase{$phase} = 1;
    }

    my @seqs;
    for (my $j = 0; $j < $n; $j++) {
        my($ref, $beg, $end, $chunk, $phase) = @{$$dfs[$dfs_i][$j]};
        my $len = $end - $beg;
        return "$chunk is not length $len" if $len != length $chunk;

        # Skip recursion if we've seen this phase, but it's not in this seq.
        next if defined($phase) && $$prev_phase{$phase} && !$$my_phase{$phase};

        if ($ref eq $prev_ref) {
            if ($beg < $prev_ref_end) {
                # Overlap.
                my $len = $prev_ref_end - $beg;
                my $a = substr $seq, -$len;
                my $b = substr $chunk, 0, $len;
                return "overlap but $a != $b" if $a ne $b;
                $chunk = substr $chunk, $len;
            } else {
                return "seq-block end oddity" if $end <= $prev_ref_end;
            }
        }

        my %my_phase_copy = %$my_phase;
        defined $phase and $my_phase_copy{$phase} = 1;

        push @seqs, $self->_dfs_consensus_seqs(
            dfs          => $dfs,
            dfs_i        => $dfs_i + 1,
            seq          => $seq . $chunk,
            my_phase     => \%my_phase_copy,
            prev_phase   => { %all_phase },
            prev_ref     => $ref,
            prev_ref_end => $end,
        );
    }

    return @seqs;
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
