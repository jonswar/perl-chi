package CHI::Driver::Paired;
use Carp;
use Carp::Assert;
use Hash::MoreUtils qw(slice_exists);
use List::MoreUtils qw(uniq);
use Moose;
use strict;
use warnings;

has 'chi_root_class' => ( is => 'ro' );
has 'subcaches' => ( is => 'ro', isa => 'ArrayRef[HashRef]', required => 1 );
has 'primary_index' => ( is => 'ro', isa => 'Int', required => 1 );
has 'primary_subcache'     => ( is => 'ro' );
has 'no_populate_on_get'   => ( is => 'ro' );
has 'no_distribute_reads'  => ( is => 'ro' );
has 'no_distribute_writes' => ( is => 'ro' );

__PACKAGE__->meta->make_immutable();

# These options can be passed to the constructor and will apply to both subcaches.
#
my @shared_option_keys = (
    'namespace',  'on_get_error', 'on_set_error', 'expires_at',
    'expires_in', 'expire_variance'
);

# TODO: Do a better job determining, and documenting, how constructor and get and set
# options get passed from parent to subcaches

sub BUILD {
    my ( $self, $params ) = @_;

    my $subcaches = $self->{subcaches};
    my %shared_options = slice_exists( $_[0], @shared_option_keys );
    foreach my $subcache (@$subcaches) {
        my $subcache_options = $subcache;
        if (
            my ($option) =
            grep { defined( $subcache_options->{$_} ) } @shared_option_keys
          )
        {
            croak
              "option '$option' cannot be passed to individual subcache of Paired cache";
        }
        $subcache =
          $self->chi_root_class->new( %$subcache_options, %shared_options );
    }
    affirm { @$subcaches == 2 && $self->{primary_index} =~ /^(0|1)$/ };
    $self->{primary_subcache} = $subcaches->[ $self->{primary_index} ];
}

sub get {
    my $self = shift;
    my $key  = shift;

    if ( $self->no_distribute_reads ) {
        return $self->primary_subcache->get( $key, @_ );
    }

    my ( $value, $obj );
    my ( $subcache0, $subcache1 ) = @{ $self->{subcaches} };
    if ( defined( $value = $subcache0->get( $key, @_ ) ) ) {
        return $value;
    }
    elsif ( defined( $value = $subcache1->get( $key, @_, obj_ref => \$obj ) ) )
    {
        unless ( $self->no_populate_on_get ) {

            # ** Should call store directly if possible - see set comments.
            $subcache1->set( $key, $value, { expires_at => $obj->expires_at } );
        }
        return $value;
    }
    else {
        return undef;
    }
}

sub set {
    my $self = shift;

    if ( $self->no_distribute_writes ) {
        return $self->primary_subcache->set(@_);
    }

    # ** Inefficient - should call store directly so we share common work of
    # ** serialization, etc. But can't if one of the driver classes has overriden set(),
    # ** or they have differing serializers, or, in general, if anything could cause the
    # ** set objects to be different.
    $self->do_for_each_subcache( sub { $_[0]->set(@_) } );
}

sub remove {
    my $self = shift;

    $self->do_for_each_subcache( sub { $_[0]->remove(@_) } );
}

sub clear {
    my $self = shift;

    $self->do_for_each_subcache( sub { $_[0]->clear(@_) } );
}

sub do_for_each_subcache {
    my ( $self, $code ) = @_;

    foreach my $subcache ( @{ $self->{subcaches} } ) {
        $code->($subcache);
    }
}

sub isa {
    my $self = shift;

    return $self->SUPER::isa(@_) || $self->primary_subcache->isa(@_);
}

sub can {
    my $self = shift;

    return $self->SUPER::can(@_) || $self->primary_subcache->can(@_);
}

sub AUTOLOAD {
    my $self = shift;
    my ($method);

    ( $method = $AUTOLOAD ) =~ s/.*:://;
    return if $method eq 'DESTROY';

    return $self->primary_subcache->$method(@_);
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Multilevel -- Use several caches chained together

=head1 SYNOPSIS

    use CHI;

    my $cache = vCHI->new(
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
