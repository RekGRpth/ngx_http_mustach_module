#define JSMN_STATIC
#include "jsmn.h"

#include <ngx_config.h>
#include <ngx_core.h>

#include <mustach/mustach.h>
#include <mustach/mustach-wrap.h>
#include <mustach/mustach-helpers.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int mustach_build_jsmn(const char *template, size_t length, int flags, mustach_template_t **templ, char **err);
int mustach_apply_jsmn(mustach_template_t *templ, const char *json, size_t jsonlen, int flags, FILE *file, char **err, ngx_pool_t *pool);

struct frame {
    int container;   /* token index of the array being iterated, or -1 */
    int is_objiter;
    int index;
    int count;
    int value;        /* token index of the current value */
    int key;          /* token index of the current key (objiter only) */
};

struct expl {
    const char *json;
    jsmntok_t *tokens;
    ngx_pool_t *pool;
    int selection;    /* token index, or -1 for "no value" */
    int depth;
    struct frame stack[MUSTACH_MAX_DEPTH];
};

static int tok_len(jsmntok_t *t) { return t->end - t->start; }

static int tok_eq(struct expl *e, int idx, const char *name, size_t namelen) {
    jsmntok_t *t = &e->tokens[idx];
    return (size_t) tok_len(t) == namelen && !memcmp(e->json + t->start, name, namelen);
}

/* Skip past the whole subtree rooted at tokens[i], returning the index of
 * the token right after it. Relies on jsmn's convention that an object's
 * or array's `size` is its number of direct children (for an object, a
 * member key's own `size` is 1, standing for its value), and that a
 * subtree's tokens always immediately follow its own token in document
 * order -- the standard jsmn traversal idiom. */
static int skip(jsmntok_t *tokens, int i) {
    int end = i + 1, j, n = tokens[i].size;
    for (j = 0; j < n; j++)
        end = skip(tokens, end);
    return end;
}

static int find_member(struct expl *e, int container, const char *name, size_t namelen) {
    int idx = container + 1, j, n = e->tokens[container].size;
    for (j = 0; j < n; j++) {
        int key = idx, value = key + 1;
        if (tok_eq(e, key, name, namelen)) return value;
        idx = skip(e->tokens, value);
    }
    return -1;
}

static int nth_element(struct expl *e, int container, int n) {
    int idx = container + 1, j;
    for (j = 0; j < n; j++) idx = skip(e->tokens, idx);
    return idx;
}

static int is_zero_number(const char *s, int len) {
    int i;
    for (i = 0; i < len; i++)
        if (s[i] >= '1' && s[i] <= '9')
            return 0;
    return 1;
}

static int is_truthy(struct expl *e, int idx) {
    jsmntok_t *t;
    int len;
    const char *s;
    if (idx < 0) return 0;
    t = &e->tokens[idx];
    len = tok_len(t);
    s = e->json + t->start;
    switch (t->type) {
        case JSMN_OBJECT: case JSMN_ARRAY: return t->size > 0;
        case JSMN_STRING: return len > 0;
        case JSMN_PRIMITIVE:
            if (len == 4 && !memcmp(s, "true", 4)) return 1;
            if (len == 5 && !memcmp(s, "false", 5)) return 0;
            if (len == 4 && !memcmp(s, "null", 4)) return 0;
            return !is_zero_number(s, len);
        default: return 0;
    }
}

/* Decode a jsmn string token's JSON escapes into a NUL-less buffer.
 * Returns a pointer suitable for sbuf->value/length. The common
 * escape-free case is returned as a direct slice of the original json
 * buffer, no copy; otherwise the copy is allocated from `pool` -- no
 * caller-side free, `pool` is destroyed as a whole once rendering ends. */
static const char *decode_string(ngx_pool_t *pool, const char *json, jsmntok_t *t, size_t *outlen) {
    const char *s = json + t->start;
    int len = tok_len(t), i;
    char *out, *o;
    for (i = 0; i < len; i++)
        if (s[i] == '\\')
            break;
    if (i == len) {
        *outlen = (size_t) len;
        return s;
    }
    out = ngx_pnalloc(pool, (size_t) len ? (size_t) len : 1);
    if (!out) { *outlen = 0; return ""; }
    o = out;
    for (i = 0; i < len; i++) {
        if (s[i] != '\\' || i + 1 >= len) { *o++ = s[i]; continue; }
        i++;
        switch (s[i]) {
            case '"': *o++ = '"'; break;
            case '\\': *o++ = '\\'; break;
            case '/': *o++ = '/'; break;
            case 'b': *o++ = '\b'; break;
            case 'f': *o++ = '\f'; break;
            case 'n': *o++ = '\n'; break;
            case 'r': *o++ = '\r'; break;
            case 't': *o++ = '\t'; break;
            case 'u': {
                unsigned cp = 0;
                ngx_int_t hi, lo;
                if (i + 4 < len) {
                    hi = ngx_hextoi((u_char *) s + i + 1, 4);
                    cp = hi >= 0 ? (unsigned) hi : 0;
                    i += 4;
                    if (cp >= 0xd800 && cp <= 0xdbff && i + 6 < len && s[i + 1] == '\\' && s[i + 2] == 'u') {
                        lo = ngx_hextoi((u_char *) s + i + 3, 4);
                        if (lo >= 0xdc00 && lo <= 0xdfff) {
                            cp = 0x10000 + ((cp - 0xd800) << 10) + ((unsigned) lo - 0xdc00);
                            i += 6;
                        }
                    }
                }
                if (cp < 0x80) *o++ = (char) cp;
                else if (cp < 0x800) {
                    *o++ = (char) (0xC0 | (cp >> 6));
                    *o++ = (char) (0x80 | (cp & 0x3F));
                } else if (cp < 0x10000) {
                    *o++ = (char) (0xE0 | (cp >> 12));
                    *o++ = (char) (0x80 | ((cp >> 6) & 0x3F));
                    *o++ = (char) (0x80 | (cp & 0x3F));
                } else {
                    *o++ = (char) (0xF0 | (cp >> 18));
                    *o++ = (char) (0x80 | ((cp >> 12) & 0x3F));
                    *o++ = (char) (0x80 | ((cp >> 6) & 0x3F));
                    *o++ = (char) (0x80 | (cp & 0x3F));
                }
                break;
            }
            default: *o++ = s[i]; break;
        }
    }
    *outlen = (size_t) (o - out);
    return out;
}

static int start(void *closure) {
    struct expl *e = closure;
    e->depth = 0;
    e->stack[0].value = 0; /* token 0 is always the root */
    e->selection = 0;
    return MUSTACH_OK;
}

static int compare(void *closure, const char *value) {
    struct expl *e = closure;
    jsmntok_t *t;
    const char *s;
    size_t slen;
    int c;
    size_t vlen, minlen;
    if (e->selection < 0) return strcmp("", value);
    t = &e->tokens[e->selection];
    switch (t->type) {
        case JSMN_PRIMITIVE:
            s = e->json + t->start;
            if (tok_len(t) == 4 && !memcmp(s, "true", 4)) return strcmp("true", value);
            if (tok_len(t) == 5 && !memcmp(s, "false", 5)) return strcmp("false", value);
            if (tok_len(t) == 4 && !memcmp(s, "null", 4)) return strcmp("null", value);
            { double d = atof(s) - atof(value); return d < 0 ? -1 : d > 0 ? 1 : 0; }
        case JSMN_STRING:
            s = decode_string(e->pool, e->json, t, &slen);
            vlen = strlen(value);
            minlen = slen < vlen ? slen : vlen;
            c = minlen ? memcmp(s, value, minlen) : 0;
            if (c == 0) c = (int) slen - (int) vlen;
            return c < 0 ? -1 : c > 0 ? 1 : 0;
        default:
            return 1;
    }
}

static int sel(void *closure, const char *name) {
    struct expl *e = closure;
    int i, r = 0, o = -1;
    size_t namelen;
    if (name == NULL) {
        o = e->stack[e->depth].value;
        r = 1;
    } else {
        namelen = strlen(name);
        for (i = e->depth; i >= 0 && !r; i--) {
            int cur = e->stack[i].value;
            if (cur >= 0 && e->tokens[cur].type == JSMN_OBJECT) {
                o = find_member(e, cur, name, namelen);
                r = o >= 0;
            }
        }
    }
    e->selection = o;
    return r;
}

static int subsel(void *closure, const char *name) {
    struct expl *e = closure;
    jsmntok_t *t;
    int o = -1, r = 0;
    if (e->selection >= 0) {
        t = &e->tokens[e->selection];
        if (t->type == JSMN_OBJECT) {
            o = find_member(e, e->selection, name, strlen(name));
            r = o >= 0;
        } else if (t->type == JSMN_ARRAY && *name) {
            char *end;
            long idx = strtol(name, &end, 10);
            if (!*end && idx >= 0 && idx < t->size) {
                o = nth_element(e, e->selection, (int) idx);
                r = 1;
            }
        }
    }
    if (r) e->selection = o;
    return r;
}

static int enter(void *closure, int objiter) {
    struct expl *e = closure;
    int o = e->selection;
    struct frame *f;
    if (++e->depth >= MUSTACH_MAX_DEPTH) return MUSTACH_ERROR_TOO_DEEP;
    f = &e->stack[e->depth];
    f->is_objiter = 0;
    f->container = -1;
    if (objiter) {
        if (o < 0 || e->tokens[o].type != JSMN_OBJECT || e->tokens[o].size == 0) goto not_entering;
        f->is_objiter = 1;
        f->container = o;
        f->index = 0;
        f->count = e->tokens[o].size;
        f->key = o + 1;
        f->value = f->key + 1;
    } else if (o >= 0 && e->tokens[o].type == JSMN_ARRAY) {
        if (e->tokens[o].size == 0) goto not_entering;
        f->container = o;
        f->index = 0;
        f->count = e->tokens[o].size;
        f->value = o + 1;
    } else if (is_truthy(e, o)) {
        f->value = o;
    } else
        goto not_entering;
    return 1;
not_entering:
    e->depth--;
    return 0;
}

static int next(void *closure) {
    struct expl *e = closure;
    struct frame *f;
    if (e->depth <= 0) return MUSTACH_ERROR_CLOSING;
    f = &e->stack[e->depth];
    if (f->is_objiter) {
        int nk = skip(e->tokens, f->value);
        if (++f->index >= f->count) return 0;
        f->key = nk;
        f->value = nk + 1;
        return 1;
    }
    if (f->container >= 0) {
        int ne = skip(e->tokens, f->value);
        if (++f->index >= f->count) return 0;
        f->value = ne;
        return 1;
    }
    return 0;
}

static int leave(void *closure) {
    struct expl *e = closure;
    if (e->depth <= 0) return MUSTACH_ERROR_CLOSING;
    e->depth--;
    return 0;
}

static int get(void *closure, struct mustach_sbuf *sbuf, int key) {
    struct expl *e = closure;
    jsmntok_t *t;
    const char *s;
    size_t slen;
    if (key) {
        int d, k = -1;
        for (d = e->depth; d >= 0; d--)
            if (e->stack[d].is_objiter) { k = e->stack[d].key; break; }
        if (k >= 0) {
            s = decode_string(e->pool, e->json, &e->tokens[k], &slen);
            sbuf->value = s;
            sbuf->length = slen;
        } else {
            sbuf->value = "";
            sbuf->length = 0;
        }
        return 1;
    }
    if (e->selection < 0) {
        sbuf->value = "";
        sbuf->length = 0;
        return 1;
    }
    t = &e->tokens[e->selection];
    switch (t->type) {
        case JSMN_STRING:
            s = decode_string(e->pool, e->json, t, &slen);
            sbuf->value = s;
            sbuf->length = slen;
            break;
        case JSMN_PRIMITIVE:
            if (tok_len(t) == 4 && !memcmp(e->json + t->start, "null", 4)) {
                sbuf->value = "";
                sbuf->length = 0;
                break;
            }
            /* fall through */
        case JSMN_OBJECT:
        case JSMN_ARRAY:
            sbuf->value = e->json + t->start;
            sbuf->length = (size_t) tok_len(t);
            break;
        default:
            sbuf->value = "";
            sbuf->length = 0;
            break;
    }
    return 1;
}

static const struct mustach_wrap_itf mustach_jsmn_wrap_itf = {
    .start = start,
    .stop = NULL,
    .compare = compare,
    .sel = sel,
    .subsel = subsel,
    .enter = enter,
    .next = next,
    .leave = leave,
    .get = get
};

/* Parses (compiles) a mustache template into a reusable mustach_template_t.
 * The returned template holds slices into `template`/`length`, so that
 * buffer must outlive it -- no copy is made here. Only the two build-time
 * flags (colon, emptytag) affect the compiled tree; the rest of `flags`
 * is applied per-render by mustach_apply_jsmn(). */
int mustach_build_jsmn(const char *template, size_t length, int flags, mustach_template_t **templ, char **err) {
    mustach_sbuf_t sbuf = { .value = template, .length = length };
    int bflags = 0, rc;
    if (flags & Mustach_With_Colon) bflags |= Mustach_Build_With_Colon;
    if (flags & Mustach_With_EmptyTag) bflags |= Mustach_Build_With_EmptyTag;
    rc = mustach_make_template(templ, bflags, &sbuf, NULL);
    if (rc != MUSTACH_OK) *err = "invalid mustache template";
    return rc;
}

/* Renders an already-compiled template against JSON data. Can be called
 * repeatedly against the same `templ` for different JSON payloads. */
int mustach_apply_jsmn(mustach_template_t *templ, const char *json, size_t jsonlen, int flags, FILE *file, char **err, ngx_pool_t *pool) {
    jsmn_parser p;
    jsmntok_t *tokens;
    int ntok, rc;
    struct expl e;

    if (!jsonlen) { json = "{}"; jsonlen = 2; }

    jsmn_init(&p);
    ntok = jsmn_parse(&p, json, jsonlen, NULL, 0);
    if (ntok < 0) { *err = "invalid json"; fclose(file); return MUSTACH_ERROR_USER(1); }
    if (!(tokens = ngx_palloc(pool, (size_t) (ntok ? ntok : 1) * sizeof(*tokens)))) { fclose(file); return MUSTACH_ERROR_SYSTEM; }

    jsmn_init(&p);
    if (jsmn_parse(&p, json, jsonlen, tokens, (unsigned) ntok) < 0) { *err = "invalid json"; fclose(file); return MUSTACH_ERROR_USER(1); }

    e.json = json;
    e.tokens = tokens;
    e.pool = pool;
    rc = mustach_wrap_apply(templ, &mustach_jsmn_wrap_itf, &e, flags, mustach_fwrite_cb, NULL, file);
    fclose(file);
    return rc;
}
