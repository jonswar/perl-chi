#!/usr/bin/perl
use Benchmark qw(:all);
use Carp;
use Data::UUID;
use File::Spec::Functions qw(catfile);
use File::Temp qw(tempfile tempdir);
use warnings;
use strict;

my $dir = tempdir('name-XXXX', TMPDIR => 1, CLEANUP => 1);

{

    # For efficiency, use Data::UUID to generate an initial unique id, then suffix it to
    # generate a series of 0x10000 unique ids. Not to be used for hard-to-guess ids, obviously.

    my $ug = Data::UUID->new();
    my $uuid;
    my $suffix = 0;

    sub unique_id {
        if ( !$suffix || !defined($uuid) ) {
            $uuid = $ug->create_hex();
        }
        my $hex = sprintf( '%s%04x', $uuid, $suffix );
        $suffix = ( $suffix + 1 ) & 0xffff;
        return $hex;
    }
}

sub use_tempfile
{
    my ($fh, $filename) = tempfile('name-XXXX', DIR => $dir);
    return $filename;
}

sub use_unique_id
{
    my $filename = join("/", $dir, unique_id());
    open(my $fh, ">$filename");
    return $filename;
}

timethese(2000, {
    'tempfile' => \&use_tempfile,
    'unique_id' => \&use_unique_id,
         });
