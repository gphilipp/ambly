#include "ABYContextManager.h"

#include <libkern/OSAtomic.h>

JSValueRef BlockFunctionCallAsFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argc, const JSValueRef argv[], JSValueRef* exception) {
    JSValueRef (^block)(JSContextRef ctx, size_t argc, const JSValueRef argv[]) = (__bridge JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))JSObjectGetPrivate(function);
    JSValueRef ret = block(ctx, argc, argv);
    return ret ? ret : JSValueMakeUndefined(ctx);
}

@interface ABYContextManager() {
    JSClassRef jsBlockFunctionClass;
}

// The compiler output directory
@property (strong, nonatomic) NSURL* compilerOutputDirectory;

@end

@implementation ABYContextManager

- (JSObjectRef)createFunctionWithBlock:(JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))block {
    if( !jsBlockFunctionClass ) {
        JSClassDefinition blockFunctionClassDef = kJSClassDefinitionEmpty;
        blockFunctionClassDef.callAsFunction = BlockFunctionCallAsFunction;
        blockFunctionClassDef.finalize = nil;
        jsBlockFunctionClass = JSClassCreate(&blockFunctionClassDef);
    }
    
    return JSObjectMake( _context, jsBlockFunctionClass, (void*)CFBridgingRetain(block) );
}

-(void)setValue:(JSValueRef)value onObject:(JSObjectRef)object forProperty:(NSString*)property
{
    JSStringRef propertyName = JSStringCreateWithCFString((__bridge CFStringRef)property);
    JSObjectSetProperty(_context, object, propertyName, value, 0, NULL);
    JSStringRelease(propertyName);
}

-(id)initWithContext:(JSGlobalContextRef)context compilerOutputDirectory:(NSURL*)compilerOutputDirectory
{
    if (self = [super init]) {
        _context = JSGlobalContextRetain(context);
        self.compilerOutputDirectory = compilerOutputDirectory;
    }
    return self;
}

- (void)setupGlobalContext
{
    JSStringRef javaScriptStringRef = JSStringCreateWithCFString((__bridge CFStringRef)@"var global = this");
    JSEvaluateScript(_context, javaScriptStringRef, NULL, NULL, 0, NULL);
    JSStringRelease(javaScriptStringRef);
}

- (void)setUpExceptionLogging
{
    // TODO
    /*
    self.context.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        NSString* errorString = [NSString stringWithFormat:@"[%@:%@:%@] %@\n%@", exception[@"sourceURL"], exception[@"line"], exception[@"column"], exception, [exception[@"stack"] toObject]];
        NSLog(@"%@", errorString);
    };
    */
}

- (void)setUpConsoleLog
{
    // TODO
    /*
    [self.context evaluateScript:@"var console = {}"];
    self.context[@"console"][@"log"] = ^(NSString *message) {
        NSLog(@"%@", message);
    };
    */
}

- (void)setUpTimerFunctionality
{
    // TODO
    /*
    static volatile int32_t counter = 0;
    
    NSString* callbackImpl = @"var callbackstore = {};\nvar setTimeout = function( fn, ms ) {\ncallbackstore[setTimeoutFn(ms)] = fn;\n}\nvar runTimeout = function( id ) {\nif( callbackstore[id] )\ncallbackstore[id]();\ncallbackstore[id] = null;\n}\n";
    
    [self.context evaluateScript:callbackImpl];
    
    self.context[@"setTimeoutFn"] = ^( int ms ) {
        
        int32_t incremented = OSAtomicIncrement32(&counter);
        
        NSString *str = [NSString stringWithFormat:@"timer%d", incremented];
        
        JSValue *timeOutCallback = [JSContext currentContext][@"runTimeout"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [timeOutCallback callWithArguments: @[str]];
        });
        
        return str;
    };
    */
}

-(void)setUpAmblyImportScript
{
    NSString* compilerOutputDirectoryPath = self.compilerOutputDirectory.path;
    
    JSObjectRef callbackFunction =
    
    [self createFunctionWithBlock: ^JSValueRef(JSContextRef ctx, size_t argc, const JSValueRef argv[]) {
        
        if (argc == 1 && JSValueGetType (ctx, argv[0]) == kJSTypeString)
        {
            JSStringRef pathStrRef = JSValueToStringCopy(ctx, argv[0], NULL);
            NSString* path = (__bridge NSString *) JSStringCopyCFString( kCFAllocatorDefault, pathStrRef );
            
            NSString* url = [NSURL fileURLWithPath:path].absoluteString;
            JSStringRef urlStringRef = JSStringCreateWithCFString((__bridge CFStringRef)url);
            
            NSString* readPath = [NSString stringWithFormat:@"%@/%@", compilerOutputDirectoryPath, path];
            
            NSError* error = nil;
            NSString* sourceText = [NSString stringWithContentsOfFile:readPath encoding:NSUTF8StringEncoding error:&error];
            
            if (!error && sourceText) {
                
                JSValueRef jsError = NULL;
                JSStringRef javaScriptStringRef = JSStringCreateWithCFString((__bridge CFStringRef)sourceText);
                JSEvaluateScript(ctx, javaScriptStringRef, NULL, urlStringRef, 0, &jsError);
                JSStringRelease(javaScriptStringRef);
            }
            
            JSStringRelease(urlStringRef);
        }
        
        return JSValueMakeUndefined(ctx);
    }];
    
    
    [self setValue:callbackFunction onObject:JSContextGetGlobalObject(_context) forProperty:@"AMBLY_IMPORT_SCRIPT"];
}

-(void)bootstrapWithDepsFilePath:(NSString*)depsFilePath googBasePath:(NSString*)googBasePath
{
    // TODO
    
    /*
    // This implementation mirrors the bootstrapping code that is in -setup
    
    // Setup CLOSURE_IMPORT_SCRIPT
    [self.context evaluateScript:@"CLOSURE_IMPORT_SCRIPT = function(src) { AMBLY_IMPORT_SCRIPT('goog/' + src); return true; }"];
    
    // Load goog base
    NSString *baseScriptString = [NSString stringWithContentsOfFile:googBasePath encoding:NSUTF8StringEncoding error:nil];
     NSAssert(baseScriptString != nil, @"The goog base JavaScript text could not be loaded");
    [self.context evaluateScript:baseScriptString];
    
    // Load the deps file
    NSString *depsScriptString = [NSString stringWithContentsOfFile:depsFilePath encoding:NSUTF8StringEncoding error:nil];
    NSAssert(depsScriptString != nil, @"The deps JavaScript text could not be loaded");
    [self.context evaluateScript:depsScriptString];
    
    [self.context evaluateScript:@"goog.isProvided_ = function(x) { return false; };"];
    
    [self.context evaluateScript:@"goog.require = function (name) { return CLOSURE_IMPORT_SCRIPT(goog.dependencies_.nameToPath[name]); };"];
    
    [self.context evaluateScript:@"goog.require('cljs.core');"];
    
    // TODO Is there a better way for the impl below that avoids making direct calls to
    // ClojureScript compiled artifacts? (Complex and perhaps also fragile).
    
     // redef goog.require to track loaded libs
    [self.context evaluateScript:@"cljs.core._STAR_loaded_libs_STAR_ = new cljs.core.PersistentHashSet(null, new cljs.core.PersistentArrayMap(null, 1, ['cljs.core',null], null), null);\n"
     "\n"
     "goog.require = (function (name,reload){\n"
     "   if(cljs.core.truth_((function (){var or__4112__auto__ = !(cljs.core.contains_QMARK_.call(null,cljs.core._STAR_loaded_libs_STAR_,name));\n"
     "       if(or__4112__auto__){\n"
     "           return or__4112__auto__;\n"
     "       } else {\n"
     "           return reload;\n"
     "       }\n"
     "   })())){\n"
     "       cljs.core._STAR_loaded_libs_STAR_ = cljs.core.conj.call(null,(function (){var or__4112__auto__ = cljs.core._STAR_loaded_libs_STAR_;\n"
     "           if(cljs.core.truth_(or__4112__auto__)){\n"
     "               return or__4112__auto__;\n"
     "           } else {\n"
     "               return cljs.core.PersistentHashSet.EMPTY;\n"
     "           }\n"
     "       })(),name);\n"
     "       \n"
     "       return CLOSURE_IMPORT_SCRIPT((goog.dependencies_.nameToPath[name]));\n"
     "   } else {\n"
     "       return null;\n"
     "   }\n"
     "});"];
     */
}

@end
