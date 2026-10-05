# vi:filetype=
#
# Regression test for mustach_template_cache 0. The LRU used to insert the new
# entry and then evict the tail, which with a capacity of 0 was that very entry:
# its compiled template was freed and then rendered (use-after-free). 0 now
# means "no cache": a variable-sourced template is compiled per request and
# freed with the request pool.

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 7;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_template_cache 0 renders a variable template
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- http_config
    mustach_template_cache 0;
--- config
    location /test {
        set $template "{{a}}";
        mustach_template $template;
        mustach_content text/html;
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b
--- no_error_log
[alert]

=== TEST 2: mustach_template_cache 0 with an invalid template fails cleanly
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- http_config
    mustach_template_cache 0;
--- config
    location /test {
        set $template "{{#a}}";
        mustach_template $template;
        mustach_content text/html;
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- error_code: 500
--- no_error_log
[alert]

=== TEST 3: mustach_template_cache 1 still caches a variable template
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- http_config
    mustach_template_cache 1;
--- config
    location /test {
        set $template "{{a}}";
        mustach_template $template;
        mustach_content text/html;
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b
