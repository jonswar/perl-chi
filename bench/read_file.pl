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
my ($fh, $file) = tempfile(UNLINK => 1);
write_file($file, $content);

sub read_binary_file_lexical {
    my $buf = "";
    my $read_fh;
    unless ( sysopen( $read_fh, $file, O_RDONLY | O_BINARY ) ) {
        croak "read_file '$file' - sysopen: $!";
    }
    my $size_left = -s $read_fh ;

    while( 1 ) {
        my $read_cnt = sysread( $read_fh, $buf, $size_left, length $buf );

        if ( defined $read_cnt ) {
            last if $read_cnt == 0 ;
            $size_left -= $read_cnt ;
            last if $size_left <= 0 ;
        }
        else {
            croak "read_file '$file' - sysread: $!";
        }
    }
}

sub read_binary_file_glob {
    my $buf = "";
    local *read_fh;
    unless ( sysopen( *read_fh, $file, O_RDONLY | O_BINARY ) ) {
        croak "read_file '$file' - sysopen: $!";
    }
    my $size_left = -s *read_fh ;

    while( 1 ) {
        my $read_cnt = sysread( *read_fh, $buf, $size_left, length $buf );

        if ( defined $read_cnt ) {
            last if $read_cnt == 0 ;
            $size_left -= $read_cnt ;
            last if $size_left <= 0 ;
        }
        else {
            croak "read_file '$file' - sysread: $!";
        }
    }
}

timethese(5000, {
    'read_slurp'  => sub { my $c = read_file($file, bin_mode => ':raw') },
    'read_open' => sub { open(my $fh, $file); binmode($fh); local $/; my $c = <$fh> },
    'read_binary_file_lexical' => \&read_binary_file_lexical,
    'read_binary_file_glob' => \&read_binary_file_glob,
#    'write_slurp'  => sub { write_file($file, { bin_mode => ':raw' }, $content) },
#    'write_open' => sub { open(my $fh, ">$file"); binmode($fh); print $fh $content },
         });
