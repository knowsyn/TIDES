#!/usr/bin/perl

# Test to see if the module loads correctly.
use warnings;
use strict;
use Test::More tests => 1;

BEGIN {

    use_ok('TIDES');

}

diag(

    "Testing TIDES $TIDES::VERSION, Perl $], $^X\n",

);
