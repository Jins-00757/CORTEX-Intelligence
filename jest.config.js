module.exports = {
  testEnvironment: "jsdom",
  transform: {
    "^.+\\.js$": "babel-jest",
  },
  moduleNameMapper: {
    "^c/(.*)$": "<rootDir>/force-app/main/default/lwc/$1/$1.js",
    "^lightning/(.*)$": "<rootDir>/__mocks__/lightning/$1.js",
  },
  setupFilesAfterEnv: ["<rootDir>/__mocks__/setup.js"],
  collectCoverageFrom: [
    "force-app/main/default/**/*.js",
    "!force-app/main/default/**/*.test.js",
    "!force-app/main/default/**/__tests__/**",
  ],
  coverageThreshold: {
    global: {
      branches: 85,
      functions: 85,
      lines: 85,
      statements: 85,
    },
  },
};
