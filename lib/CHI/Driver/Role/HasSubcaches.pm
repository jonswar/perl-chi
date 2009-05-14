package CHI::Driver::Role::HasSubcaches;
use Moose::Role;
use Hash::MoreUtils qw(slice_exists);
use Scalar::Util qw(weaken);
use strict;
use warnings;

# List of parameters that are automatically inherited by a subcache
#
my @subcache_inherited_param_keys = (
    qw(expires_at expires_in expires_variance namespace on_get_error on_set_error)
);

# Add a subcache with the specified type and params - called from
# CHI::Driver::BUILD
#
sub add_subcache {
    my ( $self, $params, $subcache_type, $subcache_params ) = @_;

    my $chi_root_class = $self->chi_root_class;
    my %inherited_params =
      slice_exists( $params, @subcache_inherited_param_keys );
    my $default_label = $self->label . ":$subcache_type";
    my $subcache      = $chi_root_class->new(
        label => $default_label,
        %inherited_params, %$subcache_params
    );
    $subcache->{subcache_type} = $subcache_type;
    $subcache->{parent_cache}  = $self;
    weaken( $subcache->{parent_cache} );
    $self->{$subcache_type} = $subcache;
    push( @{ $self->{subcaches} }, $subcache );
}

# Call these methods first on the main cache, then on any subcaches.
#
foreach my $method (qw(clear expire expire_if purge remove set)) {
    after $method => sub {
        my $self      = shift;
        my $subcaches = $self->subcaches;
        foreach my $subcache (@$subcaches) {
            $subcache->$method(@_);
        }
    };
}

around 'get' => sub {
    my $orig     = shift;
    my $self     = shift;
    my $l1_cache = $self->l1_cache;

    if ( !defined($l1_cache) ) {
        return $self->$orig(@_);
    }
    else {

        # Consult l1 cache first
        #
        if ( defined( my $value = $l1_cache->get(@_) ) ) {
            return $value;
        }
        else {
            my $value = $self->$orig( @_, obj_ref => \my $obj );
            if ( defined($value) ) {

                # If found in primary cache, write back to l1 cache
                #
                my $key = $_[0];
                $l1_cache->set(
                    $key, $value,
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

around 'get_multi_hashref' => sub {
    my $orig   = shift;
    my $self   = shift;
    my ($keys) = @_;

    my $l1_cache = $self->l1_cache;
    if ( !defined($l1_cache) ) {
        return $self->$orig(@_);
    }
    else {

        # Consult l1 cache first, then call on primary cache with remainder of keys,
        # and combine the hashes.
        #
        my $l1_result      = $l1_cache->get_multi_hashref($keys);
        my @primary_keys   = grep { !defined( $l1_result->{$_} ) } @$keys;
        my $primary_result = $self->$orig( \@primary_keys );
        my $result         = { %$l1_result, %$primary_result };
        return $result;
    }
};

1;
