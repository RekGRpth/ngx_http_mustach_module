# ngx_http_mustach_module

An nginx module that renders [Mustache](https://mustache.github.io/) templates against JSON data, using the [mustach](https://gitlab.com/jobol/mustach) C library.

It can work two ways:

- **As a content handler** — a location renders a template against JSON coming from an nginx variable (`mustach_json`) and returns the result directly. No upstream/backend needed.
- **As a body filter** — a location's response is produced by something else (`proxy_pass`, `return`, a static file, ...); if that response comes back with `Content-Type: application/json`, this module buffers it, treats it as the data, and rewrites the body by rendering `mustach_template` against it.

## Directives

### mustach_template

- **syntax:** `mustach_template <text>;`
- **context:** `http`, `server`, `location`, `if in location`
- Sets the Mustache template. Required for both modes — it's what actually turns the module on (installing the body filter for the whole `http` block once any location uses it). The value is an [nginx complex value](https://nginx.org/en/docs/dev/development_guide.html#http_variables) and can reference variables, e.g. `mustach_template $tmpl;`.
- Inherited by nested locations unless overridden.

### mustach_json

- **syntax:** `mustach_json <text>;`
- **context:** `http`, `server`, `location`, `if in location`
- Sets the JSON data and switches the location into **content-handler mode**: this directive installs itself as the location's content handler, so the location no longer needs (or should have) another one like `proxy_pass` or `return`. Requires `mustach_template` to be set in the same location — the module refuses to start otherwise, rather than crashing on the first request.
- Combining `mustach_json` with another directive that already claims the location's content handler (`proxy_pass`, `return`, ...) is a configuration error, whichever of the two is declared second.
- Inherited by nested locations unless overridden.

### mustach_content

- **syntax:** `mustach_content <text>;`
- **context:** `http`, `server`, `location`, `if in location`
- Overrides the `Content-Type` of the rendered response (e.g. `mustach_content text/html;`). Without it, the usual nginx `Content-Type` resolution applies (MIME type by extension, then `default_type`).
- Inherited by nested locations unless overridden.

### mustach_type

- **syntax:** `mustach_type cjson | jansson | json-c | jsmn;`
- **default:** `jsmn`
- **context:** `http`, `server`, `location`, `if in location`
- Selects the JSON backend used to parse the data and drive the template.
  - `jsmn` — vendored header-only tokenizer ([jsmn.h](jsmn.h)), no external library dependency, no risk of the symbol clashes described below.
  - `json-c`, `cjson`, `jansson` — bind to the system `libjson-c`/`libcjson`/`libjansson`.
- `jansson` is only safe to use if `libmustach` was **not** also linked against `json-c` in the same shared object: `json-c`'s `json_object_get(obj)` (refcount increment) and `jansson`'s own `json_object_get(obj, key)` (field lookup) share a symbol name, and if both libraries end up in one `.so`, the dynamic linker resolves every call to one of them process-wide — silently breaking whichever one loses, regardless of which backend a given request actually asked for. Check `mustach_type jansson` actually resolves a nested field (not the whole document) before relying on it in a build where `libmustach` bundles more than one JSON backend.
- Inherited by nested locations unless overridden.

### mustach_flags

- **syntax:** `mustach_flags flag ...;`
- **default:** all extensions enabled
- **context:** `http`, `server`, `location`, `if in location`
- Selects which [mustach extensions](https://gitlab.com/jobol/mustach) are active, as a space-separated list of: `allextensions`, `colon`, `compare`, `emptytag`, `equal`, `errorundefined`, `escfirstcmp`, `incpartial`, `jsonpointer`, `noextensions`, `objectiter`, `partialdatafirst`, `singledot`.
- Can only be given once per location (a second `mustach_flags` in the same location is a configuration error); inherited by nested locations that don't set their own.

## Examples

### Content-handler mode

```nginx
location /hello {
    mustach_template "Hello, {{name}}!";
    mustach_content  text/plain;
    mustach_json     '{"name":"World"}';
}
```

Typically the JSON comes from a variable instead of a literal, e.g. built with `set`/`ngx_http_evaluate_module`/the request body:

```nginx
location /hello {
    mustach_template "Hello, {{name}}!";
    mustach_content  text/plain;
    mustach_json     $arg_name_as_json;
}
```

### Body-filter mode

```nginx
location /api/ {
    mustach_template '<h1>{{title}}</h1>';
    mustach_content  text/html;
    proxy_pass       http://backend;
}
```

Whatever `backend` returns is only rewritten if it comes back as `application/json` (optionally followed by `;` or a space, e.g. `application/json; charset=utf-8`) — any other `Content-Type` passes through untouched.

## Building

Add it with `--add-module=path/to/ngx_http_mustach_module` (static) or `--add-dynamic-module=path/to/ngx_http_mustach_module` (dynamic) to nginx's `configure`.

The build always requires [libmustach](https://gitlab.com/jobol/mustach) itself. The `json-c`/`cjson`/`jansson` backends each detect their library's headers (`json-c`, `libcjson`, `libjansson`) at compile time and fall back to a stub that errors out at request time if the corresponding header isn't found, so the module still builds without any of them installed — only `mustach_type` values backed by a missing library become unusable. `jsmn` needs nothing beyond what's vendored in this repository ([jsmn.h](jsmn.h)) and is unaffected either way.

## Testing

The test suite uses [Test::Nginx](https://metacpan.org/pod/Test::Nginx::Socket):

```sh
prove -r t/
```
