import PQueue from 'p-queue';
import logger from '../shared/utils/logger';

// According to GEMINI.md, the rate limit is 10 requests/second.
// This means a minimum interval of 100ms between requests.
const API_RATE_LIMIT_INTERVAL_MS = 100;
const API_CONCURRENCY_LIMIT = 5; // A reasonable default concurrency for API calls

/**
 * A queue for managing API requests, ensuring they adhere to rate limits and concurrency constraints.
 * This prevents overwhelming the API and handles backpressure gracefully.
 */
const apiQueue = new PQueue({
  intervalCap: 1, // Allow 1 task per interval
  interval: API_RATE_LIMIT_INTERVAL_MS, // 100ms interval for 10 requests/second
  concurrency: API_CONCURRENCY_LIMIT, // Number of concurrent tasks
  autoStart: true,
});

// Log queue events for monitoring and debugging
apiQueue.on('add', () => {
  logger.debug(`API Queue: Task added. Size: ${apiQueue.size}, Pending: ${apiQueue.pending}`);
});

apiQueue.on('active', () => {
  logger.debug(`API Queue: Task started. Size: ${apiQueue.size}, Pending: ${apiQueue.pending}`);
});

apiQueue.on('next', () => {
  logger.debug(`API Queue: Task completed. Size: ${apiQueue.size}, Pending: ${apiQueue.pending}`);
});

apiQueue.on('empty', () => {
  logger.debug('API Queue: Empty.');
});

apiQueue.on('idle', () => {
  logger.debug('API Queue: Idle.');
});

apiQueue.on('error', (error) => {
  logger.error('API Queue: An error occurred in a queued task.', error);
});

/**
 * Adds an asynchronous task to the API queue.
 * The task will be executed when the queue's concurrency and rate limits allow.
 *
 * @param task - An asynchronous function to be executed.
 * @returns A Promise that resolves with the result of the task.
 */
export const enqueueApiCall = async <T>(task: () => Promise<T>): Promise<T> => {
  return apiQueue.add(task);
};

/**
 * Returns the current size of the API queue (number of pending tasks).
 * @returns The number of tasks currently in the queue.
 */
export const getApiQueueSize = (): number => {
  return apiQueue.size;
};

/**
 * Returns the number of tasks currently running.
 * @returns The number of active tasks.
 */
export const getApiQueuePending = (): number => {
  return apiQueue.pending;
};

/**
 * Clears all pending tasks from the queue.
 */
export const clearApiQueue = (): void => {
  apiQueue.clear();
  logger.info('API Queue: All pending tasks cleared.');
};

/**
 * Pauses the API queue, preventing new tasks from starting.
 */
export const pauseApiQueue = (): void => {
  apiQueue.pause();
  logger.info('API Queue: Paused.');
};

/**
 * Resumes the API queue, allowing new tasks to start.
 */
export const resumeApiQueue = (): void => {
  apiQueue.start();
  logger.info('API Queue: Resumed.');
};
