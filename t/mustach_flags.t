# vi:filetype=
#
# Coverage for the mustach_flags directive itself (ngx_http_mustach_flags_conf):
# accepting known extension names, combining several of them, and rejecting an
# unknown one. The extensions' actual rendering semantics are already exercised
# via the default (AllExtensions) flags value in long.t.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_flags with a single known extension
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_flags colon;
        mustach_template "{{:#sharp}}";
        mustach_json '{"#sharp":"#"}';
    }
--- request
    GET /test
--- response_body chop
#

=== TEST 2: mustach_flags with several extensions combined
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_flags colon compare;
        mustach_template "{{:#sharp}}";
        mustach_json '{"#sharp":"#"}';
    }
--- request
    GET /test
--- response_body chop
#

=== TEST 3: unknown mustach_flags value is rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{a}}";
        mustach_flags bogus;
        mustach_json '{"a":"b"}';
    }
--- must_die
--- suppress_stderr
--- error_log
directive error: value "bogus" must be

=== TEST 4: duplicate mustach_flags directive is rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{a}}";
        mustach_flags colon;
        mustach_flags compare;
        mustach_json '{"a":"b"}';
    }
--- must_die
--- suppress_stderr
--- error_log
is duplicate
