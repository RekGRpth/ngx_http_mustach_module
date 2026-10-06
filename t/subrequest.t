# vi:filetype=
#
# Regression test for rendering inside a subrequest (SSI include, ...). The
# rendered buffer was always marked last_buf, which ends the whole response,
# so whatever the main request had after the include was lost:
# 'A<!--# include virtual="/render" -->B' came out as "A[b]". A subrequest's
# output now only ends its own part (last_in_chain).

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 3 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: SSI include of a content-handler location
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /page {
        ssi on;
        default_type text/html;
        return 200 'A<!--# include virtual="/render" -->B';
    }
    location /render {
        mustach_template "[{{a}}]";
        mustach_json '{"a":"b"}';
    }
--- request
GET /page
--- response_body chop
A[b]B
--- no_error_log
[alert]

=== TEST 2: SSI include of a filter-mode location
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /page {
        ssi on;
        default_type text/html;
        return 200 'A<!--# include virtual="/render" -->B';
    }
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /render {
        mustach_template "[{{a}}]";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /page
--- response_body chop
A[b]B
--- no_error_log
[alert]

=== TEST 3: two includes, one rendering to nothing
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /page {
        ssi on;
        default_type text/html;
        return 200 'A<!--# include virtual="/render" -->B<!--# include virtual="/empty" -->C';
    }
    location /render {
        mustach_template "[{{a}}]";
        mustach_json '{"a":"b"}';
    }
    location /empty {
        mustach_template "{{x}}";
        mustach_json '{}';
    }
--- request
GET /page
--- response_body chop
A[b]BC
--- no_error_log
[alert]
