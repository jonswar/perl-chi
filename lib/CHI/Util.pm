package CHI::Util;
use strict;
use warnings;
use Carp;
use Data::Dumper;
use File::Spec;
use Regexp::Common qw(number);
use Sys::HostIP;
use Time::Duration::Parse;
use base qw(Exporter);

our @EXPORT_OK = qw(
  dp
  dump_one_line
  escape_for_filename
  parse_duration
  unescape_for_filename
  unique_id
);

sub _dump_value_with_caller {
    my ($value) = @_;

    my $dump =
      Data::Dumper->new( [$value] )->Indent(1)->Sortkeys(1)->Quotekeys(0)
      ->Terse(1)->Dump();
    my @caller = caller(1);
    return
      sprintf( "[%s line %d] [%d] %s\n", $caller[1], $caller[2], $$, $dump );
}

sub dp {
    print STDERR _dump_value_with_caller(@_);
}

sub dump_one_line {
    my ($value) = @_;

    return Data::Dumper->new( [$value] )->Indent(0)->Sortkeys(1)->Quotekeys(0)
      ->Terse(1)->Dump();
}

{

    # Adapted from Sys::UniqueID
    my $idnum = 0;
    my $netaddr = sprintf( '%02X%02X%02X%02X', split( /\./, Sys::HostIP->ip ) );

    sub unique_id {
        return sprintf '%012X.%s.%08X.%08X', time, $netaddr, $$, ++$idnum;
    }
}

{

    # Adapted from URI::Escape, but use '+' for escape character, like Mason's compress_path
    my %escapes;
    for ( 0 .. 255 ) {
        $escapes{ chr($_) } = sprintf( "+%02x", $_ );
    }

    sub _fail_hi {
        my $chr = shift;
        Carp::croak( sprintf "Can't escape multibyte character \\x{%04X}",
            ord($chr) );
    }

    sub escape_for_filename {
        my ($text) = @_;

        $text =~ s/([^\w\=\-\~])/$escapes{$1} || _fail_hi($1)/ge;
        $text;
    }

    sub unescape_for_filename {
        my ($str) = @_;

        $str =~ s/\+([0-9A-Fa-f]{2})/chr(hex($1))/eg if defined $str;
        $str;
    }
}

1;
