package CHI::Types;
use Carp;
use CHI::Util qw(can_load parse_duration parse_memory_size);
use MooX::Types::MooseLike qw(exception_message);
use MooX::Types::MooseLike::Base qw(:all);
use MooX::Types::MooseLike::Numeric qw(:all);
use Scalar::Util qw(blessed);
use base qw(Exporter);
use strict;
use warnings;

our @EXPORT_OK = ();
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

MooX::Types::MooseLike::register_types([
{
    name => 'OnError',
    test => sub { ref($_[0]) eq 'CODE' || $_[0] =~ /^(?:ignore|warn|die|log)$/ },
    message => sub { return exception_message($_[0], 'a coderef or error level') },
},
{
    name => 'Duration',
    subtype_of => 'PositiveInt',
    from => 'MooX::Types::MooseLike::Numeric',
    test =>  sub { 1 },
    message => sub { return exception_message($_[0], 'a positive integer') },
},
{
    name => 'MemorySize',
    subtype_of => 'PositiveInt',
    from => 'MooX::Types::MooseLike::Numeric',
    test => sub { 1 },
    message => sub { return exception_message($_[0], 'a positive integer') },
},
{
    name => 'DiscardPolicy',
    test => sub { !ref($_) || ref($_) eq 'CODE' },
    message => sub { return exception_message($_[0], 'a coderef or policy name') },
},
{
    name => 'Serializer',
    subtype_of => 'Object',
    from => 'MooX::Types::MooseLike::Base',
    test => sub { 1 },
    message => sub { return exception_message($_[0], 'a serializer, hashref, or string') },
},
{
    name => 'Digester',
    subtype_of => 'Object',
    from => 'MooX::Types::MooseLike::Base',
    test => sub { 1 },
    message => sub { return exception_message($_[0], 'a digester, hashref, or string') },
}
], __PACKAGE__);

sub to_MemorySize {
    my $from = shift;
    if (is_Str($from)) {
        parse_memory_size($from);
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_MemorySize';

sub to_Duration {
    my $from = shift;
    if (is_Str($from)) {
        parse_duration($from);
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_Duration';

sub to_Serializer {
    my $from = shift;
    if (is_HashRef($from)) {
        _build_data_serializer($from);
    }
    elsif (is_Str($from)) {
        _build_data_serializer( { serializer => $from, raw => 1 } );
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_Serializer';

sub to_Digester {
    my $from = shift;
    if (is_HashRef($from)) {
        _build_digester(%$from);
    }
    elsif (is_Str($from)) {
        _build_digester($from);
    }
    else {
        $from;
    }
}
push @EXPORT_OK, 'to_Digester';

my $data_serializer_loaded = can_load('Data::Serializer');

my $digest_loaded = can_load('Digest');

sub _build_data_serializer {
    my ($params) = @_;

    if ($data_serializer_loaded) {
        return Data::Serializer->new(%$params);
    }
    else {
        croak
          "Could not load Data::Serializer - install Data::Serializer from CPAN to support serializer argument";
    }
}

sub _build_digester {
    if ($digest_loaded) {
        return Digest->new(@_);
    }
    else {
        croak "Digest could not be loaded, cannot handle digester argument";
    }
}

1;
