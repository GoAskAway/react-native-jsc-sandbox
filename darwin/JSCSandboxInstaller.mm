#import "JSCSandboxInstaller.h"
#import "JSCSandboxJSI.h"

#import <React/RCTBridge+Private.h>
#import <jsi/jsi.h>

using namespace facebook;

// Track if JSI has been installed to avoid double-installation
static bool sJSIInstalled = false;
static std::mutex sInstallMutex;

extern "C" void JSCSandboxInstall(void* runtime) {
    std::lock_guard<std::mutex> lock(sInstallMutex);

    if (sJSIInstalled) {
        NSLog(@"[JSCSandbox] JSI already installed, skipping");
        return;
    }

    if (runtime == nullptr) {
        NSLog(@"[JSCSandbox] Cannot install: runtime is null");
        return;
    }

    jsi::Runtime* jsiRuntime = static_cast<jsi::Runtime*>(runtime);
    jsc_sandbox::JSCSandboxModule::install(*jsiRuntime);
    sJSIInstalled = true;
    NSLog(@"[JSCSandbox] JSI bindings installed via manual call");
}

@implementation JSCSandboxInstaller

+ (void)installWithBridge:(RCTBridge *)bridge {
    std::lock_guard<std::mutex> lock(sInstallMutex);

    if (sJSIInstalled) {
        NSLog(@"[JSCSandbox] JSI already installed, skipping");
        return;
    }

    if (!bridge) {
        NSLog(@"[JSCSandbox] Cannot install: bridge is nil");
        return;
    }

    RCTCxxBridge *cxxBridge = (RCTCxxBridge *)bridge;
    if (!cxxBridge.runtime) {
        NSLog(@"[JSCSandbox] Warning: Bridge runtime not ready yet");
        // Retry after a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self installWithBridge:bridge];
        });
        return;
    }

    jsi::Runtime* runtime = (jsi::Runtime*)cxxBridge.runtime;
    jsc_sandbox::JSCSandboxModule::install(*runtime);
    sJSIInstalled = true;
    NSLog(@"[JSCSandbox] JSI bindings installed via bridge");
}

@end
