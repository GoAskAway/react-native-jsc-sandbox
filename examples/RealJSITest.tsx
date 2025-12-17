/**
 * JSCSandbox Real JSI Test
 *
 * Copy this file into any React Native project to test JSCSandbox JSI bindings.
 *
 * Usage:
 *   1. Install: npm install react-native-jsc-sandbox
 *   2. iOS: cd ios && pod install
 *   3. Copy this file to your project
 *   4. Import and render <JSCSandboxTest />
 */

import { useEffect, useState } from 'react';
import { Alert, Button, ScrollView, StyleSheet, Text, View } from 'react-native';
import {
  ensureJSCSandboxInstalled,
  getJSCSandboxModule,
  isJSCSandboxAvailable,
} from 'react-native-jsc-sandbox';

interface TestResult {
  name: string;
  passed: boolean;
  result?: unknown;
  error?: string;
}

export function JSCSandboxTest() {
  const [status, setStatus] = useState('Initializing...');
  const [results, setResults] = useState<TestResult[]>([]);

  useEffect(() => {
    ensureJSCSandboxInstalled().then((ok) => {
      setStatus(ok ? 'JSI Ready ✅' : 'JSI Not Available ❌');
    });
  }, []);

  const runTests = () => {
    if (!isJSCSandboxAvailable()) {
      Alert.alert('Error', 'JSI not available');
      return;
    }

    const module = getJSCSandboxModule();
    if (!module) {
      Alert.alert('Error', 'Module not available');
      return;
    }
    const runtime = module.createRuntime({ timeout: 5000 });
    const ctx = runtime.createContext();
    const tests: TestResult[] = [];

    // Test suite
    const testCases: Array<{ name: string; fn: () => unknown; expected: unknown }> = [
      { name: 'Arithmetic', fn: () => ctx.eval('1 + 2 * 3'), expected: 7 },
      { name: 'String', fn: () => ctx.eval('"hello"'), expected: 'hello' },
      { name: 'Array', fn: () => ctx.eval('[1,2,3].length'), expected: 3 },
      { name: 'Object', fn: () => (ctx.eval('({x:1})') as { x: number }).x, expected: 1 },
      { name: 'Function', fn: () => ctx.eval('(function(a,b){return a+b})(2,3)'), expected: 5 },
      {
        name: 'setGlobal',
        fn: () => {
          ctx.setGlobal('x', 42);
          return ctx.getGlobal('x');
        },
        expected: 42,
      },
      { name: 'Loop', fn: () => ctx.eval('for(var i=0,s=0;i<10;i++)s+=i;s'), expected: 45 },
      { name: 'JSON', fn: () => ctx.eval('JSON.parse("{\\"a\\":1}").a'), expected: 1 },
      { name: 'Math', fn: () => ctx.eval('Math.max(1,5,3)'), expected: 5 },
      {
        name: 'Closure',
        fn: () => ctx.eval('(function(){var x=1;return function(){return++x}})()()'),
        expected: 2,
      },
    ];

    for (const tc of testCases) {
      try {
        const result = tc.fn();
        tests.push({ name: tc.name, passed: result === tc.expected, result });
      } catch (e) {
        tests.push({ name: tc.name, passed: false, error: String(e) });
      }
    }

    ctx.dispose();
    runtime.dispose();
    setResults(tests);

    const passed = tests.filter((t) => t.passed).length;
    Alert.alert('Results', `${passed}/${tests.length} tests passed`);
  };

  return (
    <ScrollView style={styles.container}>
      <Text style={styles.title}>JSCSandbox Test</Text>
      <Text style={styles.status}>{status}</Text>
      <Button title="Run Tests" onPress={runTests} />
      {results.length > 0 && (
        <View style={styles.results}>
          {results.map((t, i) => (
            <Text key={i} style={t.passed ? styles.pass : styles.fail}>
              {t.passed ? '✅' : '❌'} {t.name}
              {t.error ? ` - ${t.error}` : ''}
            </Text>
          ))}
        </View>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 20 },
  title: { fontSize: 24, fontWeight: 'bold', marginBottom: 10 },
  status: { fontSize: 16, marginBottom: 20 },
  results: { marginTop: 20 },
  pass: { color: 'green', marginVertical: 2 },
  fail: { color: 'red', marginVertical: 2 },
});

export default JSCSandboxTest;
