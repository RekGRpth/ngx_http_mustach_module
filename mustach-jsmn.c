#define JSMN_STATIC
#define JSMN_PARENT_LINKS
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
int mustach_apply_jsmn(mustach_template_t *templ, const char *json, size_t jsonlen, int flags, FILE *file, char **err, ngx_pool_t *pool, const ngx_str_t *partials, size_t max_output, size_t partials_limit);

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
    int *after;       /* after[i]: index of the token right after tokens[i]'s subtree */
    int **index;      /* index[i]: member_index() of object tokens[i], built on first
                       * lookup; NULL as a whole when no object is big enough */
    ngx_pool_t *pool;
    int selection;    /* token index, or -1 for "no value" */
    int depth;
    int nested;       /* a get_partial() lookup: keep the caller's context */
    int flags;
    const ngx_str_t *partials; /* mustach_partials_root, or NULL */
    const char *too_big;       /* name of a data partial over DATA_PARTIAL_MAX */
    size_t partials_left;      /* mustach_data_partials_limit budget left, */
    int partials_limited;      /* when there is one */
    struct frame stack[MUSTACH_MAX_DEPTH];
};

static int tok_len(jsmntok_t *t) { return t->end - t->start; }

static int tok_eq(struct expl *e, int idx, const char *name, size_t namelen) {
    jsmntok_t *t = &e->tokens[idx];
    return (size_t) tok_len(t) == namelen && !memcmp(e->json + t->start, name, namelen);
}

/* Skip past the whole subtree rooted at tokens[i], returning the index of
 * the token right after it. O(1): precomputed by index_tree(), so neither
 * deep nesting (recursion) nor repeated lookups over big subtrees cost more. */
static int skip(struct expl *e, int i) {
    return e->after[i];
}

/* Objects with more members than this get a hash index on their first
 * lookup: below it, a linear scan is as fast and needs no memory. Without
 * it, a loop over a big array looking up a name in a big enclosing object
 * is quadratic -- 27s for one 840KB body. */
#define MEMBER_INDEX_MIN 8

static uint32_t key_hash(const char *s, size_t len) {
    uint32_t h = 2166136261u; /* FNV-1a */
    while (len--) { h ^= (u_char) *s++; h *= 16777619u; }
    return h;
}

/* Open addressing over the object's key tokens, -1 for an empty slot.
 * Keys compare by their raw JSON text, as tok_eq() does, and on duplicates
 * the first one wins, as in the linear scan. */
static int *member_index(struct expl *e, int container, unsigned *pmask) {
    int n = e->tokens[container].size, i, key, *tab;
    unsigned cap, h;
    jsmntok_t *t;
    for (cap = 16; cap < 2 * (unsigned) n; cap <<= 1);
    *pmask = cap - 1;
    if ((tab = e->index[container])) return tab;
    if (!(tab = ngx_palloc(e->pool, cap * sizeof(*tab)))) return NULL;
    ngx_memset(tab, 0xff, cap * sizeof(*tab));
    for (i = 0, key = container + 1; i < n; i++, key = skip(e, key + 1)) {
        t = &e->tokens[key];
        for (h = key_hash(e->json + t->start, (size_t) tok_len(t)) & (cap - 1); tab[h] >= 0; h = (h + 1) & (cap - 1))
            if (tok_eq(e, tab[h], e->json + t->start, (size_t) tok_len(t))) break;
        if (tab[h] < 0) tab[h] = key;
    }
    e->index[container] = tab;
    return tab;
}

static int find_member(struct expl *e, int container, const char *name, size_t namelen) {
    int idx = container + 1, j, n = e->tokens[container].size, *tab;
    unsigned mask, h;
    if (n > MEMBER_INDEX_MIN && e->index && (tab = member_index(e, container, &mask))) {
        for (h = key_hash(name, namelen) & mask; tab[h] >= 0; h = (h + 1) & mask)
            if (tok_eq(e, tab[h], name, namelen)) return tab[h] + 1;
        return -1;
    }
    for (j = 0; j < n; j++) {
        int key = idx, value = key + 1;
        if (tok_eq(e, key, name, namelen)) return value;
        idx = skip(e, value);
    }
    return -1;
}

static int nth_element(struct expl *e, int container, int n) {
    int idx = container + 1, j;
    for (j = 0; j < n; j++) idx = skip(e, idx);
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
    /* mustach takes a zero length to mean "NUL-terminated, measure it": a
     * slice of the JSON for "" would print the rest of the document, and
     * run past the end of the buffer looking for that NUL */
    if (!len) { *outlen = 0; return ""; }
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
    if (e->nested) return MUSTACH_OK;
    e->depth = 0;
    /* the root frame: not an iteration -- get() walks the frames down to it
     * looking for an objiter key, as for {{*}} outside {{#x.*}} */
    e->stack[0].container = -1;
    e->stack[0].is_objiter = 0;
    e->stack[0].index = 0;
    e->stack[0].count = 0;
    e->stack[0].key = -1;
    e->stack[0].value = 0; /* token 0 is always the root */
    e->selection = 0;
    return MUSTACH_OK;
}

/* atof() needs a NUL-terminated string, and a primitive token isn't one: it
 * runs on into whatever follows, past the end of the buffer when the whole
 * JSON is a bare number. */
static double tok_number(struct expl *e, jsmntok_t *t) {
    char buf[64], *s = buf;
    int len = tok_len(t);
    if ((size_t) len >= sizeof(buf) && !(s = ngx_pnalloc(e->pool, (size_t) len + 1))) return 0;
    ngx_memcpy(s, e->json + t->start, (size_t) len);
    s[len] = '\0';
    return atof(s);
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
            { double d = tok_number(e, t) - atof(value); return d < 0 ? -1 : d > 0 ? 1 : 0; }
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
        int nk = skip(e, f->value);
        if (++f->index >= f->count) return 0;
        f->key = nk;
        f->value = nk + 1;
        return 1;
    }
    if (f->container >= 0) {
        int ne = skip(e, f->value);
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

/* The render in progress, for get_partial(): mustach_wrap_get_partial is a
 * global hook and gets no closure. Workers render one request at a time. */
static struct expl *partial_expl;

/* A partial from the data is a template the JSON supplies, and libmustach
 * copies each tag name it looks up into a stack buffer of that name's size:
 * a multi-megabyte name overflows the worker's stack. Its tag names can't be
 * longer than the partial itself, so capping the partial bounds them. */
#define DATA_PARTIAL_MAX (64 * 1024)
#define MUSTACH_ERROR_PARTIAL_TOO_BIG MUSTACH_ERROR_USER(3)

/* Every partial taken from the data costs work and request-pool memory
 * whether or not it outputs anything, so each lookup is charged against a
 * per-render budget: its length, and at least DATA_PARTIAL_COST. */
#define DATA_PARTIAL_COST 64
#define MUSTACH_ERROR_PARTIALS_LIMIT MUSTACH_ERROR_USER(4)

static int charge_partial(struct expl *e, size_t cost) {
    if (!e->partials_limited) return MUSTACH_OK;
    if (cost > e->partials_left) return MUSTACH_ERROR_PARTIALS_LIMIT;
    e->partials_left -= cost;
    return MUSTACH_OK;
}

/* Looks `name` up in the JSON data the way mustach-wrap itself does, by
 * rendering {{&name}} against the current context, so names resolve as they
 * always did: dots, JSON pointers, objiter keys. Returns 1 with the value in
 * `sbuf` when it's not empty, 0 otherwise -- a missing name and an empty
 * string can't be told apart this way. */
static int partial_from_data(struct expl *e, const char *name, struct mustach_sbuf *sbuf) {
    struct expl nested;
    mustach_template_t *templ;
    mustach_sbuf_t text = MUSTACH_SBUF_INIT;
    char *tpl, *out = NULL, *copy;
    size_t outlen = 0;
    FILE *file;
    int rc;
    if ((rc = charge_partial(e, DATA_PARTIAL_COST)) != MUSTACH_OK) return rc;
    /* delimiters that can't clash with the name */
    if (strchr(name, '\x01') || strchr(name, '\x02')) return 0;
    if (!(tpl = ngx_pnalloc(e->pool, strlen(name) + sizeof("{{=\x01 \x02=}}\x01&\x02") - 1))) return MUSTACH_ERROR_SYSTEM;
    text.value = tpl;
    text.length = (size_t) (ngx_sprintf((u_char *) tpl, "{{=\x01 \x02=}}\x01&%s\x02", name) - (u_char *) tpl);
    if (mustach_make_template(&templ, 0, &text, NULL) != MUSTACH_OK) return 0;
    if (!(file = open_memstream(&out, &outlen))) { mustach_destroy_template(templ, NULL, NULL); return MUSTACH_ERROR_SYSTEM; }
    nested = *e;
    nested.nested = 1;
    rc = mustach_wrap_apply(templ, &mustach_jsmn_wrap_itf, &nested, e->flags & ~Mustach_With_ErrorUndefined, mustach_fwrite_cb, NULL, file);
    fclose(file);
    mustach_destroy_template(templ, NULL, NULL);
    if (rc != MUSTACH_OK) { free(out); return MUSTACH_ERROR_SYSTEM; }
    if (!outlen) { free(out); return 0; }
    if (outlen > DATA_PARTIAL_MAX) {
        free(out);
        if ((copy = ngx_pnalloc(e->pool, strlen(name) + 1))) e->too_big = strcpy(copy, name);
        return MUSTACH_ERROR_PARTIAL_TOO_BIG;
    }
    if (outlen > DATA_PARTIAL_COST && (rc = charge_partial(e, outlen - DATA_PARTIAL_COST)) != MUSTACH_OK) { free(out); return rc; }
    if (!(copy = ngx_pnalloc(e->pool, outlen))) { free(out); return MUSTACH_ERROR_SYSTEM; }
    ngx_memcpy(copy, out, outlen);
    free(out);
    sbuf->value = copy;
    sbuf->length = outlen;
    return 1;
}

/* Reads `name`, then `name`.mustache, from the mustach_partials_root
 * directory, as mustach-wrap would from the working directory. `name` must
 * be a single path component, so nothing outside that directory can be
 * reached. Returns 1 with the contents in `sbuf`, 0 if there's no such
 * file. */
static int partial_from_file(struct expl *e, const char *name, struct mustach_sbuf *sbuf) {
    size_t namelen = strlen(name);
    ngx_file_info_t fi;
    ngx_fd_t fd;
    u_char *path, *p, *buf;
    size_t size, got;
    ssize_t n;
    int i;
    if (!e->partials || !namelen || strchr(name, '/') || !strcmp(name, ".") || !strcmp(name, "..")) return 0;
    if (!(path = ngx_pnalloc(e->pool, e->partials->len + 1 + namelen + sizeof(".mustache")))) return MUSTACH_ERROR_SYSTEM;
    p = ngx_sprintf(path, "%V/%s", e->partials, name);
    for (i = 0; i < 2; i++) {
        if (i) p = ngx_cpymem(p, ".mustache", sizeof(".mustache") - 1);
        *p = '\0';
        if ((fd = ngx_open_file(path, NGX_FILE_RDONLY, NGX_FILE_OPEN, 0)) == NGX_INVALID_FILE) continue;
        if (ngx_fd_info(fd, &fi) == NGX_FILE_ERROR || !ngx_is_file(&fi)) { ngx_close_file(fd); continue; }
        size = (size_t) ngx_file_size(&fi);
        if (!(buf = ngx_pnalloc(e->pool, size ? size : 1))) { ngx_close_file(fd); return MUSTACH_ERROR_SYSTEM; }
        for (got = 0; got < size; got += (size_t) n)
            if ((n = ngx_read_fd(fd, buf + got, size - got)) <= 0) break;
        ngx_close_file(fd);
        if (got != size) return MUSTACH_ERROR_SYSTEM;
        sbuf->value = size ? (const char *) buf : "";
        sbuf->length = size;
        return 1;
    }
    return 0;
}

/* The render in progress, for get_partial(): mustach_wrap_get_partial is a
 * global hook and gets no closure. Workers render one request at a time. */
static struct expl *partial_expl;

/* Left to itself, mustach-wrap reads a partial it doesn't find in the data
 * from `name` (then `name`.mustache) as a file path, relative to the working
 * directory or absolute. And since a partial taken from the data is itself a
 * template, the JSON alone could pull any file the worker can read into the
 * response. This global hook runs before that, and never answering "not
 * found" keeps the library from ever getting there: partials come from the
 * data and, only when mustach_partials_root is set, from that directory --
 * in the order Mustach_With_PartialDataFirst asks for. */
static int get_partial(const char *name, struct mustach_sbuf *sbuf) {
    struct expl *e = partial_expl;
    int rc;
    sbuf->value = "";
    sbuf->length = 0;
    if (!e) return MUSTACH_OK;
    if (e->flags & Mustach_With_PartialDataFirst) {
        if (!(rc = partial_from_data(e, name, sbuf))) rc = partial_from_file(e, name, sbuf);
    } else {
        if (!(rc = partial_from_file(e, name, sbuf))) rc = partial_from_data(e, name, sbuf);
    }
    return rc < 0 ? rc : MUSTACH_OK;
}

/* jsmn, strict or not, accepts object members without exactly one value --
 * {"a"}, {"a":}, {"a" "b"}, {"a":1 "b":2} -- while find_member() and objiter
 * take a member's value to be the token right after its key, and so walk off
 * the end of `tokens` on such input. Reject it up front: one linear pass in
 * document order with an explicit stack, no recursion. The same pass fills
 * in `after` for skip(). */
static int index_tree(ngx_pool_t *pool, jsmntok_t *tokens, int ntok, int **pafter, int *pbig) {
    struct { int tok, left; } *stack;
    int top = 0, i, *after;
    if (!(after = ngx_palloc(pool, (size_t) ntok * sizeof(*after)))) return MUSTACH_ERROR_SYSTEM;
    *pafter = after;
    *pbig = tokens[0].type == JSMN_OBJECT && tokens[0].size > MEMBER_INDEX_MIN;
    if (!tokens[0].size) { after[0] = 1; return MUSTACH_OK; }
    if (!(stack = ngx_palloc(pool, (size_t) ntok * sizeof(*stack)))) return MUSTACH_ERROR_SYSTEM;
    stack[top].tok = 0;
    stack[top++].left = tokens[0].size;
    for (i = 1; top; i++) {
        if (i >= ntok) return MUSTACH_ERROR_USER(1);
        if (tokens[stack[top - 1].tok].type == JSMN_OBJECT && tokens[i].size != 1) return MUSTACH_ERROR_USER(1);
        stack[top - 1].left--;
        if (tokens[i].size) {
            if (tokens[i].type == JSMN_OBJECT && tokens[i].size > MEMBER_INDEX_MIN) *pbig = 1;
            stack[top].tok = i;
            stack[top++].left = tokens[i].size;
        } else after[i] = i + 1;
        while (top && !stack[top - 1].left) after[stack[--top].tok] = i + 1;
    }
    return MUSTACH_OK;
}

/* The rendered output goes through here: rendering stops with an error once
 * it outgrows mustach_max_output_size, rather than filling the worker's
 * memory -- partials taken from the data are templates too, so a small JSON
 * can otherwise expand into an arbitrarily large page. */
struct output {
    FILE *file;
    size_t left;      /* bytes still allowed, when `limited` */
    int limited;
};

#define MUSTACH_ERROR_OUTPUT_TOO_BIG MUSTACH_ERROR_USER(2)

static int write_output(void *closure, const char *buffer, size_t size) {
    struct output *o = closure;
    if (o->limited) {
        if (size > o->left) return MUSTACH_ERROR_OUTPUT_TOO_BIG;
        o->left -= size;
    }
    return mustach_fwrite_cb(o->file, buffer, size);
}

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
int mustach_apply_jsmn(mustach_template_t *templ, const char *json, size_t jsonlen, int flags, FILE *file, char **err, ngx_pool_t *pool, const ngx_str_t *partials, size_t max_output, size_t partials_limit) {
    jsmn_parser p;
    jsmntok_t *tokens;
    int ntok, rc, big;
    struct expl e;

    jsmn_init(&p);
    ntok = jsmn_parse(&p, json, jsonlen, NULL, 0);
    if (ntok < 0) { *err = "invalid json"; fclose(file); return MUSTACH_ERROR_USER(1); }
    /* empty or whitespace-only: render against {} rather than read a tokens[0]
     * that jsmn never filled in */
    if (!ntok) { json = "{}"; jsonlen = 2; ntok = 1; }
    if (!(tokens = ngx_palloc(pool, (size_t) ntok * sizeof(*tokens)))) { fclose(file); return MUSTACH_ERROR_SYSTEM; }

    jsmn_init(&p);
    if (jsmn_parse(&p, json, jsonlen, tokens, (unsigned) ntok) < 0) { *err = "invalid json"; fclose(file); return MUSTACH_ERROR_USER(1); }
    if ((rc = index_tree(pool, tokens, ntok, &e.after, &big)) != MUSTACH_OK) { if (rc != MUSTACH_ERROR_SYSTEM) *err = "invalid json"; fclose(file); return rc; }

    e.json = json;
    e.tokens = tokens;
    e.pool = pool;
    /* shared with partial lookups' copies of `e`; without it, a linear scan */
    e.index = big ? ngx_pcalloc(pool, (size_t) ntok * sizeof(*e.index)) : NULL;
    e.nested = 0;
    e.flags = flags;
    e.partials = partials;
    e.too_big = NULL;
    e.partials_left = partials_limit;
    e.partials_limited = partials_limit != 0;
    mustach_wrap_get_partial = get_partial;
    partial_expl = &e;
    struct output o = { .file = file, .left = max_output, .limited = max_output != 0 };
    rc = mustach_wrap_apply(templ, &mustach_jsmn_wrap_itf, &e, flags, write_output, NULL, &o);
    partial_expl = NULL;
    if (rc == MUSTACH_ERROR_OUTPUT_TOO_BIG) *err = "rendered output is larger than mustach_max_output_size";
    if (rc == MUSTACH_ERROR_PARTIALS_LIMIT) *err = "partials from the data exceed mustach_data_partials_limit";
    if (rc == MUSTACH_ERROR_PARTIAL_TOO_BIG) {
        char *msg = e.too_big ? ngx_pnalloc(pool, strlen(e.too_big) + sizeof("partial \"\" from the data is larger than 64k")) : NULL;
        if (msg) *ngx_sprintf((u_char *) msg, "partial \"%s\" from the data is larger than 64k", e.too_big) = '\0';
        *err = msg ? msg : "a partial from the data is larger than 64k";
    }
    fclose(file);
    return rc;
}
