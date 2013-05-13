package CHI::Driver::Null;
use Moo;
use strict;
use warnings;

extends 'CHI::Driver';

sub fetch          { undef }
sub store          { undef }
sub remove         { undef }
sub clear          { undef }
sub get_keys       { return () }
sub get_namespaces { return () }

1;

__END__

=pod

=head1 NAME

CHI::Driver::Null - Nothing is cached

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(driver => 'Null');
    $cache->set('key', 5);
    my $value = $cache->get('key');   # returns undef

=head1 DESCRIPTION

This cache driver implements the full CHI interface without ever actually
storing items. Useful for disabling caching in an application, for example.

=cut
