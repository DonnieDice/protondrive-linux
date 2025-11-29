import winston from 'winston';
import path from 'path';
import { appConfig } from '../config/app-config';

// Determine the logs directory based on the environment
const logsDir = process.env.NODE_ENV === 'production'
  ? path.join(process.resourcesPath, 'logs') // In production, logs are in a standard location
  : 'logs'; // In development, logs are in the project root

const { combine, timestamp, printf, colorize, json } = winston.format;

// Custom format for console logging with colors
const consoleFormat = combine(
  colorize(),
  timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  printf(({ level, message, timestamp: ts, ...meta }) => {
    const metaString = Object.keys(meta).length ? JSON.stringify(meta) : '';
    return `${ts} ${level}: ${message} ${metaString}`;
  })
);

// JSON format for file logging
const fileFormat = combine(
  timestamp(),
  json()
);

const transports: winston.transport[] = [];

// In development, we log to the console with a pretty, colorized format
if (appConfig.NODE_ENV === 'development') {
  transports.push(new winston.transports.Console({
    format: consoleFormat,
  }));
} else {
  // In production, we log to files with a structured JSON format
  transports.push(
    new winston.transports.File({
      filename: path.join(logsDir, 'error.log'),
      level: 'error',
      format: fileFormat,
      maxsize: 5 * 1024 * 1024, // 5MB
      maxFiles: 5,
      tailable: true,
    }),
    new winston.transports.File({
      filename: path.join(logsDir, 'combined.log'),
      format: fileFormat,
      maxsize: 5 * 1024 * 1024, // 5MB
      maxFiles: 5,
      tailable: true,
    })
  );
}

const validWinstonLevels = ['error', 'warn', 'info', 'http', 'verbose', 'debug', 'silly'];
const resolvedLogLevel = validWinstonLevels.includes(appConfig.LOG_LEVEL)
  ? appConfig.LOG_LEVEL
  : 'info';

const logger = winston.createLogger({
  level: resolvedLogLevel,
  format: fileFormat, // Default format for the logger
  transports,
  exitOnError: false, // Do not exit on handled exceptions
});




export default logger;
