#!/usr/bin/env perl
#
# This is the test script executed by prove.
# You probably want to run "bin/chitest" instead, which will give you all the options of prove.
#
use lib qw(/home/swartz/perl/CHI/lib);
use Cwd qw(realpath);
use File::Basename;
use Getopt::Long;
use strict;
use warnings;

our @classes;

my $test_class;

BEGIN {
    GetOptions(
        'c|class=s'     => \$test_class,
        'm|method=s'    => \$ENV{TEST_METHOD},
        'S|stack-trace' => \$ENV{TEST_STACK_TRACE},
        );
    foreach my $key (qw(TEST_METHOD TEST_STACK_TRACE)) {
        delete($ENV{$key}) if !defined($ENV{$key});
    }
    if ($ENV{TEST_METHOD}) {
        $ENV{TEST_METHOD} = ".*" . $ENV{TEST_METHOD} . ".*";
    }
    eval "require $test_class";
    die $@ if $@;
}

CHI::Test::Class->runtests($test_class);
