import { expect, test } from 'vitest'

// Multiple assertions in one test (violates A04 property 1: isolated assertions)
// Uses expect(result).toBe(...) with truthy comparisons instead of readable-diff matchers
// Test name is not descriptive (violates A04 property 2)
test('testHello', () => {
  const result = 42
  expect(result).toBeTruthy()               // hides the actual value on failure
  expect(result > 40).toBe(true)            // boolean expression matcher — A04 property 3 fail
  expect(new Date().getFullYear()).toBeGreaterThan(2020)  // wall-clock — A04 property 4 fail
})

// One well-written test to show a contrast
test('greet_returnsHello_whenNameProvided', () => {
  const name = 'world'
  const greeting = `Hello, ${name}`
  expect(greeting).toEqual('Hello, world')
})
