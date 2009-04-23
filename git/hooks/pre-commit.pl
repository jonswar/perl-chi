#!/usr/bin/perl
use Cwd qw(realpath);
use File::Basename;

my $root_dir = dirname(dirname(dirname(realpath($0))));
system("CHI_INTERNAL_TESTS=1 perl -I$root_dir/lib $root_dir/t/01-tidy.t");
if ($?) {
    die "01-tidy.t failed: $?";
}
