#pragma once

#import <React/RCTBridgeModule.h>
#import <ReactCommon/RCTTurboModuleWithJSIBindings.h>

/**
 * RNJSCSandboxModule - TurboModule that installs JSI bindings
 *
 * Implements RCTTurboModuleWithJSIBindings to get direct access to JSI runtime
 * in the new architecture. This is the recommended way to install custom JSI
 * bindings in React Native 0.73+.
 */
@interface RNJSCSandboxModule : NSObject <RCTBridgeModule, RCTTurboModuleWithJSIBindings>
@end
