#include <nginx.h>
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <mustach/mustach-json-c.h>

typedef struct {
    ngx_buf_t *buf;
} ngx_http_mustach_context_t;

typedef struct {
    ngx_http_complex_value_t *json;
    ngx_http_complex_value_t *template;
} ngx_http_mustach_location_conf_t;

ngx_module_t ngx_http_mustach_module;

static void ngx_http_mustach_handler_internal(ngx_http_request_t *r) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_mustach_location_conf_t *location_conf = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    ngx_str_t json;
    if (ngx_http_complex_value(r, location_conf->json, &json) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return; }
    u_char *jsonc = ngx_pnalloc(r->pool, json.len + 1);
    if (!jsonc) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pnalloc"); return; }
    (void) ngx_cpystrn(jsonc, json.data, json.len + 1);
    ngx_str_t template;
    if (ngx_http_complex_value(r, location_conf->template, &template) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return; }
    u_char *templatec = ngx_pnalloc(r->pool, template.len + 1);
    if (!templatec) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pnalloc"); return; }
    (void) ngx_cpystrn(templatec, template.data, template.len + 1);
    struct json_object *object = json_tokener_parse(jsonc);
    if (!object) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!json_tokener_parse"); return; }
    ngx_str_t output = ngx_null_string;
    FILE *out = open_memstream((char **)&output.data, &output.len);
    if (!out) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!open_memstream"); goto json_object_put; }
    if (fmustach_json_c(templatec, object, out)) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "fmustach_json_c"); goto free; }
    fclose(out);
    if (!output.len) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!output.len"); goto free; }
    ngx_buf_t *buf = ngx_create_temp_buf(r->pool, output.len);
    if (!buf) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_create_temp_buf"); goto free; }
    buf->memory = 1;
    buf->last = ngx_copy(buf->last, output.data, output.len);
    if (buf->last != buf->end) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "buf->last != buf->end"); goto free; }
    buf->last_buf = (r == r->main) ? 1 : 0;
    buf->last_in_chain = 1;
    ngx_http_mustach_context_t *context = ngx_http_get_module_ctx(r, ngx_http_mustach_module);
    context->buf = buf;
free:
    free(output.data);
json_object_put:
    json_object_put(object);
}

static void ngx_http_mustach_task_handler(void *data, ngx_log_t *log) {
    ngx_http_request_t *r = data;
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_mustach_handler_internal(r);
}

static ngx_int_t ngx_http_mustach_handler_internal2(ngx_http_request_t *r) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_int_t rc = NGX_HTTP_INTERNAL_SERVER_ERROR;
    ngx_http_mustach_context_t *context = ngx_http_get_module_ctx(r, ngx_http_mustach_module);
    if (!context->buf) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!context->buf"); return rc; }
    ngx_chain_t *chain = ngx_alloc_chain_link(r->pool);
    if (!chain) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_alloc_chain_link"); return rc; }
    chain->buf = context->buf;
    chain->next = NULL;
    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = context->buf->end - context->buf->pos;
    rc = ngx_http_send_header(r);
    ngx_http_weak_etag(r);
    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only); else rc = ngx_http_output_filter(r, chain);
    return rc;
}

static void ngx_http_mustach_event_handler(ngx_event_t *ev) {
    ngx_http_request_t *r = ev->data;
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_finalize_request(r, ngx_http_mustach_handler_internal2(r));
}

static ngx_int_t ngx_http_mustach_handler(ngx_http_request_t *r) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    if (!(r->method & (NGX_HTTP_GET|NGX_HTTP_HEAD))) return NGX_HTTP_NOT_ALLOWED;
    ngx_int_t rc = ngx_http_discard_request_body(r);
    if (rc != NGX_OK && rc != NGX_AGAIN) return rc;
    ngx_http_mustach_context_t *context = ngx_pcalloc(r->pool, sizeof(ngx_http_mustach_context_t));
    ngx_http_set_ctx(r, context, ngx_http_mustach_module);
    ngx_http_core_loc_conf_t *core_loc_conf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    if (core_loc_conf->thread_pool) {
        ngx_thread_task_t *task = ngx_thread_task_alloc(r->pool, 0);
        if (!task) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_thread_task_alloc"); return NGX_ERROR; }
        task->handler = ngx_http_mustach_task_handler;
        task->ctx = r;
        task->event.handler = ngx_http_mustach_event_handler;
        task->event.data = r;
        if (ngx_thread_task_post(core_loc_conf->thread_pool, task) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_thread_task_post != NGX_OK"); return NGX_ERROR; }
        r->main->count++;
        return NGX_OK;
    }
    ngx_http_mustach_handler_internal(r);
    return ngx_http_mustach_handler_internal2(r);
}

static char *ngx_http_mustach_conf(ngx_conf_t *cf, ngx_command_t *cmd, void *conf) {
    ngx_http_core_loc_conf_t *clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_mustach_handler;
    return NGX_CONF_OK;
}

static ngx_command_t ngx_http_mustach_commands[] = {
  { .name = ngx_string("mustach"),
    .type = NGX_HTTP_LOC_CONF|NGX_CONF_NOARGS,
    .set = ngx_http_mustach_conf,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = 0,
    .post = NULL },
  { .name = ngx_string("mustach_json"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_conf_t, json),
    .post = NULL },
  { .name = ngx_string("mustach_template"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_conf_t, template),
    .post = NULL },
    ngx_null_command
};

static void *ngx_http_mustach_create_loc_conf(ngx_conf_t *cf) {
    ngx_http_mustach_location_conf_t *location_conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_mustach_location_conf_t));
    if (!location_conf) return NULL;
    return location_conf;
}

static char *ngx_http_mustach_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child) {
    ngx_http_mustach_location_conf_t *prev = parent;
    ngx_http_mustach_location_conf_t *conf = child;
    if (!conf->json) conf->json = prev->json;
    if (!conf->template) conf->template = prev->template;
    return NGX_CONF_OK;
}

static ngx_http_module_t ngx_http_mustach_ctx = {
    .preconfiguration = NULL,
    .postconfiguration = NULL,
    .create_main_conf = NULL,
    .init_main_conf = NULL,
    .create_srv_conf = NULL,
    .merge_srv_conf = NULL,
    .create_loc_conf = ngx_http_mustach_create_loc_conf,
    .merge_loc_conf = ngx_http_mustach_merge_loc_conf
};

ngx_module_t ngx_http_mustach_module = {
    NGX_MODULE_V1,
    .ctx = &ngx_http_mustach_ctx,
    .commands = ngx_http_mustach_commands,
    .type = NGX_HTTP_MODULE,
    .init_master = NULL,
    .init_module = NULL,
    .init_process = NULL,
    .init_thread = NULL,
    .exit_thread = NULL,
    .exit_process = NULL,
    .exit_master = NULL,
    NGX_MODULE_V1_PADDING
};
