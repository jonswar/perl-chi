#!/usr/bin/perl
use Benchmark qw(:all);
use Carp;
use File::Slurp;
use File::Temp qw(tempfile);
use POSIX qw( :fcntl_h ) ;
use Fcntl qw( :DEFAULT ) ;
use warnings;
use strict;

my $content = "a" x 100000;
my $file = "content.txt";

sub write_binary_file {
    my $buf = $content;
    my $write_fh;
    unless ( sysopen( $write_fh, $file, O_WRONLY | O_CREAT | O_BINARY ) ) {
        croak "write_file '$file' - sysopen: $!";
    }
    my $length = length($buf);
    my $size_left = $length;
    my $offset = 0;

    do {
        my $write_cnt = syswrite( $write_fh, $buf,
                                  $size_left, $offset ) ;

        unless ( defined $write_cnt ) {
            croak "write_file '$file' - syswrite: $!";
        }
        $size_left -= $write_cnt ;
        $offset += $write_cnt ;

    } while( $size_left > 0 ) ;

    truncate( $write_fh, $length );
}

timethese(5000, {
    'write_binary_file' => \&write_binary_file,
    'write_slurp'  => sub { write_file($file, { bin_mode => ':raw' }, $content) },
    'write_open' => sub { open(my $fh, ">$file"); binmode($fh); print $fh $content },
         });
