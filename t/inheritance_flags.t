# vi:filetype=
#
# Regression test for sharing an inherited literal mustach_template between
# locations. Templates compiled at config time used to be compiled again in
# every location that inherited them and never freed, so the master leaked
# them all on each reload. Now a location shares its parent's compiled
# template, but only when the build-time flags (colon, emptytag) match:
# with different ones the template must still be compiled, and checked,
# with the location's own flags.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: inherited template with the same flags is shared and renders
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /p/ {
        mustach_template "a{{}}b{{c}}";
        location /p/test {
            mustach_content text/plain;
            mustach_json '{"c":"d"}';
        }
    }
--- request
GET /p/test
--- response_body chop
abd

=== TEST 2: inherited template is rebuilt with the location's own flags
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /p/ {
        mustach_template "a{{}}b{{c}}";
        location /p/test {
            mustach_flags noextensions;
            mustach_content text/plain;
            mustach_json '{"c":"d"}';
        }
    }
--- must_die
--- suppress_stderr
--- error_log
"mustach_template" error
