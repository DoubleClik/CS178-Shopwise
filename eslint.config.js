// eslint.config.mjs

export default [
  // 1) Tell ESLint what to ignore
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'build/**',
      '.husky/**',
      'sanityCheckerCrap/**', // ignore your sanity scripts; remove if you want them linted
    ],
  },

  // 2) Main config for your JS files
  {
    files: ['**/*.js', '**/*.mjs'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        Buffer: 'readonly',
        process: 'readonly',
        module: 'readonly',
        console: 'readonly',
      },
    },
    rules: {
      // Just warn for unused vars so lint doesn’t block commits
      'no-unused-vars': 'warn',

      // Turn off no-undef so Node globals don’t explode
      'no-undef': 'off',
    },
  },
];
