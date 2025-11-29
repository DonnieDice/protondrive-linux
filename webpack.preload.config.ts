import type { Configuration } from 'webpack';
import { rules } from './webpack.rules'; // Assuming rules are shared
import { plugins } from './webpack.plugins'; // Assuming plugins are shared

export const preloadConfig: Configuration = {
  module: {
    rules: [
      ...rules, // Include general rules, ensure ts-loader is applied
      // Add specific rules for preload if needed, e.g., to handle Node.js specific modules
    ],
  },
  plugins, // Include plugins, if any are relevant for preload
  resolve: {
    extensions: ['.js', '.ts', '.jsx', '.tsx', '.css'],
    mainFields: ['module', 'main'], // Help Webpack find correct entry points
  },
  target: 'electron-preload', // Crucial for preload scripts
  node: {
    // Explicitly set Node.js globals to 'false' to ensure they are handled by Electron
    // and not polyfilled by Webpack in a way that conflicts with contextIsolation
    __dirname: false,
    __filename: false,
  },
  optimization: {
    minimize: false, // Easier debugging
  },
};