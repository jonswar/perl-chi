package CHI::Test::Logger;
use CHI::Util qw(dump_one_line);
use List::MoreUtils qw(first_index);
use Test::Deep qw(cmp_deeply);
use strict;
use warnings;
use Mouse;
use strict;
use warnings;

has 'msgs' => ( is => 'ro' );

foreach my $level (qw(fatal error warn info debug)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$level" } = sub {
        my ( $self, $msg ) = @_;
        $self->{msgs} ||= [];
        push( @{ $self->{msgs} }, $msg );
    };
    *{ __PACKAGE__ . "::is_$level" } = sub { 1 };
}

__PACKAGE__->meta->make_immutable();

sub contains_ok {
    my ( $self, $regex ) = @_;
    my $tb = Test::Builder->new();

    my $found = first_index { /$regex/ } @{ $self->{msgs} };
    if ( $found != -1 ) {
        splice( @{ $self->{msgs} }, $found, 1 );
        $tb->ok( 1, "found message matching $regex" );
    }
    else {
        $tb->ok( 0,
            "could not find message matching $regex; log contains: "
              . dump_one_line( $self->{msgs} ) );
    }
}

sub clear {
    my ($self) = @_;

    $self->{msgs} = [];
}

sub empty_ok {
    my ($self) = @_;
    my $tb = Test::Builder->new();

    if ( !@{ $self->{msgs} } ) {
        $tb->ok( 1, "log is empty" );
    }
    else {
        $tb->ok( 0,
            "log is not empty; contains " . dump_one_line( $self->{msgs} ) );
    }
}

1;
