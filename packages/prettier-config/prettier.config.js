export default {
  printWidth: 120,
  tabWidth: 2,
  semi: true,
  singleQuote: true,
  jsxSingleQuote: false,
  bracketSpacing: true,
  bracketSameLine: true,
  arrowParens: "always",
  trailingComma: "es5",
  overrides: [
    {
      files: ["*.yml", "*.yaml"],
      options: {
        bracketSpacing: false,
      },
    },
  ],
};
