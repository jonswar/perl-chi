#!/usr/bin/perl
use Test::More tests => 1;
use strict;
use threads;

use CHI::Util qw( unique_id );

sub say {
    print(@_);
    print "\n";
}

foreach (1..10){
    say unique_id();
}


foreach (1..2){
    threads->create( sub { say "doing nothing." } );
}

foreach (threads->list){
    $_->join;
}

ok(1);

