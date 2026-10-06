# vi:filetype=
#
# Regression test for mustach_data_partials_limit. A partial taken from the
# data is a template the JSON supplies, and each lookup of one cost work and
# request-pool memory with no bound, even when it output nothing (which
# mustach_max_output_size can't see). Each lookup is now charged against a
# per-render budget: its length, at least 64 bytes; past it, a 500.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: partials within the budget are rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_data_partials_limit 128;
        mustach_template "[{{>a}}][{{>b}}]";
        mustach_content text/plain;
        mustach_json '{"a":"first","b":"second"}';
    }
--- request
GET /test
--- response_body chop
[first][second]

=== TEST 2: one lookup past the budget is a 500
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_data_partials_limit 127;
        mustach_template "[{{>a}}][{{>b}}]";
        mustach_content text/plain;
        mustach_json '{"a":"first","b":"second"}';
    }
--- request
GET /test
--- error_code: 500
--- error_log
partials from the data exceed mustach_data_partials_limit

=== TEST 3: a partial longer than 64 bytes is charged its length
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_data_partials_limit 99;
        mustach_template "[{{>a}}]";
        mustach_content text/plain;
        mustach_json '{"a":"0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"}';
    }
--- request
GET /test
--- error_code: 500
--- error_log
partials from the data exceed mustach_data_partials_limit

=== TEST 4: 0 lifts the limit
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_data_partials_limit 0;
        mustach_template "[{{>a}}][{{>b}}]";
        mustach_content text/plain;
        mustach_json '{"a":"first","b":"second"}';
    }
--- request
GET /test
--- response_body chop
[first][second]

=== TEST 5: partials from files aren't charged for their contents
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_data_partials_limit 64;
        mustach_partials_root html;
        mustach_template "[{{>f}}]";
        mustach_content text/plain;
        mustach_json '{}';
    }
--- user_files eval
">>> f.mustache\n" . ('z' x 500)
--- request
GET /test
--- response_body eval
'[' . ('z' x 500) . ']'
