package CHI::Driver::CacheCache;
use strict;
use warnings;
use Cache::Cache;
use Carp;
use CHI::Util qw(require_dynamic);
use Hash::MoreUtils qw(slice_exists);
use base qw(CHI::Driver::Base::CacheContainer);

__PACKAGE__->mk_ro_accessors(qw(cc_class cc_options));

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    my $cc_class = $self->{cc_class}
      or croak "missing required parameter 'cc_class'";
    my $cc_options = $self->{cc_options}
      or croak "missing required parameter 'cc_options'";
    my %subparams = slice_exists( $_[0], 'namespace' );

    require_dynamic($cc_class);

    my %final_cc_params = ( %subparams, %{$cc_options} );
    $self->{_contained_cache} = $self->{cc_cache} =
      $cc_class->new( \%final_cc_params );

    return $self;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::CacheCache -- CHI wrapper for Cache::Cache

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

When using this driver, the following options can be passed to CHI->new() in addition to the
L<CHI|general constructor options/constructor>.
    
=over

=item cc_class

Name of Cache::Cache class to create, e.g. Cache::FileCache. Required.

=item cc_options

Hashref of options to pass to Cache::Cache constructor. Required.

=back

=head1 SEE ALSO

Cache::Cache
CHI

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
