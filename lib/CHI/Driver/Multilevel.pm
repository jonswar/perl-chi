package CHI::Driver::Multilevel;
use Carp;
use CHI::Util qw(dp);
use Hash::MoreUtils qw(slice_exists);
use List::MoreUtils qw(uniq);
use Moose;
use strict;
use warnings;

extends 'CHI::Driver';

has 'subcaches' => ( is => 'ro', isa => 'ArrayRef', required => 1 );

__PACKAGE__->meta->make_immutable();

# TODO: Do a better job determining, and documenting, how constructor and get and set
# options get passed from parent cache to subcaches

sub BUILD {
    my ( $self, $params ) = @_;

    my $subcaches = $self->{subcaches};
    my %subparams =
      slice_exists( $_[0], 'namespace', 'on_get_error', 'on_set_error' );
    foreach my $subcache (@$subcaches) {
        if ( ref($subcache) eq 'HASH' ) {
            my $subcache_options = $subcache;
            my $chi_class = 'CHI';    # TODO: make this work with CHI subclasses
            $subcache = $chi_class->new( %subparams, %$subcache_options );
            if (
                my ($option) =
                grep { defined( $subcache_options->{$_} ) }
                qw(expires_at expires_in expires_variance)
              )
            {
                croak "expiration option '$option' not supported in subcache";
            }
        }
        $subcache->is_subcache(1);
    }
}

sub get {
    my $self = shift;
    my $key  = shift;

    my $log = CHI->logger();
    my ( $value, @subcaches_to_populate );
    foreach my $subcache ( @{ $self->{subcaches} } ) {
        if ( defined( $value = $subcache->get( $key, @_ ) ) ) {
            foreach my $subcache (@subcaches_to_populate) {
                $subcache->set( $key, $value );
            }
            $self->_log_get_result( $log, $key, "HIT" );
            return $value;
        }
        else {
            push( @subcaches_to_populate, $subcache );
        }
    }
    $self->_log_get_result( $log, $key, "MISS" );
    return undef;
}

sub get_object {
    my ( $self, $key ) = @_;

    return $self->return_first_defined( sub { $_[0]->get_object($key) } );
}

sub get_expires_at {
    my ( $self, $key ) = @_;

    return $self->return_first_defined( sub { $_[0]->get_expires_at($key) } );
}

sub store {
    my ( $self, $key, $data ) = @_;

    $self->do_for_each_subcache( sub { $_[0]->store( $key, $data ) } );
}

sub remove {
    my ( $self, $key ) = @_;

    $self->do_for_each_subcache( sub { $_[0]->remove($key) } );
}

sub clear {
    my ($self) = @_;

    $self->do_for_each_subcache( sub { $_[0]->clear() } );
}

sub get_keys {
    my ($self) = @_;

    my @keys;
    $self->do_for_each_subcache( sub { push( @keys, $_[0]->get_keys() ) } );
    return uniq(@keys);
}

sub get_namespaces {
    my ($self) = @_;

    my @namespaces;
    $self->do_for_each_subcache(
        sub { push( @namespaces, $_[0]->get_namespaces() ) } );
    return uniq(@namespaces);
}

sub do_for_each_subcache {
    my ( $self, $code ) = @_;

    foreach my $subcache ( @{ $self->{subcaches} } ) {
        $code->($subcache);
    }
}

sub return_first_defined {
    my ( $self, $code ) = @_;

    foreach my $subcache ( @{ $self->{subcaches} } ) {
        if ( defined( my $retval = $code->($subcache) ) ) {
            return $retval;
        }
    }
    return undef;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Multilevel -- Use several caches chained together

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(
        driver => 'Multilevel',
        subcaches => [
            { driver => 'Memory' },
            {
                driver  => 'Memcached',
                servers => [ "10.0.0.15:11211", "10.0.0.15:11212" ]
            }
        ],
    );

=head1 DESCRIPTION

This cache driver allows you to use two or more CHI caches together, for example, a
memcached cache bolstered by a local memory cache.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in addition to the
L<CHI|general constructor options/constructor>.
    
=over

=item subcaches [ARRAYREF]

Required - an array reference of CHI caches that will power this cache, in order from most
to least local. Each element of the array is either a hash reference to be passed to CHI->new(),
or an actual driver handle.

The accessor of the same name will return an array reference of driver handles.

=back

The I<namespace> option will automatically be passed to subcaches. Right now, expiration
options are only supported in the parent cache - subcaches currently may not have
different expiration options.

=head1 OPERATION

This section describes how the standard CHI methods are interpreted for multilevel caches.

=over

=item get

Do a get from each subcache in turn, returning the first defined and unexpired value found. In addition, set the value in any more-local subcaches that initially missed, using the subcache's default set options.

For example, in our memory-memcached example, a hit from the memcached cache would cause the value to be written into the memory cache, but a hit from the memory cache would not result in a write to the memcached cache.

=item get_object

=item get_expires_at

Calls the method on each subcache in turn, returning the first defined value found. These methods are not very well suited to multilevel caches; you might be better off calling these methods manually on the individual subcache handles.

=item set

Set the value in all subcaches (write-through). Expiration options are taken from the set() method, then from the default options for the parent cache. Subcaches may not have their own default expiration options (this may change in the future).

=item remove

=item clear

Calls the method on each subcache.

=item get_keys

=item get_namespaces

Calls the method on all subcaches and returns the union of the results.

=back

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
