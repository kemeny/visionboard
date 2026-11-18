import nextVitals from 'eslint-config-next/core-web-vitals'
import nextTs from 'eslint-config-next/typescript'

const config = [
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      // React Compiler checks: the app isn't compiled with it yet, so these
      // are advice for now rather than errors
      'react-hooks/set-state-in-effect': 'warn',
      'react-hooks/refs': 'warn',
      'react-hooks/purity': 'warn',
      'react-hooks/immutability': 'warn',
      'react-hooks/preserve-manual-memoization': 'warn',
      // let { a, b } = ... is fine when only one of them is reassigned
      'prefer-const': ['error', { destructuring: 'all' }],
    },
  },
  {
    ignores: ['.next/**', 'node_modules/**', 'worker/**', 'ios/**', 'public/**', 'next-env.d.ts'],
  },
]

export default config
