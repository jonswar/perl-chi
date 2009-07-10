#!/usr/bin/perl
use Cwd qw(realpath);
use File::Basename;

my $root_dir = dirname(dirname(dirname(realpath($0))));
system("cd $root_dir; /Users/swartz/std/bin/cptools/cptidy");
if ($?) {
    die "cptidy failed";
}
