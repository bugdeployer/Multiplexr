#include <jni.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "quickjs.h"

/* One invocation at a time, isolated UID. No libc module, module loader,
 * JNI object, class lookup, file descriptor or host object is exposed. */
#define MESSAGE_LIMIT 65536
#define HEAP_LIMIT (8 * 1024 * 1024)
static atomic_llong cancelled_through = 0;
typedef struct { int64_t id, deadline; int interrupted, calls; JNIEnv *env; jobject bridge; } Budget;
typedef struct { int denied; } MemoryBudget;
typedef union { size_t size; max_align_t alignment; } Allocation;
static size_t allocation_size(const void *ptr) { return ptr ? ((const Allocation *)ptr - 1)->size : 0; }
static void *limited_malloc(JSMallocState *s, size_t n) {
    if (n > HEAP_LIMIT - sizeof(Allocation) || s->malloc_size > HEAP_LIMIT - n - sizeof(Allocation)) {
        ((MemoryBudget *)s->opaque)->denied = 1; return NULL;
    }
    Allocation *p = malloc(n + sizeof(Allocation));
    if (!p) { ((MemoryBudget *)s->opaque)->denied = 1; return NULL; }
    p->size = n; s->malloc_size += n + sizeof(Allocation); s->malloc_count++;
    return p + 1;
}
static void limited_free(JSMallocState *s, void *ptr) {
    if (!ptr) return;
    s->malloc_size -= allocation_size(ptr) + sizeof(Allocation); s->malloc_count--;
    free((Allocation *)ptr - 1);
}
static void *limited_realloc(JSMallocState *s, void *ptr, size_t n) {
    if (!ptr) return limited_malloc(s, n);
    if (!n) { limited_free(s, ptr); return NULL; }
    size_t old = allocation_size(ptr);
    if (n > HEAP_LIMIT - sizeof(Allocation) || s->malloc_size - old > HEAP_LIMIT - n) {
        ((MemoryBudget *)s->opaque)->denied = 1; return NULL;
    }
    Allocation *p = realloc((Allocation *)ptr - 1, n + sizeof(Allocation));
    if (!p) { ((MemoryBudget *)s->opaque)->denied = 1; return NULL; }
    p->size = n; s->malloc_size = s->malloc_size - old + n;
    return p + 1;
}
static const JSMallocFunctions allocator = { limited_malloc, limited_free, limited_realloc, allocation_size };
static int64_t now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
static int interrupt(JSRuntime *rt, void *opaque) {
    Budget *b = opaque;
    if (atomic_load(&cancelled_through) >= b->id) b->interrupted = 1;
    else if (now_ms() >= b->deadline) b->interrupted = 2;
    return b->interrupted != 0;
}
static JSValue host_call(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    Budget *b = JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
    if (++b->calls > 64) return JS_ThrowRangeError(ctx, "host call quota exceeded");
    if (argc != 1 || !JS_IsString(argv[0])) return JS_ThrowTypeError(ctx, "JSON request required");
    size_t n; const char *s = JS_ToCStringLen(ctx, &n, argv[0]);
    if (!s) return JS_EXCEPTION;
    if (n > MESSAGE_LIMIT) { JS_FreeCString(ctx, s); return JS_ThrowRangeError(ctx, "message too large"); }
    JSValue req = JS_ParseJSON(ctx, s, n, "host-request"); JS_FreeCString(ctx, s);
    if (JS_IsException(req)) return req;
    if (!JS_IsObject(req) || JS_IsArray(ctx, req)) { JS_FreeValue(ctx, req); return JS_ThrowTypeError(ctx, "request object required"); }
    JSValue v = JS_GetPropertyStr(ctx, req, "v"), method = JS_GetPropertyStr(ctx, req, "method"), id = JS_GetPropertyStr(ctx, req, "id");
    double version = 0; if (JS_IsNumber(v)) JS_ToFloat64(ctx, &version, v);
    size_t name_len = 0;
    const char *name = JS_IsString(method) ? JS_ToCStringLen(ctx, &name_len, method) : NULL;
    size_t id_len = 0;
    const char *request_id = JS_IsString(id) ? JS_ToCStringLen(ctx, &id_len, id) : NULL;
    int valid_id = request_id && id_len > 0 && id_len <= 64;
    if (valid_id) for (size_t i = 0; i < id_len; i++) {
        char c = request_id[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-')) valid_id = 0;
    }
    int valid_method = name && name_len > 0 && name_len <= 100;
    int dots = 0, segment_start = 1;
    if (valid_method) for (size_t i = 0; i < name_len; i++) {
        unsigned char c = (unsigned char)name[i];
        if (c == '.') { if (segment_start) valid_method = 0; dots++; segment_start = 1; }
        else { if (!(segment_start ? (c >= 'a' && c <= 'z') :
            (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) valid_method = 0;
            segment_start = 0; }
    }
    if (segment_start || !dots) valid_method = 0;
    JSPropertyEnum *properties = NULL; uint32_t property_count = 0;
    int valid_shape = JS_GetOwnPropertyNames(ctx, &properties, &property_count, req, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) >= 0;
    if (valid_shape) {
        valid_shape = property_count == 4;
        for (uint32_t i = 0; i < property_count; i++) {
            const char *key = JS_AtomToCString(ctx, properties[i].atom);
            if (!key || (strcmp(key, "v") && strcmp(key, "id") && strcmp(key, "method") && strcmp(key, "params"))) valid_shape = 0;
            if (key) JS_FreeCString(ctx, key);
            JS_FreeAtom(ctx, properties[i].atom);
        }
        js_free(ctx, properties);
    }
    JSValue params = JS_GetPropertyStr(ctx, req, "params");
    /* The proof exposes only ping, whose parameters are an empty object. No
     * production dispatch is inferred from declared manifest capabilities. */
    if (valid_method && !strcmp(name, "runtime.ping")) {
        JSValue encoded = JS_JSONStringify(ctx, params, JS_UNDEFINED, JS_UNDEFINED);
        const char *json = JS_IsString(encoded) ? JS_ToCString(ctx, encoded) : NULL;
        if (!json || strcmp(json, "{}")) valid_shape = 0;
        if (json) JS_FreeCString(ctx, json);
        JS_FreeValue(ctx, encoded);
    }
    JS_FreeValue(ctx, params);
    /* Only JSON text crosses JNI; the isolated process has no application objects.
     * A missing gateway retains the original standalone proof behavior. */
    if (valid_id && valid_method && valid_shape && version == 1 && b->env && b->bridge) {
        JNIEnv *env = b->env;
        jclass type = (*env)->GetObjectClass(env, b->bridge);
        jmethodID method_id = (*env)->GetMethodID(env, type, "hostCall", "([B)[B");
        size_t raw_length = 0; const char *raw = JS_ToCStringLen(ctx, &raw_length, argv[0]);
        jbyteArray argument = raw ? (*env)->NewByteArray(env, (jsize)raw_length) : NULL;
        if(argument && raw) (*env)->SetByteArrayRegion(env, argument, 0, (jsize)raw_length, (const jbyte *)raw);
        if (raw) JS_FreeCString(ctx, raw);
        int64_t started = now_ms();
        jbyteArray response = method_id && argument ? (*env)->CallObjectMethod(env, b->bridge, method_id, argument) : NULL;
        b->deadline += now_ms() - started;
        int bridge_failed = (*env)->ExceptionCheck(env);
        if (bridge_failed) { (*env)->ExceptionClear(env); response = NULL; }
        if (argument) (*env)->DeleteLocalRef(env, argument);
        (*env)->DeleteLocalRef(env, type);
        if(bridge_failed) {
            if(name) JS_FreeCString(ctx, name); if(request_id) JS_FreeCString(ctx, request_id);
            JS_FreeValue(ctx, method); JS_FreeValue(ctx, v); JS_FreeValue(ctx, id); JS_FreeValue(ctx, req);
            return JS_ThrowInternalError(ctx, "host call failed");
        }
        if (response) {
            jsize size = (*env)->GetArrayLength(env, response);
            jbyte *json = size <= MESSAGE_LIMIT ? (*env)->GetByteArrayElements(env, response, NULL) : NULL;
            JSValue answer = json ? JS_NewStringLen(ctx, (const char *)json, size) : JS_ThrowRangeError(ctx, "message too large");
            if(json) (*env)->ReleaseByteArrayElements(env, response, json, JNI_ABORT);
            (*env)->DeleteLocalRef(env, response);
            if(name) JS_FreeCString(ctx, name); if(request_id) JS_FreeCString(ctx, request_id);
            JS_FreeValue(ctx, method); JS_FreeValue(ctx, v); JS_FreeValue(ctx, id); JS_FreeValue(ctx, req);
            return answer;
        }
    }
    /* Proof only: no production capability gateway or mutation authority. */
    const char *payload = !valid_id || !valid_method || !valid_shape ? "\"error\":{\"code\":\"invalid_request\"}" :
        version != 1 ? "\"error\":{\"code\":\"version_mismatch\"}" :
        !strcmp(name, "runtime.ping") ? "\"result\":{\"protocol\":1,\"runtime\":\"quickjs\"}" :
        "\"error\":{\"code\":\"unsupported_capability\"}";
    char reply[256];
    if (valid_id) snprintf(reply, sizeof(reply), "{\"v\":1,\"id\":\"%s\",%s}", request_id, payload);
    else snprintf(reply, sizeof(reply), "{\"v\":1,\"id\":null,%s}", payload);
    if (name) JS_FreeCString(ctx, name);
    if (request_id) JS_FreeCString(ctx, request_id);
    JS_FreeValue(ctx, method); JS_FreeValue(ctx, v); JS_FreeValue(ctx, id); JS_FreeValue(ctx, req);
    return JS_NewString(ctx, reply);
}
JNIEXPORT void JNICALL Java_com_bugdeployer_multiplexr_plugins_QuickJs_cancel(JNIEnv *env, jobject self, jlong id) {
    long long old = atomic_load(&cancelled_through);
    while (old < id && !atomic_compare_exchange_weak(&cancelled_through, &old, id)) {}
}
JNIEXPORT jbyteArray JNICALL Java_com_bugdeployer_multiplexr_plugins_QuickJs_execute(
    JNIEnv *env, jobject self, jbyteArray source, jbyteArray input, jlong id) {
    const char *error = "runtime_failure";
    jbyteArray output = NULL; JSRuntime *rt = NULL; JSContext *ctx = NULL;
    JSValue result = JS_UNDEFINED; char *code = NULL, *request = NULL;
    jsize length = (*env)->GetArrayLength(env, source), input_length = (*env)->GetArrayLength(env, input);
    if (length > MESSAGE_LIMIT || input_length > MESSAGE_LIMIT) { error = "message_too_large"; goto done; }
    code = malloc((size_t)length + 1); request = malloc((size_t)input_length + 1);
    if (!code || !request) { error = "resource_limit"; goto done; }
    (*env)->GetByteArrayRegion(env, source, 0, length, (jbyte *)code); code[length] = 0;
    (*env)->GetByteArrayRegion(env, input, 0, input_length, (jbyte *)request); request[input_length] = 0;
    MemoryBudget memory = {0};
    rt = JS_NewRuntime2(&allocator, &memory); if (!rt) { error = "resource_limit"; goto done; }
    JS_SetMemoryLimit(rt, HEAP_LIMIT); JS_SetMaxStackSize(rt, 256 * 1024);
    Budget budget = { .id = id, .deadline = now_ms() + 250, .env = env, .bridge = self };
    JS_SetRuntimeOpaque(rt, &budget); JS_SetInterruptHandler(rt, interrupt, &budget);
    ctx = JS_NewContext(rt); if (!ctx) { error = "resource_limit"; goto done; }
    JSValue global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "__hostCall", JS_NewCFunction(ctx, host_call, "hostCall", 1));
    JSValue parsed = JS_ParseJSON(ctx, request, input_length, "request");
    if (JS_IsException(parsed)) { JS_FreeValue(ctx, global); error = "invalid_request"; goto done; }
    JS_SetPropertyStr(ctx, global, "__request", parsed); JS_FreeValue(ctx, global);
    result = JS_Eval(ctx, code, length, "plugin.js", JS_EVAL_TYPE_GLOBAL);
    if (!JS_IsException(result)) {
        JS_FreeValue(ctx, result);
        const char *invoke = "multiplexrEntry(__request)";
        result = JS_Eval(ctx, invoke, strlen(invoke), "invoke", JS_EVAL_TYPE_GLOBAL);
    }
    if (!JS_IsException(result)) {
        if ((int)JS_PromiseState(ctx, result) >= 0) { error = "unsupported_capability"; goto done; }
        JSValue encoded = JS_JSONStringify(ctx, result, JS_UNDEFINED, JS_UNDEFINED);
        JS_FreeValue(ctx, result); result = encoded;
    }
    if (JS_IsException(result)) {
        error = budget.interrupted == 1 ? "cancelled" : budget.interrupted == 2 ? "deadline_exceeded" : memory.denied ? "resource_limit" : "plugin_error";
        /* Never invoke an untrusted exception's getters/toString. */
        goto done;
    }
    if (!JS_IsString(result)) { error = "invalid_response"; goto done; }
    if (memory.denied) { error = "resource_limit"; goto done; }
    size_t n; const char *value = JS_ToCStringLen(ctx, &n, result);
    if (!value) { error = "resource_limit"; goto done; }
    if (n > MESSAGE_LIMIT) { JS_FreeCString(ctx, value); error = "message_too_large"; goto done; }
    output = (*env)->NewByteArray(env, (jsize)n + 1);
    jbyte marker = 0; (*env)->SetByteArrayRegion(env, output, 0, 1, &marker);
    (*env)->SetByteArrayRegion(env, output, 1, (jsize)n, (const jbyte *)value);
    JS_FreeCString(ctx, value);
done:
    if (ctx) { JS_FreeValue(ctx, result); JS_FreeContext(ctx); }
    if (rt) JS_FreeRuntime(rt);
    free(code); free(request);
    if (!output) {
        size_t n = strlen(error); output = (*env)->NewByteArray(env, (jsize)n + 1);
        jbyte marker = 1; (*env)->SetByteArrayRegion(env, output, 0, 1, &marker);
        (*env)->SetByteArrayRegion(env, output, 1, (jsize)n, (const jbyte *)error);
    }
    return output;
}
