package CHI::Driver::Role::SizeAware;
use Any::Moose qw(::Role);
use strict;
use warnings;

use constant Reserved_Key_Prefix =>
  '_CHI_RESERVED_';    # XXX could use a better name
use constant Size_Key => Reserved_Key_Prefix . 'SIZE';

sub initialize_size_awareness {
    my $self = shift;

    $self->{is_size_aware} = 1;
}

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

    my $size_delta;
    if ( my $data = $self->fetch($key) ) {
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

    return $self->get(Size_Key) || 0;
}

sub _set_size {
    my ( $self, $new_size ) = @_;

    my $obj =
      CHI::CacheObject->new( Size_Key, $new_size, time(), CHI::Driver::Max_Time,
        CHI::Driver::Max_Time, $self->serializer );
    $self->_set_object( Size_Key, $obj );
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
    my $ejection_iterator = $self->_get_ejection_iterator_for_policy();

    # Remove keys until we are under $ceiling
    #
    my $size = $self->get_size();
    while ( $size > $ceiling ) {
        if ( defined( my $key = $ejection_iterator->() ) ) {
            if ( my $data = $self->fetch($key) ) {
                $self->remove($key);
                $size -= length($data);
            }
        }
        else {
            die "should be empty!" unless $self->is_empty();
            last;
        }
    }
    $self->_set_size($size);
}

sub _get_ejection_iterator_for_policy {
    my ($self) = @_;

    my $ejection_sub =
      sprintf( "ejection_iterator_%s", $self->ejection_policy );
    if ( $self->can($ejection_sub) ) {
        return $self->$ejection_sub();
    }
    else {
        ## no critic (RequireCarping)
        die sprintf( "cannot get ejection iterator for policy '%s' ('%s')",
            $self->ejection_policy, $ejection_sub );
    }
}

sub ejection_iterator_arbitrary {
    my ($self) = @_;

    return $self->get_keys_iterator();
}

1;
