# vi:filetype=
#
# Regression test for where partials ({{> name}}) may come from. mustach-wrap,
# left to itself, reads a partial it doesn't find in the data from `name` as a
# file path, relative to the worker's working directory or absolute. Since a
# partial taken from the data is itself a template, the JSON alone (from an
# upstream or a client) could pull any file the worker can read into the
# response. Partials now come from the data and, only when
# mustach_partials_root is set, from that one directory, by a single path
# component.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: without mustach_partials_root, a template can't name a file
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config eval
qq|
    location /test {
        mustach_template "[{{> $Test::Nginx::Util::ServRoot/html/secret.txt}}][{{> t/servroot/html/secret.txt}}]";
        mustach_json '{}';
    }
|
--- user_files
>>> secret.txt
SECRET
--- request
GET /test
--- response_body chop
[][]

=== TEST 2: a partial supplied by upstream JSON can't name a file
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config eval
qq|
    location /backend {
        default_type application/json;
        return 200 '{"p":"[{{> $Test::Nginx::Util::ServRoot/html/secret.txt}}]"}';
    }
    location /test {
        mustach_template "{{>p}}";
        mustach_partials_root html;
        proxy_pass http://127.0.0.1:\$server_port/backend;
    }
|
--- user_files
>>> secret.txt
SECRET
--- request
GET /test
--- response_body chop
[]

=== TEST 3: mustach_partials_root serves partials from that directory
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{#items}}{{>row}}{{/items}}";
        mustach_partials_root html;
        mustach_json '{"items":[{"n":1},{"n":2}]}';
    }
--- user_files
>>> row.mustache
<{{n}}>
--- request
GET /test
--- response_body
<1>
<2>

=== TEST 4: names can't leave mustach_partials_root
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{> ../html/secret.txt}}][{{>..}}][{{> /etc/hostname}}]";
        mustach_partials_root html;
        mustach_json '{}';
    }
--- user_files
>>> secret.txt
SECRET
--- request
GET /test
--- response_body chop
[][][]

=== TEST 5: data comes before files by default (partialdatafirst)
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{>row}}]";
        mustach_partials_root html;
        mustach_json '{"row":"from data"}';
    }
--- user_files
>>> row.mustache
from file
--- request
GET /test
--- response_body chop
[from data]

=== TEST 6: files come before data without partialdatafirst
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_flags noextensions;
        mustach_template "[{{>row}}]";
        mustach_partials_root html;
        mustach_json '{"row":"from data"}';
    }
--- user_files
>>> row
from file
--- request
GET /test
--- response_body chop
[from file
]

=== TEST 7: data partials work without partialdatafirst
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_flags noextensions;
        mustach_template "[{{>p}}]";
        mustach_json '{"p":"ok"}';
    }
--- request
GET /test
--- response_body chop
[ok]
