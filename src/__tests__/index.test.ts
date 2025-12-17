/**
 * Tests for react-native-jsc-sandbox TypeScript interface
 *
 * These tests mock the JSI module to verify the TypeScript interface works correctly.
 * Real JSI tests require a React Native environment - see examples/RealJSITest.tsx
 */

import { beforeEach, describe, expect, mock, test } from 'bun:test';
import type { JSCSandboxContext, JSCSandboxModule, JSCSandboxRuntime } from '../index';
import { getJSCSandboxModule, isJSCSandboxAvailable } from '../index';

// Create a mock JSI module with isolated contexts
function createMockJSIModule(): JSCSandboxModule & { isAvailable(): boolean } {
  const createMockContext = (): JSCSandboxContext => {
    const storage = new Map<string, unknown>();

    return {
      eval: mock((code: string) => {
        if (code === '1 + 2') return 3;
        if (code === '2 * 3') return 6;
        if (code === '"hello"') return 'hello';
        if (code === '[1, 2, 3]') return [1, 2, 3];
        if (code === '({x: 1})') return { x: 1 };
        if (code === 'testVar') return storage.get('testVar');
        if (code === 'throw new Error("test")') throw new Error('test');
        return undefined;
      }),
      setGlobal: mock((name: string, value: unknown) => {
        storage.set(name, value);
      }),
      getGlobal: mock((name: string) => storage.get(name)),
      dispose: mock(() => storage.clear()),
    };
  };

  const mockRuntime: JSCSandboxRuntime = {
    createContext: mock(() => createMockContext()),
    dispose: mock(() => {}),
  };

  return {
    createRuntime: mock(() => mockRuntime),
    isAvailable: mock(() => true),
  };
}

describe('JSCSandbox Interface', () => {
  let mockModule: ReturnType<typeof createMockJSIModule>;

  beforeEach(() => {
    mockModule = createMockJSIModule();
    (globalThis as Record<string, unknown>).__JSCSandboxJSI = mockModule;
  });

  test('isJSCSandboxAvailable returns true when module exists', () => {
    expect(isJSCSandboxAvailable()).toBe(true);
  });

  test('isJSCSandboxAvailable returns false when module missing', () => {
    delete (globalThis as Record<string, unknown>).__JSCSandboxJSI;
    expect(isJSCSandboxAvailable()).toBe(false);
  });

  test('getJSCSandboxModule returns module when available', () => {
    const module = getJSCSandboxModule();
    expect(module).not.toBeNull();
    expect(typeof module?.createRuntime).toBe('function');
  });

  test('getJSCSandboxModule returns null when not available', () => {
    delete (globalThis as Record<string, unknown>).__JSCSandboxJSI;
    expect(getJSCSandboxModule()).toBeNull();
  });
});

describe('Runtime and Context', () => {
  let mockModule: ReturnType<typeof createMockJSIModule>;

  beforeEach(() => {
    mockModule = createMockJSIModule();
    (globalThis as Record<string, unknown>).__JSCSandboxJSI = mockModule;
  });

  test('createRuntime returns runtime with methods', () => {
    const runtime = mockModule.createRuntime();
    expect(typeof runtime.createContext).toBe('function');
    expect(typeof runtime.dispose).toBe('function');
  });

  test('createContext returns context with methods', () => {
    const runtime = mockModule.createRuntime();
    const context = runtime.createContext();
    expect(typeof context.eval).toBe('function');
    expect(typeof context.setGlobal).toBe('function');
    expect(typeof context.getGlobal).toBe('function');
    expect(typeof context.dispose).toBe('function');
  });

  test('eval returns result', () => {
    const runtime = mockModule.createRuntime();
    const context = runtime.createContext();
    expect(context.eval('1 + 2')).toBe(3);
  });

  test('setGlobal and getGlobal work', () => {
    const runtime = mockModule.createRuntime();
    const context = runtime.createContext();
    context.setGlobal('testValue', 42);
    expect(context.getGlobal('testValue')).toBe(42);
  });

  test('eval throws on error', () => {
    const runtime = mockModule.createRuntime();
    const context = runtime.createContext();
    expect(() => context.eval('throw new Error("test")')).toThrow('test');
  });

  test('contexts are isolated', () => {
    const runtime = mockModule.createRuntime();
    const ctx1 = runtime.createContext();
    const ctx2 = runtime.createContext();

    ctx1.setGlobal('value', 'ctx1');
    ctx2.setGlobal('value', 'ctx2');

    expect(ctx1.getGlobal('value')).toBe('ctx1');
    expect(ctx2.getGlobal('value')).toBe('ctx2');
  });
});

describe('Type compatibility', () => {
  test('JSCSandboxContext interface is correct', () => {
    const context: JSCSandboxContext = {
      eval: () => undefined,
      setGlobal: () => {},
      getGlobal: () => undefined,
      dispose: () => {},
    };
    expect(typeof context.eval).toBe('function');
    expect(typeof context.setGlobal).toBe('function');
    expect(typeof context.getGlobal).toBe('function');
    expect(typeof context.dispose).toBe('function');
  });

  test('JSCSandboxRuntime interface is correct', () => {
    const runtime: JSCSandboxRuntime = {
      createContext: () => ({
        eval: () => undefined,
        setGlobal: () => {},
        getGlobal: () => undefined,
        dispose: () => {},
      }),
      dispose: () => {},
    };
    expect(typeof runtime.createContext).toBe('function');
    expect(typeof runtime.dispose).toBe('function');
  });

  test('JSCSandboxModule interface is correct', () => {
    const module: JSCSandboxModule = {
      createRuntime: () => ({
        createContext: () => ({
          eval: () => undefined,
          setGlobal: () => {},
          getGlobal: () => undefined,
          dispose: () => {},
        }),
        dispose: () => {},
      }),
    };
    expect(typeof module.createRuntime).toBe('function');
  });
});
