# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

#$Test::Nginx::LWP::LogLevel = 'debug';

our $main_config = <<'_EOC_';
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
_EOC_

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Basic Behavior
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{>text}}\"";
        mustach_content text/html;
        return 200 '{
        "text": "from partial"
      }';
    }
--- request
    GET /test
--- response_body eval
"\"from partial\""
=== TEST 2: Failed Lookup
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{>text}}\"";
        mustach_content text/html;
        return 200 '{
      }';
    }
--- request
    GET /test
--- response_body eval
"\"\""
=== TEST 3: Context
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{>partial}}\"";
        mustach_content text/html;
        return 200 '{
        "text": "content",
        "partial": "*{{text}}*"
      }';
    }
--- request
    GET /test
--- response_body eval
"\"*content*\""
=== TEST 4: Recursion
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "{{>node}}";
        mustach_content text/html;
        return 200 '{
        "content": "X",
        "nodes": [
          {
            "content": "Y",
            "nodes": [

            ]
          }
        ],
        "node": "{{content}}<{{#nodes}}{{>node}}{{/nodes}}>"
      }';
    }
--- request
    GET /test
--- response_body eval
"X<Y<>>"
=== TEST 5: Surrounding Whitespace
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "| {{>partial}} |";
        mustach_content text/html;
        return 200 '{
        "partial": "\t|\t"
      }';
    }
--- request
    GET /test
--- response_body eval
"| \t|\t |"
=== TEST 6: Inline Indentation
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "  {{data}}  {{> partial}}\n";
        mustach_content text/html;
        return 200 '{
        "data": "|",
        "partial": ">\n>"
      }';
    }
--- request
    GET /test
--- response_body eval
"  |  >\n>\n"
=== TEST 7: Standalone Line Endings
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "|\r\n{{>partial}}\r\n|";
        mustach_content text/html;
        return 200 '{
        "partial": ">"
      }';
    }
--- request
    GET /test
--- response_body eval
"|\r\n>\r\n|"
=== TEST 8: Standalone Without Previous Line
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "  {{>partial}}\n>";
        mustach_content text/html;
        return 200 '{
        "partial": ">\n>"
      }';
    }
--- request
    GET /test
--- response_body eval
"  >\n>\n>"
=== TEST 9: Standalone Without Newline
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template ">\n  {{>partial}}";
        mustach_content text/html;
        return 200 '{
        "partial": ">\n>"
      }';
    }
--- request
    GET /test
--- response_body eval
">\n  >\n>"
=== TEST 10: Standalone Indentation
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\\\n {{>partial}}\n/\n";
        mustach_content text/html;
        return 200 '{
        "content": "<\n->",
        "partial": "|\n{{{content}}}\n|\n"
      }';
    }
--- request
    GET /test
--- response_body eval
"\\\n |\n<\n->\n|\n\n/\n"
=== TEST 11: Padding Whitespace
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "|{{> partial }}|";
        mustach_content text/html;
        return 200 '{
        "boolean": true,
        "partial": "[]"
      }';
    }
--- request
    GET /test
--- response_body eval
"|[]|"
