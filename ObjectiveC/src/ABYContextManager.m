#include "ABYContextManager.h"
#include "ABYUtils.h"
#include <libkern/OSAtomic.h>

@interface ABYContextManager() {
    JSClassRef jsBlockFunctionClass;
}

// The compiler output directory
@property (strong, nonatomic) NSURL* compilerOutputDirectory;

@end

@implementation ABYContextManager

- (JSObjectRef)createFunctionWithBlock:(JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))block
{
    if(!jsBlockFunctionClass) {
        JSClassDefinition blockFunctionClassDef = kJSClassDefinitionEmpty;
        blockFunctionClassDef.callAsFunction = BlockFunctionCallAsFunction;
        blockFunctionClassDef.finalize = nil;
        jsBlockFunctionClass = JSClassCreate(&blockFunctionClassDef);
    }
    
    return JSObjectMake(_context, jsBlockFunctionClass, (void*)CFBridgingRetain(block));
}

-(id)initWithContext:(JSGlobalContextRef)context compilerOutputDirectory:(NSURL*)compilerOutputDirectory
{
    if (self = [super init]) {
        _context = JSGlobalContextRetain(context);
        self.compilerOutputDirectory = compilerOutputDirectory;
    }
    return self;
}

-(void)dealloc
{
    if (jsBlockFunctionClass) {
        JSClassRelease(jsBlockFunctionClass);
    }
}

- (void)setupGlobalContext
{
    [ABYUtils evaluateScript:@"var global = this" inContext:_context];
}

- (void)setUpExceptionLogging
{
    NSLog(@"setUpExceptionLogging is being eliminated with move to JavaScriptCore C API");
}

- (void)setUpConsoleLog
{
    [ABYUtils evaluateScript:@"var console = {}" inContext:_context];
    
    JSObjectRef callbackFunction =
    [self createFunctionWithBlock: ^JSValueRef(JSContextRef ctx, size_t argc, const JSValueRef argv[]) {
        
        if (argc == 1 && JSValueGetType (ctx, argv[0]) == kJSTypeString)
        {
            JSStringRef messageStringRef = JSValueToStringCopy(ctx, argv[0], NULL);
            NSString* message = (__bridge NSString *) JSStringCopyCFString(kCFAllocatorDefault, messageStringRef);
            NSLog(@"%@", message);
            JSStringRelease(messageStringRef);
        }
        
        return JSValueMakeUndefined(ctx);
    }];
    
    [ABYUtils setValue:callbackFunction
          onObject:JSValueToObject(_context, [ABYUtils getValueOnObject:JSContextGetGlobalObject(_context) forProperty:@"console" inContext:_context], NULL)
       forProperty:@"log" inContext:_context];
}

- (void)setUpTimerFunctionality
{
    
    static volatile int32_t counter = 0;
    
    NSString* callbackImpl = @"var callbackstore = {};\nvar setTimeout = function( fn, ms ) {\ncallbackstore[setTimeoutFn(ms)] = fn;\n}\nvar runTimeout = function( id ) {\nif( callbackstore[id] )\ncallbackstore[id]();\ncallbackstore[id] = null;\n}\n";
    
    [ABYUtils evaluateScript:callbackImpl inContext:_context];
    
    __weak typeof(self) weakSelf = self;
    
    JSObjectRef callbackFunction =
    [self createFunctionWithBlock: ^JSValueRef(JSContextRef ctx, size_t argc, const JSValueRef argv[]) {
        if (argc == 1 && JSValueGetType (ctx, argv[0]) == kJSTypeNumber)
        {
            int ms = (int)JSValueToNumber(ctx, argv[0], NULL);
            
            int32_t incremented = OSAtomicIncrement32(&counter);
            
            NSString *str = [NSString stringWithFormat:@"timer%d", incremented];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                [ABYUtils evaluateScript:[NSString stringWithFormat:@"runTimeout(\"%@\");", str] inContext:weakSelf.context];
            });
            
            JSStringRef strRef = JSStringCreateWithCFString((__bridge CFStringRef)str);
            JSValueRef rv = JSValueMakeString(ctx, strRef);
            return rv;
        }
        
        return JSValueMakeUndefined(ctx);
    }];
    
    
    [ABYUtils setValue:callbackFunction onObject:JSContextGetGlobalObject(_context) forProperty:@"setTimeoutFn" inContext:_context];
    
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
    
    [ABYUtils setValue:callbackFunction onObject:JSContextGetGlobalObject(_context) forProperty:@"AMBLY_IMPORT_SCRIPT" inContext:_context];
}

-(void)bootstrapWithDepsFilePath:(NSString*)depsFilePath googBasePath:(NSString*)googBasePath
{
    // This implementation mirrors the bootstrapping code that is in -setup
    
    // Setup CLOSURE_IMPORT_SCRIPT
    [ABYUtils evaluateScript:@"CLOSURE_IMPORT_SCRIPT = function(src) { AMBLY_IMPORT_SCRIPT('goog/' + src); return true; }" inContext:_context];
    
    // Load goog base
    NSString *baseScriptString = [NSString stringWithContentsOfFile:googBasePath encoding:NSUTF8StringEncoding error:nil];
     NSAssert(baseScriptString != nil, @"The goog base JavaScript text could not be loaded");
    [ABYUtils evaluateScript:baseScriptString inContext:_context];
    
    // Load the deps file
    NSString *depsScriptString = [NSString stringWithContentsOfFile:depsFilePath encoding:NSUTF8StringEncoding error:nil];
    NSAssert(depsScriptString != nil, @"The deps JavaScript text could not be loaded");
    [ABYUtils evaluateScript:depsScriptString inContext:_context];
    
    [ABYUtils evaluateScript:@"goog.isProvided_ = function(x) { return false; };" inContext:_context];
    
    [ABYUtils evaluateScript:@"goog.require = function (name) { return CLOSURE_IMPORT_SCRIPT(goog.dependencies_.nameToPath[name]); };" inContext:_context];
    
    [ABYUtils evaluateScript:@"goog.require('cljs.core');" inContext:_context];
    
    // TODO Is there a better way for the impl below that avoids making direct calls to
    // ClojureScript compiled artifacts? (Complex and perhaps also fragile).
    
     // redef goog.require to track loaded libs
    [ABYUtils evaluateScript:@"cljs.core._STAR_loaded_libs_STAR_ = new cljs.core.PersistentHashSet(null, new cljs.core.PersistentArrayMap(null, 1, ['cljs.core',null], null), null);\n"
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
     "});" inContext:_context];
}

@end
