# vi:filetype=
#
# Coverage for the mustach_type directive and its explicitly-selected JSON
# backends (mustach_process_cjson / mustach_process_jansson / mustach_process_json_c
# in mustach-cjson.c / mustach-jansson.c / mustach-json-c.c). jsmn is the
# default backend (mustach-jsmn.c) since it needs no external JSON library
# and has no symbol-collision exposure, so the rest of the suite already
# exercises it without setting mustach_type explicitly.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_type cjson
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_type cjson;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li></ul>

=== TEST 2: mustach_type jansson
# Currently broken: variable lookups always resolve to the whole JSON
# document instead of the named field's value. Root cause (confirmed via
# LD_DEBUG=bindings): libmustach.so links cjson + json-c + jansson into one
# shared object, and json-c's json_object_get(obj) (refcount increment,
# 1 arg) and jansson's json_object_get(obj, key) (field lookup, 2 args)
# share the same symbol name. The dynamic linker resolves mustach-jansson.c's
# calls to json-c's version process-wide, so the "key" argument is silently
# dropped and every lookup just returns the input object unchanged -- hence
# the whole document coming back instead of a field. This is an upstream
# mustach/json-c/jansson linking hazard (needs a fix in mustach-jansson.c
# in the sibling mustach repo, or a linking-scheme change), not a bug in
# this module's own code. Kept (skipped) so a future fix gets noticed.
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_type jansson;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li></ul>
--- SKIP

=== TEST 3: mustach_type json-c
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_type json-c;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li></ul>

=== TEST 4: mustach_type jsmn
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_type jsmn;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li></ul>

=== TEST 5: mustach_type jsmn with nesting and falsy sections
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_type jsmn;
        mustach_template '{{a.b}}|{{#truthy}}T{{/truthy}}{{^truthy}}F{{/truthy}}|{{#falsy}}T{{/falsy}}{{^falsy}}F{{/falsy}}|[{{missing}}]';
        mustach_json '{"a":{"b":"nested"},"truthy":"x","falsy":"","zero":0}';
    }
--- request
    GET /test
--- response_body chop
nested|T|F|[]

=== TEST 6: mustach_type jsmn decodes JSON string escapes delivered over the wire
# JSON string escapes (\n, \t, \") can't be tested via a literal in any
# nginx directive argument, including mustach_json and echo: nginx's own
# config-file lexer (ngx_conf_read_token) unescapes \n/\t/\"/\\/\' in
# directive values before this module ever sees them, so a config literal
# can't deliver a raw backslash-escape sequence for jsmn to decode -- a
# general characteristic of nginx.conf, not specific to the jsmn backend.
# --- user_files bypasses the config parser entirely (the content is
# written to disk as-is), so serving it as a static file and running it
# through the body-filter path (like split_body.t does) is the only way to
# deliver a literal backslash-escape here.
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend.json {
        default_type application/json;
        root html;
    }
    location /test {
        mustach_type jsmn;
        mustach_template "{{msg}}|{{emoji}}";
        proxy_pass http://127.0.0.1:$server_port/backend.json;
    }
--- user_files
>>> backend.json
{"msg":"line1\nline2\ttab\"quote\"","emoji":"😀"}
--- request
    GET /test
--- response_body chop
line1
line2	tab&quot;quote&quot;|😀

=== TEST 7: invalid mustach_type value is rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{a}}";
        mustach_type bogus;
        mustach_json '{"a":"b"}';
    }
--- must_die
--- suppress_stderr
--- error_log
invalid value "bogus"
