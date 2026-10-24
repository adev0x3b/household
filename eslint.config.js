import js from "@eslint/js"
import globals from "globals"

export default [
  js.configs.recommended,
  {
    files: ["app/javascript/**/*.js"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: globals.browser
    },
    rules: {
      // A body that spans more than one line gets braces, so a statement
      // added under an `if` can't silently fall outside it.
      curly: ["error", "multi-line"],
      // A leading underscore marks a parameter or caught error that is
      // deliberately unused, as in Ruby.
      "no-unused-vars": ["error", { argsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_" }]
    }
  },
  {
    // The unit tests run under Node's own test runner.
    files: ["test/javascript/**/*.js"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: globals.node
    }
  },
  {
    // The tests that draw on a page (the controllers', an uploader row's, the
    // focus keeper's) also have the page's globals, which
    // test/javascript/support/dom.js sets from jsdom.
    files: [
      "test/javascript/controllers/**/*.js",
      "test/javascript/uploader/row.test.js",
      "test/javascript/helpers/focus_keeper.test.js",
      "test/javascript/support/stimulus.js"
    ],
    languageOptions: {
      globals: { ...globals.node, ...globals.browser }
    }
  }
]
