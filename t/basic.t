use strict;
use warnings;

use Test::More;

# FILENAME: basic.t
# CREATED: 09/11/14 15:02:38 by Kent Fredric (kentnl) <kentfredric@gmail.com>
# ABSTRACT: Basic do-someting test.

use Dist::Zilla::Util::Test::KENTNL 1.003002 qw( dztest );
use Test::DZil qw( simple_ini );

my $test = dztest();
$test->add_file(
  'dist.ini',
  simple_ini(
    [ 'Prereqs', 'TestRequires',    { 'Foo' => '6.0' } ],    #
    [ 'Prereqs', 'RuntimeRequires', { 'Foo' => '5.0' } ],    #
    ['Prereqs::SyncVersions'],                               #
  )
);
$test->build_ok;

note explain $test->distmeta;

done_testing;
