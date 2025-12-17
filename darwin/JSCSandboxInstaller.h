#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Install JSCSandbox JSI bindings into the given runtime.
 * Call this from your AppDelegate if you need manual installation.
 *
 * Note: For React Native 0.73+, prefer using ensureJSCSandboxInstalled() from JS
 * which triggers the TurboModule to install JSI bindings automatically.
 */
void JSCSandboxInstall(void* runtime);

#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
#import <React/RCTBridge.h>

@interface JSCSandboxInstaller : NSObject

/**
 * Manually install JSI bindings with a bridge (legacy architecture).
 * For new architecture apps, use ensureJSCSandboxInstalled() from JS instead.
 *
 * @param bridge The RCTBridge instance
 */
+ (void)installWithBridge:(RCTBridge *)bridge;

@end
#endif
