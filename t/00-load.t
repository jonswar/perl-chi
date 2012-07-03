#!/usr/bin/perl

use Test::More tests => 1;

BEGIN {
    use_ok('CHI');
}

diag("Testing CHI $CHI::VERSION, Perl $], $^X");
