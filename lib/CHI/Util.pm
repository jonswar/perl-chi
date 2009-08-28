package CHI::Util;
use Carp qw( croak longmess );
use Data::Dumper;
use Data::UUID;
use File::Spec::Functions qw(catdir catfile);
use Time::Duration::Parse;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(
  dump_one_line
  fast_catdir
  fast_catfile
  has_moose_class
  parse_duration
  parse_memory_size
  read_dir
  unique_id
);

sub dump_one_line {
    my ($value) = @_;

    return Data::Dumper->new( [$value] )->Indent(0)->Sortkeys(1)->Quotekeys(0)
      ->Terse(1)->Dump();
}

# Simplified read_dir cribbed from File::Slurp
sub read_dir {
    my ($dir) = @_;

    ## no critic (RequireInitializationForLocalVars)
    local *DIRH;
    opendir( DIRH, $dir ) or croak "cannot open '$dir': $!";
    return grep { $_ ne "." && $_ ne ".." } readdir(DIRH);
}

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

{
    my $File_Spec_Using_Unix = $File::Spec::ISA[0] eq 'File::Spec::Unix';

    sub fast_catdir {
        return $File_Spec_Using_Unix ? join( "/", @_ ) : catdir(@_);
    }

    sub fast_catfile {
        return $File_Spec_Using_Unix ? join( "/", @_ ) : catfile(@_);
    }
}

my %memory_size_units = ( 'k' => 1024, 'm' => 1024 * 1024 );

sub parse_memory_size {
    my $size = shift;
    if ( $size =~ /^\d+b?$/ ) {
        return $size;
    }
    elsif ( my ( $quantity, $unit ) = ( $size =~ /^(\d+)\s*([km])b?$/i ) ) {
        return $quantity * $memory_size_units{ lc($unit) };
    }
    else {
        croak "cannot parse memory size '$size'";
    }
}

sub has_moose_class {
    my ($obj) = @_;

    my $meta = Class::MOP::class_of($obj);
    return ( defined $meta && $meta->isa("Moose::Meta::Class") );
}

1;

__END__

=pod

=head1 NAME

CHI::Util -- Internal utilities

=head1 DESCRIPTION

These are utilities for internal CHI use.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
