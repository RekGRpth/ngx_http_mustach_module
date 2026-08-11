# vi:filetype=
#
# Coverage for ngx_http_mustach_merge_loc_conf inheriting content/json/template
# from a parent location into a nested child that doesn't redeclare them.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: nested location inherits mustach_template and mustach_content from the parent
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /parent {
        mustach_content text/html;
        mustach_template "{{a}}";
        location /parent/child {
            mustach_json '{"a":"inherited"}';
        }
    }
--- request
    GET /parent/child
--- response_body chop
inherited

=== TEST 2: nested location overrides only what it redeclares
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /parent {
        mustach_content text/html;
        mustach_template "{{a}}";
        mustach_json '{"a":"parent"}';
        location /parent/child {
            mustach_json '{"a":"child"}';
        }
    }
--- request
    GET /parent/child
--- response_body chop
child
