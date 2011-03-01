package CHI::Driver::Role::HasSubcaches;
use Moose::Role;
use Hash::MoreUtils qw(slice_exists);
use Log::Any qw($log);
use Scalar::Util qw(weaken);
use strict;
use warnings;

has 'l1_cache'     => ( is => 'ro', isa => 'CHI::Types::UnblessedHashRef' );
has 'mirror_cache' => ( is => 'ro', isa => 'CHI::Types::UnblessedHashRef' );
has 'subcaches'    => ( is => 'ro', default => sub { [] }, init_arg => undef );

# List of parameter keys that initialize a subcache
#
my @subcache_types = qw(l1_cache mirror_cache);

after 'BUILD_roles' => sub {
    my ( $self, $params ) = @_;

    $self->{has_subcaches} = 1;

    # Create subcaches as necessary (l1_cache, mirror_cache)
    # Eventually might allow existing caches to be passed
    #
    foreach my $subcache_type (@subcache_types) {
        if ( my $subcache_params = $params->{$subcache_type} ) {
            $self->add_subcache( $params, $subcache_type, $subcache_params );
        }
    }
};

# List of parameters that are automatically inherited by a subcache
#
my @subcache_inherited_param_keys = (
    qw(expires_at expires_in expires_variance namespace on_get_error on_set_error serializer)
);

# List of parameters that cannot be overriden in a subcache
#
my @subcache_nonoverride_param_keys =
  (qw(expires_at expires_in expires_variance serializer));

# Add a subcache with the specified type and params - called from BUILD
#
sub add_subcache {
    my ( $self, $params, $subcache_type, $subcache_params ) = @_;

    if ( my %nonoverride_params =
        slice_exists( $subcache_params, @subcache_nonoverride_param_keys ) )
    {
        my @nonoverride_keys = sort keys(%nonoverride_params);
        warn sprintf( "cannot override these keys in a subcache: %s",
            join( ", ", @nonoverride_keys ) );
        delete( @$subcache_params{@nonoverride_keys} );
    }

    my $chi_root_class = $self->chi_root_class;
    my %inherited_params =
      slice_exists( $params, @subcache_inherited_param_keys );
    my $default_label = $self->label . ":$subcache_type";

    my $subcache = $chi_root_class->new(
        label => $default_label,
        %inherited_params, %$subcache_params,
        is_subcache   => 1,
        parent_cache  => $self,
        subcache_type => $subcache_type,
    );
    $self->{$subcache_type} = $subcache;
    push( @{ $self->{subcaches} }, $subcache );
}

# Call these methods first on the main cache, then on any subcaches.
#
foreach my $method (qw(clear expire purge remove)) {
    after $method => sub {
        my $self      = shift;
        my $subcaches = $self->subcaches;
        foreach my $subcache (@$subcaches) {
            $subcache->$method(@_);
        }
    };
}

after 'set_object' => sub {
    my ( $self, $key, $obj ) = @_;

    my $subcaches = $self->subcaches;
    foreach my $subcache (@$subcaches) {
        $subcache->set(
            $key,
            $obj->value,
            {
                expires_at       => $obj->expires_at,
                early_expires_at => $obj->early_expires_at
            }
        );
    }
};

around 'get' => sub {
    my $orig = shift;
    my $self = shift;
    my ( $key, %params ) = @_;
    my $l1_cache = $self->l1_cache;

    if ( !defined($l1_cache) || $params{obj} ) {
        return $self->$orig(@_);
    }
    else {

        # Consult l1 cache first
        #
        if ( defined( my $value = $l1_cache->get(@_) ) ) {
            return $value;
        }
        else {
            my ( $key, %params ) = @_;
            $params{obj_ref} ||= \my $obj_store;
            my $value = $self->$orig( $key, %params );
            if ( defined($value) ) {

                # If found in primary cache, write back to l1 cache.
                #
                my $obj = ${ $params{obj_ref} };
                $l1_cache->set(
                    $key,
                    $obj->value,
                    {
                        expires_at       => $obj->expires_at,
                        early_expires_at => $obj->early_expires_at
                    }
                );
            }
            return $value;
        }
    }
};

around 'get_multi_arrayref' => sub {
    my $orig   = shift;
    my $self   = shift;
    my ($keys) = @_;

    my $l1_cache = $self->l1_cache;
    if ( !defined($l1_cache) ) {
        return $self->$orig(@_);
    }
    else {

        # Consult l1 cache first, then call on primary cache with remainder of keys,
        # and combine the arrays.
        #
        my $l1_values = $l1_cache->get_multi_arrayref($keys);
        my @indices   = ( 0 .. scalar(@$keys) - 1 );
        my @primary_keys =
          map { $keys->[$_] } grep { defined( $l1_values->[$_] ) } @indices;
        my $primary_values = $self->$orig( \@primary_keys );
        my $values         = [
            map {
                defined( $l1_values->[$_] )
                  ? $l1_values->[$_]
                  : shift(@$primary_values)
              } @indices
        ];
        return $values;
    }
};

1;
