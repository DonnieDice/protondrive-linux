import { init, trackEvent } from '@aptabase/electron';
import { appConfig } from '../shared/config/app-config';
import logger from '../shared/utils/logger';

/**
 * Initializes Aptabase for analytics if an APP_KEY is provided in the configuration.
 * Should be called once in the main process during application startup.
 */
export const initializeAnalytics = (): void => {
  if (appConfig.APTABASE_APP_KEY) {
    init(appConfig.APTABASE_APP_KEY);
    logger.info('Aptabase analytics initialized.');
  } else {
    logger.warn('APTABASE_APP_KEY is not set. Analytics will be disabled.');
  }
};

/**
 * Tracks a custom event with Aptabase.
 * Events are only tracked if Aptabase has been initialized (i.e., APTABASE_APP_KEY is set).
 *
 * @param eventName The name of the event to track.
 * @param props Optional properties to associate with the event.
 */
export const recordAnalyticsEvent = (eventName: string, props?: Record<string, string>): void => {
  if (appConfig.APTABASE_APP_KEY) {
    trackEvent(eventName, props);
    logger.debug(`Aptabase event recorded: ${eventName}`, props);
  } else {
    logger.debug(`Aptabase event not recorded (analytics disabled): ${eventName}`);
  }
};
