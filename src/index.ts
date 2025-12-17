/**
 * react-native-jsc-sandbox
 *
 * JavaScriptCore sandbox for React Native - isolated JS execution on all Apple platforms.
 * Uses JSI for synchronous operations (same interface as react-native-quickjs).
 */

// JSI module is installed as global.__JSCSandboxJSI
declare global {
  // eslint-disable-next-line no-var
  var __JSCSandboxJSI:
    | {
        createRuntime(options?: { timeout?: number }): JSCSandboxRuntime;
        isAvailable(): boolean;
      }
    | undefined;
}

/**
 * A sandboxed JavaScript context (same interface as RNQuickJSContext)
 */
export interface JSCSandboxContext {
  /** Evaluate JavaScript code synchronously */
  eval(code: string): unknown;
  /** Set a global variable (including functions) */
  setGlobal(name: string, value: unknown): void;
  /** Get a global variable */
  getGlobal(name: string): unknown;
  /** Dispose this context */
  dispose(): void;
}

/**
 * A sandbox runtime (same interface as RNQuickJSRuntime)
 */
export interface JSCSandboxRuntime {
  /** Create a new isolated context */
  createContext(): JSCSandboxContext;
  /** Dispose the runtime */
  dispose(): void;
}

/**
 * Module interface (same as RNQuickJSLike)
 */
export interface JSCSandboxModule {
  createRuntime(options?: { timeout?: number }): JSCSandboxRuntime;
}

// Native module interface
interface RNJSCSandboxSpec {
  ensureInstalled(): Promise<boolean>;
}

// Lazy-load react-native to allow testing without RN installed
let _nativeModule: RNJSCSandboxSpec | null | undefined;

function getNativeModule(): RNJSCSandboxSpec | null {
  if (_nativeModule !== undefined) {
    return _nativeModule;
  }

  try {
    // Dynamic require to avoid issues in non-RN environments
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const RN = require('react-native');
    const { NativeModules, TurboModuleRegistry } = RN;

    // Try TurboModuleRegistry first (new architecture)
    try {
      const turboModule = TurboModuleRegistry?.get?.('RNJSCSandbox') as
        | RNJSCSandboxSpec
        | undefined;
      if (turboModule) {
        _nativeModule = turboModule;
        return turboModule;
      }
    } catch {
      // TurboModuleRegistry not available
    }

    // Fall back to NativeModules (legacy architecture)
    _nativeModule = (NativeModules?.RNJSCSandbox as RNJSCSandboxSpec | undefined) ?? null;
    return _nativeModule;
  } catch {
    // react-native not available (e.g., in tests)
    _nativeModule = null;
    return null;
  }
}

/**
 * Ensure the native module is loaded and JSI bindings are installed.
 * Call this once at app startup before using JSCSandbox.
 *
 * @returns Promise that resolves to true if JSI is ready
 */
export async function ensureJSCSandboxInstalled(): Promise<boolean> {
  const nativeModule = getNativeModule();

  if (!nativeModule) {
    return isJSCSandboxAvailable(); // JSI might already be installed
  }

  try {
    // This triggers TurboModule initialization which installs JSI bindings
    const installed = await nativeModule.ensureInstalled();
    return installed && isJSCSandboxAvailable();
  } catch {
    return isJSCSandboxAvailable();
  }
}

/**
 * Check if JSCSandbox JSI is available.
 * Note: Call ensureJSCSandboxInstalled() first to guarantee availability.
 */
export function isJSCSandboxAvailable(): boolean {
  return (
    typeof globalThis.__JSCSandboxJSI !== 'undefined' &&
    typeof globalThis.__JSCSandboxJSI.isAvailable === 'function' &&
    globalThis.__JSCSandboxJSI.isAvailable()
  );
}

/**
 * Get the JSCSandbox module (or null if not available).
 * Note: Call ensureJSCSandboxInstalled() first to guarantee availability.
 */
export function getJSCSandboxModule(): JSCSandboxModule | null {
  if (isJSCSandboxAvailable()) {
    return globalThis.__JSCSandboxJSI as JSCSandboxModule;
  }
  return null;
}

/**
 * Check if we're on an Apple platform where JSCSandbox is supported
 */
export function isApplePlatform(): boolean {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { Platform } = require('react-native');
    return Platform?.OS === 'ios' || Platform?.OS === 'macos';
  } catch {
    return false;
  }
}
