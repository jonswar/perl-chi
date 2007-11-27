#!/usr/bin/perl
#
# Try to generate failure to rename one temp file to another, as the file driver does.
#
use Data::Dump qw(dump);
use File::Path qw(mkpath rmtree);
use File::Slurp;
use File::Temp qw(tempdir);
use Sys::HostIP;
use warnings;
use strict;

my $main_dir = "/tmp/chi-driver-file-VK12/Test+3A+3AClass/b/6";
rmtree($main_dir);
mkpath($main_dir, 0, 0775);
die "could not create $main_dir" unless -d $main_dir;
my $main_file = "$main_dir/medium.dat";

sub main {
    foreach my $p ( 0 .. 2 ) {
        if ( my $pid = fork() ) {
        }
        else {
            child_action($p);
            exit;
        }
    }
    sleep(100);
}

sub child_action {
    my $p = shift;
    print "running child_action for $p ($$)\n";
    my $buf = "a" x 100;
    for ( my $i = 0 ; $i < 100000 ; $i++ ) {
        my $temp_file = "/tmp/chi-driver-file." . unique_id();
        { my $fh; open($fh, ">$temp_file"); print $fh $buf }
        # print "$p ($$): renaming $temp_file to $main_file\n";
        die "temp_file $temp_file does not exist!" if !-f $temp_file;
        die "main_dir $main_dir does not exist!" if !-d $main_dir;
        for (my $j = 0; $j <= 9; $j++) {
            if ( rename( $temp_file, $main_file ) ) {
                last;
            }
            elsif ($j == 0) {
                die "could not rename '$temp_file' to '$main_file': $!";
            }
        }
    }
}

# Adapted from Sys::UniqueID
my $idnum = 0;
my $netaddr = sprintf( '%02X%02X%02X%02X', split( /\./, Sys::HostIP->ip ) );

sub unique_id {
    die "netaddr not defined" unless defined $netaddr;
    return sprintf '%012X.%s.%08X.%08X', time, $netaddr, $$, ++$idnum;
}

main();
