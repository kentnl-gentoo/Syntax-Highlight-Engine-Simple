use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Syntax::Highlight::Engine::Simple',
    license             => 'perl',
    dist_author         => 'Sugama Keita <sugama@jamadam.com>',
    dist_version_from   => 'lib/Syntax/Highlight/Engine/Simple.pm',
    requires => {
        'Test::More'			=> 0,
        'version'				=> 0,
        'UNIVERSAL::require'	=> 0,
        'encoding'				=> 0,
    },
    add_to_cleanup      => [ 'Syntax-Highlight-Engine-Simple-*' ],
);

$builder->create_build_script();
