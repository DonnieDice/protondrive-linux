import type { Configuration } from 'webpack';
import { rules } from './webpack.rules';
import { plugins } from './webpack.plugins';

export const rendererConfig: Configuration = {
  module: {
    rules: [
      ...rules, // Include general rules, ensure ts-loader and CSS loaders are applied
    ],
  },
  plugins,
  resolve: {
    extensions: ['.js', '.ts', '.jsx', '.tsx', '.css'],
  },
  target: 'electron-renderer', // Explicitly set target for renderer
  node: {
    // Explicitly disable Node.js globals for the renderer process as nodeIntegration is false
    __dirname: false,
    __filename: false,
    global: false,
  },
  optimization: {
    minimize: false, // Easier debugging
  },
};