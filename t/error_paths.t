# vi:filetype=
#
# Coverage for the runtime error branches in ngx_http_mustach_process():
# an empty rendered template, and a MUSTACH_ERROR_* return code from the
# mustach library itself (undefined tag, forced into an error via the
# errorundefined extension flag instead of the default silent-empty
# behaviour).

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: empty template is a request error, not a crash
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "";
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- error_code: 500
--- error_log
!template.len

=== TEST 2: undefined tag is a request error under errorundefined
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_flags errorundefined;
        mustach_template "{{missing}}";
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- error_code: 500
--- error_log
MUSTACH_ERROR_UNDEFINED_TAG

=== TEST 3: undefined tag renders empty without errorundefined
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template "[{{missing}}]";
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
[]
