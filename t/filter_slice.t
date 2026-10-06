# vi:filetype=
#
# Regression test for the slice module in front of a rendering location. slice
# fetches the response in ranges: the main request gets the first piece and
# subrequests fetch the rest, so the JSON never comes together in one place.
# This filter used to take the first piece for the whole JSON (500 "invalid
# json"); then to pass such a response through only once its body ended, which
# still failed it up front when its Content-Length (the whole file's) was over
# mustach_max_json_size, and also stopped rendering every other subrequest of
# the same main request. slice marks the requests it handles
# (r->subrequest_ranges) before this filter runs: those now pass through from
# the header filter on, whatever their size, and nothing else is affected.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 3 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: a sliced response passes through whole, with a warning
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        slice 16;
        mustach_template "[{{a}}]";
        proxy_set_header Range $slice_range;
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"a":"first-second-and-more"}
--- request
GET /test
--- response_body
{"a":"first-second-and-more"}
--- error_log
not rendering a response fetched by the slice module

=== TEST 2: ... whatever its size against mustach_max_json_size
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        slice 16;
        mustach_max_json_size 20;
        mustach_template "[{{a}}]";
        proxy_set_header Range $slice_range;
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"a":"first-second-and-more"}
--- request
GET /test
--- response_body
{"a":"first-second-and-more"}
--- no_error_log
mustach_max_json_size

=== TEST 3: ... even when it fits in one slice
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        slice 1m;
        mustach_template "[{{a}}]";
        proxy_set_header Range $slice_range;
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"a":"first-second-and-more"}
--- request
GET /test
--- response_body
{"a":"first-second-and-more"}
--- error_log
not rendering a response fetched by the slice module

=== TEST 4: another subrequest of a sliced main request is still rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /footer {
        default_type application/json;
        mustach_template "<footer {{f}}>";
        return 200 '{"f":"x"}';
    }
    location /test {
        slice 16;
        mustach_template "[{{a}}]";
        add_after_body /footer;
        addition_types application/json;
        proxy_set_header Range $slice_range;
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"a":"first-second-and-more"}
--- request
GET /test
--- response_body chop
{"a":"first-second-and-more"}
<footer x>
--- no_error_log
[error]
