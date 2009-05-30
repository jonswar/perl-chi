package CHI::Driver::Role::IsSizeAware;
use Carp::Assert;
use Moose::Role;
use strict;
use warnings;

has 'max_size' => ( is => 'rw', isa => 'CHI::Types::MemorySize', coerce => 1 );
has 'max_size_reduction_factor' => ( is => 'rw', isa => 'Num', default => 0.8 );
has 'discard_policy' => (
    is      => 'ro',
    isa     => 'Maybe[CHI::Types::DiscardPolicy]',
    builder => '_build_discard_policy',
);
has 'discard_timeout' => (
    is      => 'rw',
    isa     => 'Num',
    default => 10
);

use constant Size_Key => 'CHI_IsSizeAware_size';

sub _build_discard_policy {
    my $self = shift;

    return $self->can('default_discard_policy')
      ? $self->default_discard_policy
      : 'arbitrary';
}

after 'BUILD_roles' => sub {
    my ( $self, $params ) = @_;

    $self->{is_size_aware} = 1;
};

after 'clear' => sub {
    my $self = shift;

    $self->_set_size(0);
};

around 'remove' => sub {
    my $orig  = shift;
    my $self  = shift;
    my ($key) = @_;

    my ( $size_delta, $data );
    if ( !$self->{_no_set_size_on_remove} && ( $data = $self->fetch($key) ) ) {
        $size_delta = -1 * length($data);
    }
    $self->$orig(@_);
    if ($size_delta) {
        $self->_add_to_size($size_delta);
    }
};

around 'set' => sub {
    my $orig  = shift;
    my $self  = shift;
    my ($key) = @_;

    # If item exists, record its size so we can subtract it below
    #
    my $size_delta = 0;
    if ( my $data = $self->fetch($key) ) {
        $size_delta = -1 * length($data);
    }

    my $result = $self->$orig( @_, { obj_ref => \my $obj } );

    # Add to size and reduce size if over the maximum
    #
    $size_delta += $obj->size;
    my $namespace_size = $self->_add_to_size($size_delta);

    if ( defined( $self->max_size )
        && $namespace_size > $self->max_size )
    {
        $self->discard_to_size(
            $self->max_size * $self->max_size_reduction_factor );
    }

    return $result;
};

sub get_size {
    my ($self) = @_;

    my $size = $self->metacache->get(Size_Key) || 0;
    return $size;
}

sub _set_size {
    my ( $self, $new_size ) = @_;

    $self->metacache->set( Size_Key, $new_size );
}

sub _add_to_size {
    my ( $self, $incr ) = @_;

    # Non-atomic, so may be inaccurate over time
    my $new_size = ( $self->get_size || 0 ) + $incr;
    $self->_set_size($new_size);
    return $new_size;
}

sub discard_to_size {
    my ( $self, $ceiling ) = @_;

    # Get an iterator that produces keys in the order they should be removed
    #
    my $discard_iterator =
      $self->_get_iterator_for_discard_policy( $self->discard_policy );

    # Remove keys until we are under $ceiling. Temporarily turn off size
    # setting on remove because we will set size once at end. Check if
    # we exceed discard timeout.
    #
    my $end_time = time + $self->discard_timeout;
    local $self->{_no_set_size_on_remove} = 1;
    my $size = $self->get_size();
    eval {
        while ( $size > $ceiling )
        {
            if ( defined( my $key = $discard_iterator->() ) ) {
                if ( my $data = $self->fetch($key) ) {
                    $self->remove($key);
                    $size -= length($data);
                }
            }
            else {
                affirm { $self->is_empty }
                "iterator returned undef, cache should be empty";
                last;
            }
            if ( time > $end_time ) {
                die sprintf( "discard timeout (%s sec) reached",
                    $self->discard_timeout );
            }
        }
    };
    $self->_set_size($size);
    die $@ if $@;
}

sub _get_iterator_for_discard_policy {
    my ( $self, $discard_policy ) = @_;

    if ( ref($discard_policy) eq 'CODE' ) {
        return $discard_policy->($self);
    }
    else {
        my $discard_policy_sub = "discard_policy_" . $discard_policy;
        if ( $self->can($discard_policy_sub) ) {
            return $self->$discard_policy_sub();
        }
        else {
            die sprintf( "cannot get iterator for discard policy '%s' ('%s')",
                $discard_policy, $discard_policy_sub );
        }
    }
}

sub discard_policy_arbitrary {
    my ($self) = @_;

    return $self->get_keys_iterator();
}

1;
