import baseConfig from './jest.config.mjs';

export default {
  ...baseConfig,
  transform: {
    '^.+\\.tsx?$': [
      'ts-jest',
      {
        // The imported legacy WMS schema has known TS6133/TS6198 unused-local diagnostics.
        diagnostics: { ignoreCodes: [6133, 6198] },
      },
    ],
  },
};
