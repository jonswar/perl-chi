package CHI::Test::Driver::Role::CheckKeyValidity;
use Carp;
use Moose::Role;
use strict;
use warnings;

has 'test_object' => ( is => 'rw' );

before 'get' => sub {
    my ( $self, $key ) = @_;
    $self->verify_valid_test_key($key);
};

before 'set' => sub {
    my ( $self, $key ) = @_;
    $self->verify_valid_test_key($key);
};

sub verify_valid_test_key {
    my ( $self, $key ) = @_;
    croak "invalid test key '$key'"
      if ( defined($key)
        && !exists( $self->test_object->{all_test_keys_hash}->{$key} ) );
}

1;
