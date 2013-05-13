package CHI::Driver::CacheCache;
use Cache::Cache;
use Carp;
use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use Module::Runtime qw(require_module);
use strict;
use warnings;

extends 'CHI::Driver::Base::CacheContainer';

has 'cc_class'   => ( is => 'ro', isa => Str, required => 1 );
has 'cc_options' => ( is => 'ro', isa => HashRef, required => 1 );

sub BUILD {
    my ( $self, $params ) = @_;

    $self->{_contained_cache} = $self->_build_contained_cache;
}

sub _build_contained_cache {
    my ($self) = @_;

    my $cc_class   = $self->{cc_class};
    my $cc_options = $self->{cc_options};
    my %subparams  = ( namespace => $self->namespace );

    require_module($cc_class);

    my %final_cc_params = ( %subparams, %{$cc_options} );

    return $cc_class->new( \%final_cc_params );
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::CacheCache - CHI wrapper for Cache::Cache

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(
        driver     => 'CacheCache',
        cc_class   => 'Cache::FileCache',
        cc_options => { cache_root => '/path/to/cache/root' },
    );

=head1 DESCRIPTION

This driver wraps any Cache::Cache cache.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in
addition to the L<CHI|general constructor options/constructor>.

=over

=item cc_class

Name of Cache::Cache class to create, e.g. Cache::FileCache. Required.

=item cc_options

Hashref of options to pass to Cache::Cache constructor. Required.

=back

=cut
