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

=== TEST 1: mustach
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_content text/html;
        mustach_template 'Hello {{name}}
You have just won {{value}} dollars!
{{#in_ca}}
Well, {{taxed_value}} dollars, after taxes.
{{/in_ca}}
Shown.
{{#person}}
  Never shown!
{{/person}}
{{^person}}
  No person
{{/person}}

{{#repo}}
  <b>{{name}}</b> reviewers:{{#who}} {{reviewer}}{{/who}} commiters:{{#who}} {{commiter}}{{/who}}
{{/repo}}

{{#person?}}
  Hi {{name}}!
{{/person?}}

{{=%(% %)%=}}
 =====================================
%(%! gros commentaire %)%
%(%#repo%)%
  <b>%(%name%)%</b> reviewers:%(%#who%)% %(%reviewer%)%%(%/who%)% commiters:%(%#who%)% %(%commiter%)%%(%/who%)%
%(%/repo%)%
 =====================================
%(%={{ }}=%)%
ggggggggg
{{> special}}
jjjjjjjjj
end

{{:#sharp}}
{{:!bang}}
{{:~tilde}}
{{:/~0tilde}}
{{:/~1slash}} see json pointers IETF RFC 6901
{{:^circ}}
{{:\=equal}}
{{::colon}}
{{:>greater}}';
        return 200 '{
  "name": "Chris",
  "value": 10000,
  "taxed_value": 6000,
  "in_ca": true,
  "person": false,
  "repo": [
    { "name": "resque", "who": [ { "commiter": "joe" }, { "reviewer": "avrel" }, { "commiter": "william" } ] },
    { "name": "hub", "who": [ { "commiter": "jack" }, { "reviewer": "avrel" }, { "commiter": "greg" } ]  },
    { "name": "rip", "who": [ { "reviewer": "joe" }, { "reviewer": "jack" }, { "commiter": "greg" } ]  }
  ],
  "person?": { "name": "Jon" },
  "special": "----{{extra}}----",
  "extra": 3.14159,
  "#sharp": "#",
  "!bang": "!",
  "/slash": "/",
  "^circ": "^",
  "=equal": "=",
  ":colon": ":",
  ">greater": ">",
  "~tilde": "~"
}';
    }
--- request
    GET /test
--- response_body chop
Hello Chris
You have just won 10000 dollars!
Well, 6000 dollars, after taxes.
Shown.
  No person

  <b>resque</b> reviewers:  avrel  commiters: joe  william
  <b>hub</b> reviewers:  avrel  commiters: jack  greg
  <b>rip</b> reviewers: joe jack  commiters:   greg

  Hi Jon!

 =====================================
  <b>resque</b> reviewers:  avrel  commiters: joe  william
  <b>hub</b> reviewers:  avrel  commiters: jack  greg
  <b>rip</b> reviewers: joe jack  commiters:   greg
 =====================================
ggggggggg
----3.14159----jjjjjjjjj
end

#
!
~
~
/ see json pointers IETF RFC 6901
^
=
:
&gt;
=== TEST 2: mustach
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_content text/html;
        mustach_template '<h1>{{header}}</h1>
{{#bug}}
{{/bug}}

{{#items}}
  {{#first}}
    <li><strong>{{name}}</strong></li>
  {{/first}}
  {{#link}}
    <li><a href="{{url}}">{{name}}</a></li>
  {{/link}}
{{/items}}

{{#empty}}
  <p>The list is empty.</p>
{{/empty}}';
        return 200 '{
  "header": "Colors",
  "items": [
      {"name": "red", "first": true, "url": "#Red"},
      {"name": "green", "link": true, "url": "#Green"},
      {"name": "blue", "link": true, "url": "#Blue"}
  ],
  "empty": false
}';
    }
--- request
    GET /test
--- response_body eval
'<h1>Colors</h1>

    <li><strong>red</strong></li>
    <li><a href="#Green">green</a></li>
    <li><a href="#Blue">blue</a></li>

'
=== TEST 3: mustach
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_content text/html;
        mustach_template '* {{name}}
* {{age}}
* {{company}}
* {{&company}}
* {{{company}}}
{{=<% %>=}}
* <%company%>
* <%&company%>
* <%{company}%>

<%={{ }}=%>
* <ul>{{#names}}<li>{{.}}</li>{{/names}}</ul>
* skills: <ul>{{#skills}}<li>{{.}}</li>{{/skills}}</ul>
{{#age}}* age: {{.}}{{/age}}';
        return 200 '{
  "name": "Chris",
  "company": "<b>GitHub & Co</b>",
  "names": ["Chris", "Kross"],
  "skills": ["JavaScript", "PHP", "Java"],
  "age": 18
}';
    }
--- request
    GET /test
--- response_body chop
* Chris
* 18
* &lt;b&gt;GitHub &amp; Co&lt;/b&gt;
* <b>GitHub & Co</b>
* <b>GitHub & Co</b>
* &lt;b&gt;GitHub &amp; Co&lt;/b&gt;
* <b>GitHub & Co</b>
* <b>GitHub & Co</b>

* <ul><li>Chris</li><li>Kross</li></ul>
* skills: <ul><li>JavaScript</li><li>PHP</li><li>Java</li></ul>
* age: 18
=== TEST 4: mustach
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_content text/html;
        mustach_template 'This are extensions!!

{{person.name}}
{{person.age}}

{{person\.name}}
{{person\.name\=Fred}}

{{#person.name=Jon}}
Hello Jon
{{/person.name=Jon}}

{{^person.name=Jon}}
No Jon? Hey Jon...
{{/person.name=Jon}}

{{^person.name=Harry}}
No Harry? Hey Calahan...
{{/person.name=Harry}}

{{#person\.name=Fred}}
Hello Fred
{{/person\.name=Fred}}

{{^person\.name=Fred}}
No Fred? Hey Fred...
{{/person\.name=Fred}}

{{#person\.name\=Fred=The other Fred.}}
Hello Fred#2
{{/person\.name\=Fred=The other Fred.}}

{{^person\.name\=Fred=The other Fred.}}
No Fred#2? Hey Fred#2...
{{/person\.name\=Fred=The other Fred.}}

{{#persons}}
{{#lang=!fr}}Hello {{name}}, {{age}} years{{/lang=!fr}}
{{#lang=fr}}Salut {{name}}, {{age}} ans{{/lang=fr}}
{{/persons}}

{{#persons}}
{{name}}: {{age=24}}/{{age}}/{{age=!27}}
{{/persons}}

{{#fellows.*}}
{{*}}: {{age=24}}/{{age}}/{{age=!27}}
{{/fellows.*}}

{{#*}}
 (1) {{*}}: {{.}}
   {{#*}}
     (2) {{*}}: {{.}}
     {{#*}}
       (3) {{*}}: {{.}}
     {{/*}}
   {{/*}}
{{/*}}';
        return 200 '{
  "person": { "name": "Jon", "age": 25 },
  "person.name": "Fred",
  "person.name=Fred": "The other Fred.",
  "persons": [
	{ "name": "Jon", "age": 25, "lang": "en" },
	{ "name": "Henry", "age": 27, "lang": "en" },
	{ "name": "Amed", "age": 24, "lang": "fr" } ],
  "fellows": {
	"Jon": { "age": 25, "lang": "en" },
	"Henry": { "age": 27, "lang": "en" },
	"Amed": { "age": 24, "lang": "fr" } }
}';
    }
--- request
    GET /test
--- response_body eval
'This are extensions!!

Jon
25

Fred
The other Fred.


Hello Jon





No Harry? Hey Calahan...



Hello Fred





Hello Fred#2





Hello Jon, 25 years


Hello Henry, 27 years



Salut Amed, 24 ans



Jon: /25/25

Henry: /27/

Amed: 24/24/24



Jon: /25/25

Henry: /27/

Amed: 24/24/24



 (1) person: {"name":"Jon","age":25}
   
     (2) name: Jon
     
   
     (2) age: 25
     
   

 (1) person.name: Fred
   

 (1) person.name=Fred: The other Fred.
   

 (1) persons: [{"name":"Jon","age":25,"lang":"en"},{"name":"Henry","age":27,"lang":"en"},{"name":"Amed","age":24,"lang":"fr"}]
   

 (1) fellows: {"Jon":{"age":25,"lang":"en"},"Henry":{"age":27,"lang":"en"},"Amed":{"age":24,"lang":"fr"}}
   
     (2) Jon: {"age":25,"lang":"en"}
     
       (3) age: 25
     
       (3) lang: en
     
   
     (2) Henry: {"age":27,"lang":"en"}
     
       (3) age: 27
     
       (3) lang: en
     
   
     (2) Amed: {"age":24,"lang":"fr"}
     
       (3) age: 24
     
       (3) lang: fr
     
   
'
--- SKIP
=== TEST 5: mustach
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_content text/html;
        mustach_template ' =====================================
from json
{{> special}}
 =====================================
not found
{{> notfound}}
 =====================================
without extension first
{{> must2 }}
 =====================================
last with extension
{{> must3 }}
 =====================================
Ensure must3 didn\'t change specials

{{#person?}}
  Hi {{name}}!
{{/person?}}

%(%#person?%)%
  Hi %(%name%)%!
%(%/person?%)%';
        return 200 '{
  "name": "Chris",
  "value": 10000,
  "taxed_value": 6000,
  "in_ca": true,
  "person": false,
  "repo": [
    { "name": "resque", "who": [ { "commiter": "joe" }, { "reviewer": "avrel" }, { "commiter": "william" } ] },
    { "name": "hub", "who": [ { "commiter": "jack" }, { "reviewer": "avrel" }, { "commiter": "greg" } ]  },
    { "name": "rip", "who": [ { "reviewer": "joe" }, { "reviewer": "jack" }, { "commiter": "greg" } ]  }
  ],
  "person?": { "name": "Jon" },
  "special": "----{{extra}}----",
  "extra": 3.14159,
  "#sharp": "#",
  "!bang": "!",
  "/slash": "/",
  "^circ": "^",
  "=equal": "=",
  ":colon": ":",
  ">greater": ">",
  "~tilde": "~"
}';
    }
--- request
    GET /test
--- response_body eval
' =====================================
from json
----3.14159---- =====================================
not found
 =====================================
without extension first
must2 == BEGIN
Hello Chris
You have just won 10000 dollars!
Well, 6000 dollars, after taxes.
Shown.
  No person
must2 == END
 =====================================
last with extension
must3.mustache == BEGIN
  <b>resque</b> reviewers:  avrel  commiters: joe  william
  <b>hub</b> reviewers:  avrel  commiters: jack  greg
  <b>rip</b> reviewers: joe jack  commiters:   greg

  Hi Jon!

 =====================================
  <b>resque</b> reviewers:  avrel  commiters: joe  william
  <b>hub</b> reviewers:  avrel  commiters: jack  greg
  <b>rip</b> reviewers: joe jack  commiters:   greg
 =====================================
must3.mustache == END
 =====================================
Ensure must3 didn\'t change specials

  Hi Jon!

%(%#person?%)%
  Hi %(%name%)%!
%(%/person?%)%'
