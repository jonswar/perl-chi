#!/usr/bin/perl
use Benchmark qw(:all);
use Carp;
use File::Slurp;
use File::Temp qw(tempfile);
use POSIX qw( :fcntl_h );
use Fcntl qw( :DEFAULT );
use warnings;
use strict;

my $content = "a" x 100000;
my ( $fh, $file ) = tempfile( UNLINK => 1 );
write_file( $file, $content );

sub sysread_binary_file_lexical {
    my $buf = "";
    my $read_fh;
    unless ( sysopen( $read_fh, $file, O_RDONLY | O_BINARY ) ) {
        croak "read_file '$file' - sysopen: $!";
    }
    my $size_left = -s $read_fh;

    while (1) {
        my $read_cnt = sysread( $read_fh, $buf, $size_left, length $buf );

        if ( defined $read_cnt ) {
            last if $read_cnt == 0;
            $size_left -= $read_cnt;
            last if $size_left <= 0;
        }
        else {
            croak "read_file '$file' - sysread: $!";
        }
    }
    return $buf;
}

sub sysread_binary_file_glob {
    my $buf = "";
    local *read_fh;
    unless ( sysopen( *read_fh, $file, O_RDONLY | O_BINARY ) ) {
        croak "read_file '$file' - sysopen: $!";
    }
    my $size_left = -s *read_fh;

    while (1) {
        my $read_cnt = sysread( *read_fh, $buf, $size_left, length $buf );

        if ( defined $read_cnt ) {
            last if $read_cnt == 0;
            $size_left -= $read_cnt;
            last if $size_left <= 0;
        }
        else {
            croak "read_file '$file' - sysread: $!";
        }
    }
    return $buf;
}

sub slurp { return scalar( read_file( $file, bin_mode => ':raw' ) ) }

sub angle_brackets {
    open( my $fh, $file );
    binmode($fh);
    local $/;
    return scalar(<$fh>);
}

sub angle_brackets_with_localized_glob {
    local *read_fh;
    open( read_fh, $file );
    binmode(read_fh);
    local $/;
    return scalar(<read_fh>);

}

my %funcs = (
        'slurp'          => \&slurp,
        'angle_brackets' => \&angle_brackets,
        'angle_brackets_with_localized_glob' =>
          \&angle_brackets_with_localized_glob,

        'sysread_binary_file_lexical' => \&sysread_binary_file_lexical,
        'sysread_binary_file_glob'    => \&sysread_binary_file_glob,
        #   'angle_brackets_with_glob' => sub { open(*readfh, $file); binmode(*readfh); local $/; return scalar(<*readfh>) },
        #    'write_slurp'  => sub { write_file($file, { bin_mode => ':raw' }, $content) },
        #    'write_open' => sub { open(my $fh, ">$file"); binmode($fh); print $fh $content },
    );
    

foreach my $sub (keys(%funcs)) {
    print "checking $sub\n";
    my $content_from_sub = $funcs{$sub}->();
    if ($content_from_sub ne $content) {
        die "$sub did not return correct content";
    }
}

timethese(
    10000,
    \%funcs
);

