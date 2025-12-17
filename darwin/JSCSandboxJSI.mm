#import "JSCSandboxJSI.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <Foundation/Foundation.h>

namespace jsc_sandbox {

// MARK: - JSCSandboxContext Implementation

JSCSandboxContext::JSCSandboxContext(jsi::Runtime& hostRuntime, double timeout)
    : jsContext_(nullptr)
    , hostRuntime_(&hostRuntime)
    , timeout_(timeout)
    , disposed_(false)
    , callbackCounter_(0)
{
    @autoreleasepool {
        JSContext* ctx = [[JSContext alloc] init];
        if (!ctx) {
            throw jsi::JSError(hostRuntime, "Failed to create JSContext");
        }

        // Set up exception handler
        ctx.exceptionHandler = ^(JSContext* context, JSValue* exception) {
            NSLog(@"[JSCSandbox] Exception: %@", exception);
        };

        // Inject console shim
        JSValue* consoleLog = [JSValue valueWithObject:^(JSValue* message) {
            NSLog(@"[JSCSandbox] %@", message);
        } inContext:ctx];
        ctx[@"__jsc_console_log"] = consoleLog;

        NSString* consoleScript = @R"(
            var console = {
                log: function() { __jsc_console_log(Array.prototype.slice.call(arguments).join(' ')); },
                warn: function() { __jsc_console_log('[WARN] ' + Array.prototype.slice.call(arguments).join(' ')); },
                error: function() { __jsc_console_log('[ERROR] ' + Array.prototype.slice.call(arguments).join(' ')); },
                info: function() { __jsc_console_log('[INFO] ' + Array.prototype.slice.call(arguments).join(' ')); },
                debug: function() { __jsc_console_log('[DEBUG] ' + Array.prototype.slice.call(arguments).join(' ')); },
                assert: function(cond) { if (!cond) __jsc_console_log('[ASSERT] ' + Array.prototype.slice.call(arguments, 1).join(' ')); },
                trace: function() {},
                time: function() {},
                timeEnd: function() {},
                group: function() {},
                groupEnd: function() {}
            };
        )";
        [ctx evaluateScript:consoleScript];

        jsContext_ = (__bridge_retained void*)ctx;
    }
}

JSCSandboxContext::~JSCSandboxContext() {
    dispose();
}

void JSCSandboxContext::dispose() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (disposed_) return;
    disposed_ = true;

    if (jsContext_) {
        @autoreleasepool {
            JSContext* ctx = (__bridge_transfer JSContext*)jsContext_;
            ctx = nil;  // Release
        }
        jsContext_ = nullptr;
    }
    callbacks_.clear();
}

jsi::Value JSCSandboxContext::get(jsi::Runtime& rt, const jsi::PropNameID& name) {
    std::string propName = name.utf8(rt);

    if (propName == "eval") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            1, // argc
            [this](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                if (count < 1 || !args[0].isString()) {
                    throw jsi::JSError(rt, "eval requires a string argument");
                }
                std::string code = args[0].asString(rt).utf8(rt);
                return this->eval(rt, code);
            }
        );
    }

    if (propName == "setGlobal") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            2, // argc
            [this](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                if (count < 2 || !args[0].isString()) {
                    throw jsi::JSError(rt, "setGlobal requires (name: string, value: any)");
                }
                std::string globalName = args[0].asString(rt).utf8(rt);
                this->setGlobal(rt, globalName, args[1]);
                return jsi::Value::undefined();
            }
        );
    }

    if (propName == "getGlobal") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            1, // argc
            [this](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                if (count < 1 || !args[0].isString()) {
                    throw jsi::JSError(rt, "getGlobal requires a string argument");
                }
                std::string globalName = args[0].asString(rt).utf8(rt);
                return this->getGlobal(rt, globalName);
            }
        );
    }

    if (propName == "dispose") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            0,
            [this](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                this->dispose();
                return jsi::Value::undefined();
            }
        );
    }

    if (propName == "isDisposed") {
        return jsi::Value(disposed_);
    }

    return jsi::Value::undefined();
}

void JSCSandboxContext::set(jsi::Runtime& rt, const jsi::PropNameID& name, const jsi::Value& value) {
    // Read-only
}

std::vector<jsi::PropNameID> JSCSandboxContext::getPropertyNames(jsi::Runtime& rt) {
    std::vector<jsi::PropNameID> props;
    props.push_back(jsi::PropNameID::forUtf8(rt, "eval"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "setGlobal"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "getGlobal"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "dispose"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "isDisposed"));
    return props;
}

jsi::Value JSCSandboxContext::eval(jsi::Runtime& rt, const std::string& code) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (disposed_) {
        throw jsi::JSError(rt, "Context has been disposed");
    }

    @autoreleasepool {
        JSContext* ctx = (__bridge JSContext*)jsContext_;
        NSString* nsCode = [NSString stringWithUTF8String:code.c_str()];

        JSValue* result = [ctx evaluateScript:nsCode];

        // Check for exceptions
        if (ctx.exception) {
            NSString* errorMsg = [ctx.exception toString];
            ctx.exception = nil;
            throw jsi::JSError(rt, [errorMsg UTF8String]);
        }

        return jsValueToJSI(rt, (__bridge void*)result);
    }
}

void JSCSandboxContext::setGlobal(jsi::Runtime& rt, const std::string& name, const jsi::Value& value) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (disposed_) {
        throw jsi::JSError(rt, "Context has been disposed");
    }

    @autoreleasepool {
        JSContext* ctx = (__bridge JSContext*)jsContext_;
        NSString* nsName = [NSString stringWithUTF8String:name.c_str()];

        // Handle functions specially - create a wrapper function in JS that calls our block
        // This ensures typeof returns "function" instead of "object"
        if (value.isObject() && value.asObject(rt).isFunction(rt)) {
            // Store the function
            std::string callbackId = "cb_" + std::to_string(++callbackCounter_);
            auto func = std::make_shared<jsi::Function>(value.asObject(rt).asFunction(rt));
            callbacks_[callbackId] = func;

            // Capture what we need for the block
            jsi::Runtime* hostRt = hostRuntime_;
            std::string cbId = callbackId;
            auto* self = this;

            // First, create a block-based function with internal name
            NSString* internalName = [NSString stringWithFormat:@"__jsc_cb_%s", cbId.c_str()];
            JSValue* blockFn = [JSValue valueWithObject:^id(void) {
                NSArray* jsArgs = [JSContext currentArguments];

                @autoreleasepool {
                    auto it = self->callbacks_.find(cbId);
                    if (it == self->callbacks_.end()) {
                        NSLog(@"[JSCSandbox] Callback %s not found", cbId.c_str());
                        return nil;
                    }

                    try {
                        std::vector<jsi::Value> jsiArgs;
                        for (JSValue* arg in jsArgs) {
                            jsiArgs.push_back(self->jsValueToJSI(*hostRt, (__bridge void*)arg));
                        }

                        jsi::Value result;
                        if (jsiArgs.empty()) {
                            result = it->second->call(*hostRt);
                        } else {
                            result = it->second->call(*hostRt, (const jsi::Value*)jsiArgs.data(), jsiArgs.size());
                        }

                        void* jsResult = self->jsiToJSValue(*hostRt, result);
                        return (__bridge id)jsResult;
                    } catch (const std::exception& e) {
                        NSLog(@"[JSCSandbox] Callback error: %s", e.what());
                        return nil;
                    }
                }
            } inContext:ctx];

            // Store the block function with internal name
            ctx[internalName] = blockFn;

            // Create a proper function wrapper using eval
            // This ensures typeof returns "function"
            NSString* wrapperScript = [NSString stringWithFormat:
                @"(function() { var fn = function() { return %@.apply(this, arguments); }; return fn; })()",
                internalName];
            JSValue* wrapperFn = [ctx evaluateScript:wrapperScript];

            // Set the wrapper as the global with the requested name
            ctx[nsName] = wrapperFn;
        } else {
            // Convert and set non-function values
            void* jsValue = jsiToJSValue(rt, value);
            ctx[nsName] = (__bridge JSValue*)jsValue;
        }
    }
}

jsi::Value JSCSandboxContext::getGlobal(jsi::Runtime& rt, const std::string& name) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (disposed_) {
        throw jsi::JSError(rt, "Context has been disposed");
    }

    @autoreleasepool {
        JSContext* ctx = (__bridge JSContext*)jsContext_;
        NSString* nsName = [NSString stringWithUTF8String:name.c_str()];
        JSValue* value = ctx[nsName];
        return jsValueToJSI(rt, (__bridge void*)value);
    }
}

// Convert jsi::Value to JSValue*
void* JSCSandboxContext::jsiToJSValue(jsi::Runtime& rt, const jsi::Value& value) {
    JSContext* ctx = (__bridge JSContext*)jsContext_;

    if (value.isUndefined()) {
        return (__bridge void*)[JSValue valueWithUndefinedInContext:ctx];
    }
    if (value.isNull()) {
        return (__bridge void*)[JSValue valueWithNullInContext:ctx];
    }
    if (value.isBool()) {
        return (__bridge void*)[JSValue valueWithBool:value.getBool() inContext:ctx];
    }
    if (value.isNumber()) {
        return (__bridge void*)[JSValue valueWithDouble:value.getNumber() inContext:ctx];
    }
    if (value.isString()) {
        std::string str = value.asString(rt).utf8(rt);
        NSString* nsStr = [NSString stringWithUTF8String:str.c_str()];
        return (__bridge void*)[JSValue valueWithObject:nsStr inContext:ctx];
    }
    if (value.isObject()) {
        jsi::Object obj = value.asObject(rt);

        // Handle arrays
        if (obj.isArray(rt)) {
            jsi::Array arr = obj.asArray(rt);
            size_t len = arr.size(rt);
            NSMutableArray* nsArr = [NSMutableArray arrayWithCapacity:len];
            for (size_t i = 0; i < len; i++) {
                JSValue* elem = (__bridge JSValue*)jsiToJSValue(rt, arr.getValueAtIndex(rt, i));
                [nsArr addObject:elem ?: [NSNull null]];
            }
            return (__bridge void*)[JSValue valueWithObject:nsArr inContext:ctx];
        }

        // Handle plain objects
        jsi::Array propNames = obj.getPropertyNames(rt);
        size_t len = propNames.size(rt);
        NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:len];
        for (size_t i = 0; i < len; i++) {
            std::string key = propNames.getValueAtIndex(rt, i).asString(rt).utf8(rt);
            NSString* nsKey = [NSString stringWithUTF8String:key.c_str()];
            jsi::Value propVal = obj.getProperty(rt, key.c_str());
            // Skip functions in plain object conversion
            if (!propVal.isObject() || !propVal.asObject(rt).isFunction(rt)) {
                JSValue* jsVal = (__bridge JSValue*)jsiToJSValue(rt, propVal);
                if (jsVal) {
                    dict[nsKey] = jsVal;
                }
            }
        }
        return (__bridge void*)[JSValue valueWithObject:dict inContext:ctx];
    }

    return (__bridge void*)[JSValue valueWithUndefinedInContext:ctx];
}

// Convert JSValue* to jsi::Value
jsi::Value JSCSandboxContext::jsValueToJSI(jsi::Runtime& rt, void* jsValue) {
    JSValue* value = (__bridge JSValue*)jsValue;

    if (!value || [value isUndefined]) {
        return jsi::Value::undefined();
    }
    if ([value isNull]) {
        return jsi::Value::null();
    }
    if ([value isBoolean]) {
        return jsi::Value([value toBool]);
    }
    if ([value isNumber]) {
        return jsi::Value([value toDouble]);
    }
    if ([value isString]) {
        NSString* str = [value toString];
        return jsi::String::createFromUtf8(rt, [str UTF8String]);
    }
    if ([value isArray]) {
        NSArray* arr = [value toArray];
        jsi::Array jsiArr = jsi::Array(rt, arr.count);
        for (NSUInteger i = 0; i < arr.count; i++) {
            id elem = arr[i];
            if ([elem isKindOfClass:[JSValue class]]) {
                jsiArr.setValueAtIndex(rt, i, jsValueToJSI(rt, (__bridge void*)elem));
            } else if ([elem isKindOfClass:[NSNumber class]]) {
                jsiArr.setValueAtIndex(rt, i, jsi::Value([elem doubleValue]));
            } else if ([elem isKindOfClass:[NSString class]]) {
                jsiArr.setValueAtIndex(rt, i, jsi::String::createFromUtf8(rt, [elem UTF8String]));
            } else if ([elem isKindOfClass:[NSNull class]]) {
                jsiArr.setValueAtIndex(rt, i, jsi::Value::null());
            } else if ([elem isKindOfClass:[NSDictionary class]]) {
                // Recursively convert nested objects
                JSContext* ctx = (__bridge JSContext*)jsContext_;
                JSValue* nestedValue = [JSValue valueWithObject:elem inContext:ctx];
                jsiArr.setValueAtIndex(rt, i, jsValueToJSI(rt, (__bridge void*)nestedValue));
            }
        }
        return std::move(jsiArr);
    }
    if ([value isObject]) {
        NSDictionary* dict = [value toDictionary];
        jsi::Object jsiObj = jsi::Object(rt);
        for (NSString* key in dict) {
            id val = dict[key];
            if ([val isKindOfClass:[JSValue class]]) {
                jsiObj.setProperty(rt, [key UTF8String], jsValueToJSI(rt, (__bridge void*)val));
            } else if ([val isKindOfClass:[NSNumber class]]) {
                // Check if it's a boolean
                if (strcmp([val objCType], @encode(BOOL)) == 0) {
                    jsiObj.setProperty(rt, [key UTF8String], jsi::Value([val boolValue]));
                } else {
                    jsiObj.setProperty(rt, [key UTF8String], jsi::Value([val doubleValue]));
                }
            } else if ([val isKindOfClass:[NSString class]]) {
                jsiObj.setProperty(rt, [key UTF8String], jsi::String::createFromUtf8(rt, [val UTF8String]));
            } else if ([val isKindOfClass:[NSNull class]]) {
                jsiObj.setProperty(rt, [key UTF8String], jsi::Value::null());
            } else if ([val isKindOfClass:[NSDictionary class]]) {
                JSContext* ctx = (__bridge JSContext*)jsContext_;
                JSValue* nestedValue = [JSValue valueWithObject:val inContext:ctx];
                jsiObj.setProperty(rt, [key UTF8String], jsValueToJSI(rt, (__bridge void*)nestedValue));
            } else if ([val isKindOfClass:[NSArray class]]) {
                JSContext* ctx = (__bridge JSContext*)jsContext_;
                JSValue* nestedValue = [JSValue valueWithObject:val inContext:ctx];
                jsiObj.setProperty(rt, [key UTF8String], jsValueToJSI(rt, (__bridge void*)nestedValue));
            }
        }
        return std::move(jsiObj);
    }

    return jsi::Value::undefined();
}

// MARK: - JSCSandboxRuntime Implementation

JSCSandboxRuntime::JSCSandboxRuntime(jsi::Runtime& hostRuntime, double timeout)
    : hostRuntime_(&hostRuntime)
    , timeout_(timeout)
    , disposed_(false)
{
}

JSCSandboxRuntime::~JSCSandboxRuntime() {
    dispose();
}

void JSCSandboxRuntime::dispose() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (disposed_) return;
    disposed_ = true;

    for (auto& ctx : contexts_) {
        ctx->dispose();
    }
    contexts_.clear();
}

jsi::Value JSCSandboxRuntime::get(jsi::Runtime& rt, const jsi::PropNameID& name) {
    std::string propName = name.utf8(rt);

    if (propName == "createContext") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            0,
            [this](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                return this->createContext(rt);
            }
        );
    }

    if (propName == "dispose") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            0,
            [this](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                this->dispose();
                return jsi::Value::undefined();
            }
        );
    }

    return jsi::Value::undefined();
}

void JSCSandboxRuntime::set(jsi::Runtime& rt, const jsi::PropNameID& name, const jsi::Value& value) {
    // Read-only
}

std::vector<jsi::PropNameID> JSCSandboxRuntime::getPropertyNames(jsi::Runtime& rt) {
    std::vector<jsi::PropNameID> props;
    props.push_back(jsi::PropNameID::forUtf8(rt, "createContext"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "dispose"));
    return props;
}

jsi::Value JSCSandboxRuntime::createContext(jsi::Runtime& rt) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (disposed_) {
        throw jsi::JSError(rt, "Runtime has been disposed");
    }

    auto context = std::make_shared<JSCSandboxContext>(*hostRuntime_, timeout_);
    contexts_.push_back(context);

    return jsi::Object::createFromHostObject(rt, context);
}

// MARK: - JSCSandboxModule Implementation

JSCSandboxModule::JSCSandboxModule(jsi::Runtime& runtime)
    : runtime_(&runtime)
{
}

JSCSandboxModule::~JSCSandboxModule() {
}

jsi::Value JSCSandboxModule::get(jsi::Runtime& rt, const jsi::PropNameID& name) {
    std::string propName = name.utf8(rt);

    if (propName == "createRuntime") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            1,
            [](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                double timeout = 30000; // default 30s

                if (count > 0 && args[0].isObject()) {
                    jsi::Object opts = args[0].asObject(rt);
                    if (opts.hasProperty(rt, "timeout")) {
                        jsi::Value timeoutVal = opts.getProperty(rt, "timeout");
                        if (timeoutVal.isNumber()) {
                            timeout = timeoutVal.getNumber();
                        }
                    }
                }

                auto runtime = std::make_shared<JSCSandboxRuntime>(rt, timeout);
                return jsi::Object::createFromHostObject(rt, runtime);
            }
        );
    }

    if (propName == "isAvailable") {
        return jsi::Function::createFromHostFunction(
            rt,
            name,
            0,
            [](jsi::Runtime& rt, const jsi::Value& thisVal, const jsi::Value* args, size_t count) -> jsi::Value {
                return jsi::Value(true);
            }
        );
    }

    return jsi::Value::undefined();
}

void JSCSandboxModule::set(jsi::Runtime& rt, const jsi::PropNameID& name, const jsi::Value& value) {
    // Read-only
}

std::vector<jsi::PropNameID> JSCSandboxModule::getPropertyNames(jsi::Runtime& rt) {
    std::vector<jsi::PropNameID> props;
    props.push_back(jsi::PropNameID::forUtf8(rt, "createRuntime"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "isAvailable"));
    return props;
}

void JSCSandboxModule::install(jsi::Runtime& runtime) {
    auto module = std::make_shared<JSCSandboxModule>(runtime);
    jsi::Object moduleObj = jsi::Object::createFromHostObject(runtime, module);
    runtime.global().setProperty(runtime, "__JSCSandboxJSI", std::move(moduleObj));
}

} // namespace jsc_sandbox
