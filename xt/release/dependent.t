use strict;
use warnings;
use Test::More;
BEGIN {
  plan skip_all => <<'END_HELP' unless $ENV{CHI_TEST_MD};
This test will not run unless you set CHI_TEST_MD to a true value.
END_HELP
}

use Test::DependentModules qw(test_modules);

#$ENV{CHI_REDIS_SERVER} = 1;       # CHI::Driver::Redis
#$ENV{FORCE_MEMCACHED_TESTS} = 1;  # CHI::Cascade
# extra dep: Cache::Memcached::libmemcached
test_modules(qw(
  CGI::Application::Plugin::CHI
  CHI::Cascade
  CHI::Driver::BerkeleyDB
  CHI::Driver::DBI
  CHI::Driver::Memcached
  CHI::Driver::Redis
  CHI::Driver::SharedMem
  CHI::Memoize
  Cache::Profile
  Dancer::Plugin::Cache::CHI
  Dancer::Session::CHI
  Dezi::Bot
  Dist::Zilla::Role::MetaCPANInterfacer
  Elastic::Model
  File::DataClass
  Mason::Plugin::Cache
  Metabase
  Mojito
  Mojolicious::Plugin::CHI
  Parallel::ForkControl
  Perlanet
  RDF::Helper::Properties
  Rose::DBx::Object::Cached::CHI
  Search::OpenSearch
  Tapper::Reports::DPath
  Tie::CHI
  Yukki
));

#Mojolicious::Plugin::Cache # broken
#Text::Corpus::CNN # broken
#Text::Corpus::VoiceOfAmerica # broken
#Geo::Heatmap # Image::Magick
#CHI::Driver::Ping # no useful tests, also insane
#CHI::Driver::MemcachedFast # tests broken
#CHI::Driver::HandlerSocket # missing dep Net::HandlerSocket
#App::ListPrereqs # no useful tests
#Poet # broken dep
#Plack::Middleware::ActiveMirror # no tests
#Apache2::AutoTicketLDAP # apache
#Net::FullAuto # wtf
#CHI::Driver::TokyoTyrant # darkpan
#Tapper::Testplan # tests broken
#Template::Provider::Amazon::S3 # no useful tests

done_testing;
