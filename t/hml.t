#!/usr/bin/perl -wT
use strict;

# Test extraction of consensus sequences from HML
use Test::More;
use TIDES::HML;

my $file = 't/data/hml.xml';
open(my $fh, "<", $file) or die "cannot open < $file: $!";
my $samples = TIDES::HML->new(fh => $fh)->parse;
close $fh or die;

$file = 't/data/hml.dat';
open($fh, "<", $file) or die "cannot open < $file: $!";
while (<$fh>) {
    chomp;
    my($sample, $type, @data) = split /\t/;

    if ($type eq 'gls') {
        is($$samples{$sample}{gls}, $data[0], 'GL String match');
        next;
    }

    # GFE: @data = (locus, sequence)
    my $gfe = $$samples{$sample}{gfe};
    ok(delete $$gfe{$data[0]}{$data[1]}, 'GFE seq match');
    delete $$gfe{$data[0]} unless keys %{$$gfe{$data[0]}};
}
my $n_tests = $. + keys %$samples;
close $fh or die;

for (keys %$samples) {
    is(%{$$samples{$_}{gfe}}, 0, 'All HML sequences checked');
}

done_testing $n_tests;
