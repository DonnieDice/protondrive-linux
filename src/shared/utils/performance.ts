/**
 * Utility functions for performance monitoring and measurement.
 * Adheres to the project's performance budgets defined in docs/architecture/performance-budget.md.
 */

// A simple map to store start times for performance measurements
const performanceMarks = new Map<string, number>();

/**
 * Starts a performance timer for a given mark.
 * @param markName - The unique name for this performance mark.
 */
export const startPerformanceMeasure = (markName: string): void => {
  performanceMarks.set(markName, performance.now());
};

/**
 * Ends a performance timer and returns the elapsed time in milliseconds.
 * If the markName was not started, it returns -1.
 * @param markName - The unique name for the performance mark.
 * @returns The elapsed time in milliseconds, or -1 if the mark was not found.
 */
export const endPerformanceMeasure = (markName: string): number => {
  const startTime = performanceMarks.get(markName);
  if (startTime === undefined) {
    console.warn(`Performance mark "${markName}" was not started.`);
    return -1;
  }
  const endTime = performance.now();
  performanceMarks.delete(markName); // Clean up the mark
  return endTime - startTime;
};

/**
 * Measures the memory usage of the current process.
 * This function is primarily relevant for the main Electron process and Node.js environments.
 * It might not provide detailed metrics for renderer processes directly in the same way.
 * @returns An object containing various memory usage statistics in bytes, or null if not available.
 */
export const getMemoryUsage = (): NodeJS.MemoryUsage | null => {
  if (typeof process !== 'undefined' && process.memoryUsage) {
    return process.memoryUsage();
  }
  console.warn('Memory usage measurement is only available in Node.js environments (main process).');
  return null;
};

/**
 * Converts bytes to a more human-readable format (e.g., KB, MB, GB).
 * @param bytes - The number of bytes to convert.
 * @param decimals - The number of decimal places to include.
 * @returns A string representing the human-readable size.
 */
export const formatBytes = (bytes: number, decimals: number = 2): string => {
  if (bytes === 0) return '0 Bytes';

  const k = 1024;
  const dm = decimals < 0 ? 0 : decimals;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return (bytes / Math.pow(k, i)).toFixed(dm) + ' ' + sizes[i];
};
