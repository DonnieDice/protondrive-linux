import {
  startPerformanceMeasure,
  endPerformanceMeasure,
  getMemoryUsage,
  formatBytes,
} from '@shared/utils/performance';

describe('performance', () => {
  const originalPerformance = global.performance;
  const originalProcess = global.process;

  beforeAll(() => {
    // Mock global.performance.now() for consistent time measurements
    let mockTime = 0;
    Object.defineProperty(global, 'performance', {
      value: {
        now: jest.fn(() => {
          mockTime += 100; // Simulate time passing
          return mockTime;
        }),
      },
      writable: true,
    });

    // Mock process.memoryUsage() for consistent memory measurements
    Object.defineProperty(global, 'process', {
      value: {
        memoryUsage: jest.fn(() => ({
          rss: 100 * 1024 * 1024, // 100 MB
          heapTotal: 80 * 1024 * 1024, // 80 MB
          heapUsed: 50 * 1024 * 1024, // 50 MB
          external: 10 * 1024 * 1024, // 10 MB
          arrayBuffers: 5 * 1024 * 1024, // 5 MB
        })),
      },
      writable: true,
    });
  });

  afterAll(() => {
    // Restore original global objects
    global.performance = originalPerformance;
    global.process = originalProcess;
  });

  beforeEach(() => {
    // Reset mock values for performance.now() and process.memoryUsage()
    (global.performance.now as jest.Mock).mockClear();
    (global.process.memoryUsage as unknown as jest.Mock).mockClear(); // Cast to unknown first then jest.Mock
    let mockTime = 0; // Reset mock time for each test
    (global.performance.now as jest.Mock).mockImplementation(() => {
        mockTime += 100;
        return mockTime;
    });
  });

  describe('startPerformanceMeasure and endPerformanceMeasure', () => {
    it('should correctly calculate elapsed time for a single mark', () => {
      startPerformanceMeasure('testMark');
      // performance.now() will advance by 100ms on each call
      const duration = endPerformanceMeasure('testMark');
      expect(duration).toBe(100); // 2 calls to performance.now(), start and end
    });

    it('should correctly calculate elapsed time for multiple marks', () => {
      startPerformanceMeasure('mark1');
      startPerformanceMeasure('mark2'); // performance.now() = 100
      
      const duration2 = endPerformanceMeasure('mark2'); // performance.now() = 200
      expect(duration2).toBe(100);

      const duration1 = endPerformanceMeasure('mark1'); // performance.now() = 400
      expect(duration1).toBe(300);
    });

    it('should return -1 if endPerformanceMeasure is called for an unstarted mark', () => {
      const duration = endPerformanceMeasure('nonExistentMark');
      expect(duration).toBe(-1);
    });

    it('should warn if endPerformanceMeasure is called for an unstarted mark', () => {
      const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
      endPerformanceMeasure('anotherUnstartedMark');
      expect(warnSpy).toHaveBeenCalledWith('Performance mark "anotherUnstartedMark" was not started.');
      warnSpy.mockRestore();
    });
  });

  describe('getMemoryUsage', () => {
    it('should return memory usage statistics in a Node.js environment', () => {
      const memory = getMemoryUsage();
      expect(global.process.memoryUsage).toHaveBeenCalledTimes(1);
      expect(memory).toEqual({
        rss: 100 * 1024 * 1024,
        heapTotal: 80 * 1024 * 1024,
        heapUsed: 50 * 1024 * 1024,
        external: 10 * 1024 * 1024,
        arrayBuffers: 5 * 1024 * 1024,
      });
    });

    it('should return null and warn if not in a Node.js environment', () => {
      // Temporarily remove process.memoryUsage
      const tempMemoryUsage = (global.process as any).memoryUsage;
      delete (global.process as any).memoryUsage;
      const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});

      const memory = getMemoryUsage();

      expect(memory).toBeNull();
      expect(warnSpy).toHaveBeenCalledWith('Memory usage measurement is only available in Node.js environments (main process).');
      
      warnSpy.mockRestore();
      (global.process as any).memoryUsage = tempMemoryUsage; // Restore
    });
  });

  describe('formatBytes', () => {
    it('should format bytes to Bytes', () => {
      expect(formatBytes(0)).toBe('0 Bytes');
      expect(formatBytes(500)).toBe('500.00 Bytes');
    });

    it('should format bytes to KB', () => {
      expect(formatBytes(1024)).toBe('1.00 KB');
      expect(formatBytes(1536)).toBe('1.50 KB');
    });

    it('should format bytes to MB', () => {
      expect(formatBytes(1024 * 1024)).toBe('1.00 MB');
      expect(formatBytes(1.5 * 1024 * 1024)).toBe('1.50 MB');
    });

    it('should format bytes to GB', () => {
      expect(formatBytes(1024 * 1024 * 1024)).toBe('1.00 GB');
      expect(formatBytes(2.75 * 1024 * 1024 * 1024)).toBe('2.75 GB');
    });

    it('should handle different decimal places', () => {
      expect(formatBytes(1024, 0)).toBe('1 KB');
      expect(formatBytes(1536, 1)).toBe('1.5 KB');
      expect(formatBytes(1536, 3)).toBe('1.500 KB');
    });

    it('should handle large numbers', () => {
      expect(formatBytes(1024**5)).toBe('1.00 PB'); // Petabytes
    });
  });
});
