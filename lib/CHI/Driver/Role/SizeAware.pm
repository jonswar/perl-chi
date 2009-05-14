package CHI::Driver::Role::SizeAware;
use Carp::Assert;
use Moose::Role;
use strict;
use warnings;

use constant Reserved_Key_Prefix =>
  '_CHI_RESERVED_';    # XXX could use a better name
use constant Size_Key => Reserved_Key_Prefix . 'SIZE';

around 'get_keys' => sub {
    my $orig = shift;
    my $self = shift;

    # Call driver get_keys, then filter out reserved CHI keys
    return grep { index( $_, Reserved_Key_Prefix ) == -1 } $self->$orig(@_);
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
        $self->reduce_to_size( $self->max_size * $self->size_reduction_factor );
    }

    return $result;
};

sub get_size {
    my ($self) = @_;

    my $size = $self->fetch(Size_Key) || 0;
    return $size;
}

sub _set_size {
    my ( $self, $new_size ) = @_;

    $self->store( Size_Key, $new_size );
}

sub _add_to_size {
    my ( $self, $incr ) = @_;

    # Non-atomic, so may be inaccurate over time
    my $new_size = ( $self->get_size || 0 ) + $incr;
    $self->_set_size($new_size);
    return $new_size;
}

sub reduce_to_size {
    my ( $self, $ceiling ) = @_;

    # Get an iterator that produces keys in the order they should be removed
    #
    my $discard_iterator =
      $self->_get_iterator_for_discard_policy( $self->discard_policy );

    # Remove keys until we are under $ceiling. Temporarily turn off size
    # setting on remove because we will set size once at end.
    #
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
        }
    };
    $self->_set_size($size);
    die $@ if $@;  ## no critic (RequireCarping)
}

sub _get_iterator_for_discard_policy {
    my ( $self, $discard_policy ) = @_;

    if ( ref($discard_policy) eq 'CODE' ) {
        return $discard_policy;
    }
    else {
        my $discard_sub = "discard_iterator_" . $discard_policy;
        if ( $self->can($discard_sub) ) {
            return $self->$discard_sub();
        }
        else {
            ## no critic (RequireCarping)
            die sprintf( "cannot get iterator for discard policy '%s' ('%s')",
                $discard_policy, $discard_sub );
        }
    }
}

sub discard_iterator_arbitrary {
    my ($self) = @_;

    return $self->get_keys_iterator();
}

1;
