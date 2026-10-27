/* eslint-disable perfectionist/sort-objects */
/**
 * @filename: lint-staged.config.js
 * @type {import('lint-staged').Configuration}
 */

export default {
  '*': ['secretlint'],
  '*.md': ['prettier --check'],
};
