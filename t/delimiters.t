# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

#$Test::Nginx::LWP::LogLevel = 'debug';

run_tests();

__DATA__

=== TEST 1: Pair Behavior
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "{{=<% %>=}}(<%text%>)";
        mustach_content text/html;
        return 200 '{
        "text": "Hey!"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"(Hey!)"
=== TEST 2: Special Characters
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "({{=[ ]=}}[text])";
        mustach_content text/html;
        return 200 '{
        "text": "It worked!"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"(It worked!)"
=== TEST 3: Sections
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "[\n{{#section}}\n  {{data}}\n  |data|\n{{/section}}\n\n{{=| |=}}\n|#section|\n  {{data}}\n  |data|\n|/section|\n]\n";
        mustach_content text/html;
        return 200 '{
        "section": true,
        "data": "I got interpolated."
      }';
    }
--- request
    GET /mustach
--- response_body eval
"[\n\n  I got interpolated.\n  |data|\n\n\n\n\n  {{data}}\n  I got interpolated.\n\n]\n"
=== TEST 4: Inverted Sections
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "[\n{{^section}}\n  {{data}}\n  |data|\n{{/section}}\n\n{{=| |=}}\n|^section|\n  {{data}}\n  |data|\n|/section|\n]\n";
        mustach_content text/html;
        return 200 '{
        "section": false,
        "data": "I got interpolated."
      }';
    }
--- request
    GET /mustach
--- response_body eval
"[\n\n  I got interpolated.\n  |data|\n\n\n\n\n  {{data}}\n  I got interpolated.\n\n]\n"
=== TEST 5: Partial Inheritence
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "[ {{>include}} ]\n{{=| |=}}\n[ |>include| ]\n";
        mustach_content text/html;
        return 200 '{
        "value": "yes",
        "include": ".{{value}}."
      }';
    }
--- request
    GET /mustach
--- response_body eval
"[ .yes. ]\n\n[ .{{value}}. ]\n"
=== TEST 6: Post-Partial Behavior
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "[ {{>include}} ]\n[ .{{value}}.  .|value|. ]\n";
        mustach_content text/html;
        return 200 '{
        "value": "yes",
        "include": ".{{value}}. {{=| |=}} .|value|."
      }';
    }
--- request
    GET /mustach
--- response_body eval
"[ .yes.  .yes. ]\n[ .yes.  .|value|. ]\n"
=== TEST 7: Surrounding Whitespace
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "| {{=@ @=}} |";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"|  |"
=== TEST 8: Outlying Whitespace (Inline)
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template " | {{=@ @=}}\n";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
" | \n"
=== TEST 9: Standalone Tag
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "Begin.\n  {{=@ @=}}\nEnd.\n";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"Begin.\n  \nEnd.\n"
=== TEST 10: Indented Standalone Tag
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "Begin.\n  {{=@ @=}}\nEnd.\n";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"Begin.\n  \nEnd.\n"
=== TEST 11: Standalone Line Endings
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "|\r\n{{=@ @=}}\r\n|";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"|\r\n\r\n|"
=== TEST 12: Standalone Without Previous Line
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "  {{=@ @=}}\n=";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"  \n="
=== TEST 13: Standalone Without Newline
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "=\n  {{=@ @=}}";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"=\n  "
=== TEST 14: Pair with Padding
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "|{{=@   @=}}|";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"||"
