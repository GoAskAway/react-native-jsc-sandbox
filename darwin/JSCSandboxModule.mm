#import "JSCSandboxModule.h"
#import "JSCSandboxJSI.h"

#import <React/RCTBridge+Private.h>
#import <ReactCommon/RCTTurboModule.h>
#import <jsi/jsi.h>

using namespace facebook;

// Track if JSI has been installed to avoid double-installation
static bool sJSIInstalled = false;
static std::mutex sInstallMutex;

@implementation RNJSCSandboxModule

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE(RNJSCSandbox)

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (instancetype)init {
    if (self = [super init]) {
        NSLog(@"[JSCSandbox] Module initialized");
    }
    return self;
}

#pragma mark - RCTTurboModuleWithJSIBindings (New Architecture)

/**
 * This method is called by React Native's TurboModule system when the module
 * is loaded in the new architecture. It gives us direct access to the JSI runtime.
 */
- (void)installJSIBindingsWithRuntime:(jsi::Runtime &)runtime
                          callInvoker:(std::shared_ptr<react::CallInvoker>)jsInvoker {
    std::lock_guard<std::mutex> lock(sInstallMutex);

    if (sJSIInstalled) {
        NSLog(@"[JSCSandbox] JSI already installed, skipping");
        return;
    }

    NSLog(@"[JSCSandbox] Installing JSI via TurboModule...");
    jsc_sandbox::JSCSandboxModule::install(runtime);
    sJSIInstalled = true;
    NSLog(@"[JSCSandbox] ✅ JSI bindings installed via TurboModule!");
}

#pragma mark - Legacy Bridge Support (Old Architecture)

/**
 * Fallback for old architecture apps that still use RCTBridge
 */
- (void)setBridge:(RCTBridge *)bridge {
    _bridge = bridge;

    NSLog(@"[JSCSandbox] setBridge called (legacy architecture)");

    // Install JSI in the next run loop to ensure bridge is ready
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installJSIWithBridge:bridge];
    });
}

- (void)installJSIWithBridge:(RCTBridge *)bridge {
    std::lock_guard<std::mutex> lock(sInstallMutex);

    if (sJSIInstalled) {
        NSLog(@"[JSCSandbox] JSI already installed, skipping");
        return;
    }

    RCTCxxBridge *cxxBridge = (RCTCxxBridge *)bridge;

    if (!cxxBridge.runtime) {
        NSLog(@"[JSCSandbox] ⚠️ Runtime not ready, will retry");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self installJSIWithBridge:bridge];
        });
        return;
    }

    jsi::Runtime *runtime = (jsi::Runtime *)cxxBridge.runtime;
    jsc_sandbox::JSCSandboxModule::install(*runtime);
    sJSIInstalled = true;
    NSLog(@"[JSCSandbox] ✅ JSI bindings installed via legacy bridge!");
}

#pragma mark - Exported Methods

/**
 * Export a method to ensure the module gets loaded.
 * Call this from JS to trigger TurboModule initialization.
 */
RCT_EXPORT_METHOD(ensureInstalled:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // By the time this is called, installJSIBindingsWithRuntime should have run
    NSLog(@"[JSCSandbox] ensureInstalled called, JSI installed: %d", sJSIInstalled);
    resolve(@(sJSIInstalled));
}

@end
