#include "ABYUtils.h"

JSValueRef BlockFunctionCallAsFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argc, const JSValueRef argv[], JSValueRef* exception) {
    JSValueRef (^block)(JSContextRef ctx, size_t argc, const JSValueRef argv[]) = (__bridge JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))JSObjectGetPrivate(function);
    JSValueRef ret = block(ctx, argc, argv);
    return ret ? ret : JSValueMakeUndefined(ctx);
}

@implementation ABYUtils

+(NSString*)stringForValue:(JSValueRef)value inContext:(JSContextRef)context
{
    JSStringRef JSString = JSValueToStringCopy(context, value, NULL);
    CFStringRef string = JSStringCopyCFString(kCFAllocatorDefault, JSString);
    JSStringRelease(JSString);
    
    return (__bridge_transfer NSString *)string;
}

+(void)setValue:(JSValueRef)value onObject:(JSObjectRef)object forProperty:(NSString*)property inContext:(JSContextRef)context
{
    JSStringRef propertyName = JSStringCreateWithCFString((__bridge CFStringRef)property);
    JSObjectSetProperty(context, object, propertyName, value, 0, NULL);
    JSStringRelease(propertyName);
}

+(JSValueRef)getValueOnObject:(JSObjectRef)object forProperty:(NSString*)property inContext:(JSContextRef)context
{
    JSStringRef propertyName = JSStringCreateWithCFString((__bridge CFStringRef)property);
    JSValueRef rv = JSObjectGetProperty(context, object, propertyName, NULL);
    JSStringRelease(propertyName);
    return rv;
}

+(JSValueRef)evaluateScript:(NSString*)script inContext:(JSContextRef)context
{
    JSStringRef scriptStringRef = JSStringCreateWithCFString((__bridge CFStringRef)script);
    JSValueRef rv = JSEvaluateScript(context, scriptStringRef, NULL, NULL, 0, NULL);
    JSStringRelease(scriptStringRef);
    return rv;
}

@end