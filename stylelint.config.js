// Stylelint checks the stylesheets for mistakes and naming; Prettier owns
// their formatting, so no rule here is about layout.
export default {
  extends: ["stylelint-config-standard-scss"],
  rules: {
    // Class names are BEM in kebab-case: block__element--modifier.
    "selector-class-pattern": [
      "^[a-z][a-z0-9]*(-[a-z0-9]+)*(__[a-z0-9]+(-[a-z0-9]+)*)?(--[a-z0-9]+(-[a-z0-9]+)*)?$",
      { message: (selector) => `Expected class selector "${selector}" to be BEM in kebab-case` }
    ],
    // Media queries keep min-width and max-width: the range syntax needs
    // Safari 16.4, and the app is used on phones that update slowly.
    "media-feature-range-notation": "prefix",
    // Safari before 18 only blurs behind an element with the prefixed name.
    "property-no-vendor-prefix": [true, { ignoreProperties: ["-webkit-backdrop-filter"] }],
    // An empty comment line separates paragraphs inside a longer comment.
    "scss/comment-no-empty": null,
    // Prettier breaks long expressions after an operator.
    "scss/operator-no-newline-after": null,
    // Every colour is a token: a partial names one from _variables.scss and
    // makes it translucent with tint(), tint-var() or glass(). Writing a
    // colour or an alpha in place puts it outside the palette and its
    // measured contrast.
    "color-no-hex": true,
    "color-named": "never",
    "function-disallowed-list": [
      "rgb",
      "rgba",
      "hsl",
      "hsla",
      "hwb",
      "lab",
      "lch",
      "oklab",
      "oklch",
      "color",
      "color-mix"
    ]
  },
  overrides: [
    {
      // The palette itself, and the functions that make a token translucent.
      files: ["app/assets/stylesheets/_variables.scss"],
      rules: {
        "color-no-hex": null,
        "color-named": null,
        "function-disallowed-list": null
      }
    }
  ]
}
