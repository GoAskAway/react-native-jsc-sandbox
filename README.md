# react-native-jsc-sandbox

JavaScriptCore sandbox for React Native - isolated JS execution on all Apple platforms.

## Features

- **True Sandboxing**: Each context runs in its own isolated `JSContext`
- **Native Performance**: Uses Apple's built-in JavaScriptCore engine
- **Zero Dependencies**: JSC is included in all Apple platforms - no extra binaries
- **Callback Support**: Pass functions to sandbox via callback proxy mechanism
- **Timeout Support**: Configure execution timeout for protection against infinite loops
- **Thread Safe**: All operations run on a dedicated serial queue
- **Proper Lifecycle**: Reference-counted cleanup with dispose() methods

## Platform Support

| Platform  | Support | Min Version | Notes |
|-----------|---------|-------------|-------|
| iOS       | ✅      | 13.0        | System JSC |
| macOS     | ✅      | 10.15       | System JSC |
| tvOS      | ✅      | 13.0        | System JSC |
| watchOS   | ✅      | 6.0         | System JSC |
| visionOS  | ✅      | 1.0         | System JSC |
| Android   | ❌      | -           | Use [react-native-quickjs](https://github.com/bojie-liu/react-native-quickjs) |

## Installation

```bash
# Using npm
npm install github:GoAskAway/react-native-jsc-sandbox

# Using yarn
yarn add github:GoAskAway/react-native-jsc-sandbox

# Using bun
bun add github:GoAskAway/react-native-jsc-sandbox
```

### CocoaPods

```bash
cd ios && pod install
# or for macOS
cd macos && pod install
```

## Usage

### Basic Example

```typescript
import { JSCSandboxProvider } from 'react-native-jsc-sandbox';

// Create a provider
const provider = new JSCSandboxProvider();

// Create a runtime and context
const runtime = provider.createRuntime();
const context = runtime.createContext();

// Execute code in the sandbox
const result = await context.evalAsync('1 + 2 + 3');
console.log(result); // 6

// Clean up (important!)
context.dispose();
runtime.dispose();
provider.dispose();
```

### Working with Globals

```typescript
const context = runtime.createContext();

// Set a global variable (returns Promise for proper sequencing)
await context.setGlobal('config', { debug: true, version: '1.0.0' });

// Access it in sandboxed code
await context.evalAsync(`
  console.log(config.version);  // "1.0.0"
`);

// Get a global from the sandbox
const result = await context.getGlobal('config');
```

### Callback Functions

```typescript
const context = runtime.createContext();

// Register a callback function
await context.setGlobal('sendToHost', (message, data) => {
  console.log('Received from sandbox:', message, data);
});

// Call it from sandboxed code
await context.evalAsync(`
  sendToHost('hello', { count: 42 });
`);
```

### Multiple Isolated Contexts

```typescript
const context1 = runtime.createContext();
const context2 = runtime.createContext();

// Each context is completely isolated
await context1.evalAsync('var secret = "context1"');
await context2.evalAsync('var secret = "context2"');

// They cannot see each other's variables
const val1 = await context1.evalAsync('secret'); // "context1"
const val2 = await context2.evalAsync('secret'); // "context2"
```

### With Options

```typescript
const provider = new JSCSandboxProvider({
  timeout: 5000,          // Execution timeout in ms
  memoryLimit: 50000000,  // Memory limit in bytes (monitored, not enforced)
  debug: false,           // Enable debug logging
  maxCodeLength: 1024 * 1024,  // Max code size (default: 10MB)
});
```

### Performance Monitoring

```typescript
const provider = new JSCSandboxProvider({
  onMetrics: (metrics) => {
    console.log(`${metrics.operation}: ${metrics.durationMs}ms`);

    // Track slow operations
    if (metrics.durationMs > 100) {
      analytics.track('slow_sandbox_operation', metrics);
    }
  },
});
```

The metrics object includes:
- `operation`: 'eval' | 'setGlobal' | 'getGlobal' | 'registerCallback'
- `contextId`: The context identifier
- `durationMs`: Operation duration in milliseconds
- `success`: Whether the operation succeeded
- `error`: Error message if failed
- `codeLength`: Code length for eval operations
- `timestamp`: Operation start timestamp

### Interrupt Handler

```typescript
const context = runtime.createContext();

// Set up an interrupt handler (checked before each eval)
let shouldCancel = false;
context.setInterruptHandler?.(() => shouldCancel);

// Later, to cancel:
shouldCancel = true;

// Next evalAsync will throw "Execution interrupted by handler"
```

## API Reference

### `JSCSandboxProvider`

Main class for creating sandbox runtimes.

```typescript
new JSCSandboxProvider(options?: JSCSandboxOptions)
```

**Options:**
- `timeout?: number` - Execution timeout in milliseconds (1-600000)
- `memoryLimit?: number` - Memory limit in bytes (monitored, not enforced - JSC limitation)
- `debug?: boolean` - Enable debug logging (default: false)
- `maxCodeLength?: number` - Maximum code length in characters (default: 10MB)
- `maxGlobalNameLength?: number` - Maximum global variable name length (default: 256)
- `onMetrics?: (metrics: JSCSandboxMetrics) => void` - Performance metrics callback

**Methods:**
- `createRuntime(): JSCSandboxRuntime` - Create a new runtime
- `dispose(): void` - Dispose provider and all its runtimes

### `JSCSandboxRuntime`

A runtime that can create multiple isolated contexts.

**Methods:**
- `createContext(): JSCSandboxContext` - Create a new isolated context
- `dispose(): void` - Dispose runtime and all contexts

### `JSCSandboxContext`

An isolated JavaScript execution context.

**Methods:**
- `evalAsync(code: string): Promise<unknown>` - Evaluate JS code
- `setGlobal(name: string, value: unknown): Promise<void>` - Set a global variable
- `getGlobal(name: string): Promise<unknown>` - Get a global variable
- `dispose(): void` - Dispose the context
- `setInterruptHandler?(handler: () => boolean): void` - Set interrupt handler (optional)
- `clearInterruptHandler?(): void` - Clear interrupt handler (optional)

### Utility Functions

```typescript
// Check if native module is available
isJSCSandboxAvailable(): boolean

// Convenience function to create provider
createJSCSandboxProvider(options?: JSCSandboxOptions): JSEngineProvider
```

## Lifecycle Management

Proper cleanup is important to prevent memory leaks:

```typescript
const provider = new JSCSandboxProvider();

try {
  const runtime = provider.createRuntime();
  const context = runtime.createContext();

  // ... use the context ...

  context.dispose();  // Dispose context first
  runtime.dispose();  // Then runtime
} finally {
  provider.dispose(); // Always dispose provider
}
```

When you dispose:
- **Context**: Cleans up callbacks, releases JSContext
- **Runtime**: Disposes all its contexts
- **Provider**: Disposes all runtimes, cleans up event listeners

## Security

Each `JSContext` created by this library is completely isolated:

- No access to host application globals
- No access to other sandbox contexts
- No access to native modules
- No file system or network access (unless explicitly provided)

The only way to share data with sandboxed code is through `setGlobal()`.

## How It Works

```
┌─────────────────────────────────────────────┐
│ Host Application (React Native)             │
│   - Full access to native modules           │
│   - File system, network, etc.              │
└─────────────────────────────────────────────┘
        ╳ No access (unless via setGlobal)
┌─────────────────┐  ┌─────────────────┐
│ JSContext A     │  │ JSContext B     │
│ (Sandbox 1)     │  │ (Sandbox 2)     │
│ - Own globals   │  │ - Own globals   │
│ - Own scope     │  │ - Own scope     │
└─────────────────┘  └─────────────────┘
        ╳ No cross-context access
```

### Callback Proxy Mechanism

Since functions cannot be serialized across the React Native bridge, this library implements a callback proxy:

1. When `setGlobal()` is called with a function:
   - The function is registered in a Host-side callback registry
   - A proxy function is injected into the sandbox via native code

2. When the sandbox calls the proxy function:
   - Native layer sends an event to Host JS via `RCTEventEmitter`
   - Host JS looks up the real callback and invokes it with all arguments

## Comparison with Alternatives

| Feature | jsc-sandbox | quickjs | hermes |
|---------|-------------|---------|--------|
| iOS     | ✅ Native   | ✅ Bundled | ✅ |
| macOS   | ✅ Native   | ✅ Bundled | ❌ |
| tvOS    | ✅ Native   | ❓ | ❌ |
| watchOS | ✅ Native   | ❓ | ❌ |
| visionOS| ✅ Native   | ❓ | ❌ |
| Android | ❌          | ✅ Bundled | ✅ |
| Size    | 0 KB        | ~700 KB | ~2 MB |
| Engine  | JSC         | QuickJS | Hermes |

**When to use jsc-sandbox:**
- Building for Apple platforms
- Want zero additional binary size
- Need true sandboxing for untrusted code

**When to use quickjs:**
- Need Android support
- Cross-platform requirements

## Contributing

Contributions are welcome! Please open an issue or PR on GitHub.

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.
