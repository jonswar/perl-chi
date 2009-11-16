package CHI::Types;
use Carp;
use CHI::Util qw(parse_duration parse_memory_size);
use Module::Load::Conditional qw(can_load);
use Moose;
use Moose::Util::TypeConstraints;
use strict;
use warnings;

type 'CHI::Types::OnError' =>
  where { ref($_) eq 'CODE' || /^(?:ignore|warn|die|log)$/ };

subtype 'CHI::Types::Duration' => as 'Int' => where { $_ > 0 };
coerce 'CHI::Types::Duration' => from 'Str' => via { parse_duration($_) };

subtype 'CHI::Types::MemorySize' => as 'Int' => where { $_ > 0 };
coerce 'CHI::Types::MemorySize' => from 'Str' => via { parse_memory_size($_) };

subtype 'CHI::Types::UnblessedHashRef' => as 'HashRef' =>
  where { !blessed($_) };

type 'CHI::Types::DiscardPolicy' => where { !ref($_) || ref($_) eq 'CODE' };

subtype 'CHI::Types::Serializer' => as 'Object';
coerce 'CHI::Types::Serializer' => from 'HashRef' => via {
    _build_data_serializer($_);
};
coerce 'CHI::Types::Serializer' => from 'Str' => via {
    _build_data_serializer( { serializer => $_, raw => 1 } );
};

subtype 'CHI::Types::Digester' => as 'Object';
coerce 'CHI::Types::Digester' => from 'HashRef' => via {
    _build_digester(%$_);
};
coerce 'CHI::Types::Digester' => from 'Str' => via {
    _build_digester($_);
};

__PACKAGE__->meta->make_immutable;

my $data_serializer_loaded =
  can_load( modules => { 'Data::Serializer' => undef } );

my $digest_loaded = can_load( modules => { 'Digest' => undef } );

sub _build_data_serializer {
    my ($params) = @_;

    if ($data_serializer_loaded) {
        return Data::Serializer->new(%$params);
    }
    else {
        croak
          "Data::Serializer could not be loaded, cannot handle serializer argument";
    }
}

sub _build_digester {
    if ($digest_loaded) {
        return Digest->new(@_);
    }
    else {
        croak "Digest could not be loaded, cannot handle digester argument";
    }
}

1;
