#include <JavaScriptCore/JavaScriptCore.h>

JSValueRef BlockFunctionCallAsFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argc, const JSValueRef argv[], JSValueRef* exception);

@interface ABYUtils : NSObject

+(NSString*)stringForValue:(JSValueRef)value inContext:(JSContextRef)context;
+(void)setValue:(JSValueRef)value onObject:(JSObjectRef)object forProperty:(NSString*)property inContext:(JSContextRef)context;
+(JSValueRef)getValueOnObject:(JSObjectRef)object forProperty:(NSString*)property inContext:(JSContextRef)context;
+(JSValueRef)evaluateScript:(NSString*)script inContext:(JSContextRef)context;
+(void)installGlobalFunctionWithBlock:(JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))block name:(NSString*)name argList:(NSString*)argList inContext:(JSContextRef)context;

@end