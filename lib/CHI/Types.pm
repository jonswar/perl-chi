package CHI::Types;

use Carp;
use CHI::Util qw(can_load parse_duration parse_memory_size);
use List::MoreUtils qw(uniq);
use MooX::Types::MooseLike qw(exception_message);
use MooX::Types::MooseLike::Base qw(:all);
use MooX::Types::MooseLike::Numeric qw(:all);
use base qw(Exporter);
use strict;
use warnings;

our @EXPORT_OK = ();
our %EXPORT_TAGS = ( 'all' => \@EXPORT_OK );

MooX::Types::MooseLike::register_types(
    [
        {
            name => 'OnError',
            test => sub {
                ref( $_[0] ) eq 'CODE' || $_[0] =~ /^(?:ignore|warn|die|log)$/;
            },
            message => sub {
                return exception_message( $_[0], 'a coderef or error level' );
            },
            inflate => 0,
        },
        {
            name       => 'Duration',
            subtype_of => PositiveInt,
            test       => sub { 1 },
            message =>
              sub { return exception_message( $_[0], 'a positive integer' ) },
            inflate => 0,
        },
        {
            name       => 'MemorySize',
            subtype_of => PositiveInt,
            test       => sub { 1 },
            message =>
              sub { return exception_message( $_[0], 'a positive integer' ) },
            inflate => 0,
        },
        {
            name    => 'DiscardPolicy',
            test    => sub { !ref( $_[0] ) || ref( $_[0] ) eq 'CODE' },
            message => sub {
                return exception_message( $_[0], 'a coderef or policy name' );
            },
            inflate => 0,
        },
        {
            name       => 'Serializer',
            subtype_of => Object,
            test       => sub { 1 },
            message    => sub {
                return exception_message( $_[0],
                    'a serializer, hashref, or string' );
            },
            inflate => 0,
        },
        {
            name       => 'Digester',
            subtype_of => Object,
            test       => sub { 1 },
            message    => sub {
                return exception_message( $_[0],
                    'a digester, hashref, or string' );
            },
            inflate => 0,
        }
    ],
    __PACKAGE__
);

sub to_MemorySize {
    my $from = shift;
    if ( is_Num($from) ) {
        $from;
    }
    elsif ( is_Str($from) ) {
        parse_memory_size($from);
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_MemorySize';

sub to_Duration {
    my $from = shift;
    if ( is_Str($from) ) {
        parse_duration($from);
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_Duration';

sub to_Serializer {
    my $from = shift;
    if ( is_HashRef($from) ) {
        _build_data_serializer($from);
    }
    elsif ( is_Str($from) ) {
        _build_data_serializer( { serializer => $from, raw => 1 } );
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_Serializer';

sub to_Digester {
    my $from = shift;
    if ( is_HashRef($from) ) {
        _build_digester(%$from);
    }
    elsif ( is_Str($from) ) {
        _build_digester($from);
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_Digester';

# Strip duplicates from an array reference.  Also accepts a single string.
# Passes through any values other than array references so that they can be
# caught by 'isa' constraints.
#
sub to_UniqArrayRef {
    my $from = shift;

    if ( is_ArrayRef($from) ) {
        [ uniq @$from ];
    }
    elsif ( is_Str($from) ) {
        [$from];
    }
    else {
        return $from;
    }
}
push @EXPORT_OK, 'to_UniqArrayRef';

my $data_serializer_loaded = can_load('Data::Serializer');

sub _build_data_serializer {
    my ($params) = @_;

    if ($data_serializer_loaded) {
        return Data::Serializer->new(%$params);
    }
    else {
        croak
          "Could not load Data::Serializer - install Data::Serializer from CPAN to support serializer argument";
    }
}

my $digest_loaded = can_load('Digest');

sub _build_digester {
    if ($digest_loaded) {
        return Digest->new(@_);
    }
    else {
        croak "Digest could not be loaded, cannot handle digester argument";
    }
}

1;
