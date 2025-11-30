/**
 * System Capability Types
 * 
 * Types for detecting and representing system hardware capabilities.
 * Used by the performance profiler to adapt application behavior to available resources.
 */

/**
 * System capabilities detected at startup
 */
export interface SystemCapabilities {
  /** Total RAM in megabytes */
  totalRAM: number
  
  /** Available RAM at startup in megabytes */
  availableRAM: number
  
  /** Number of CPU cores */
  cpuCores: number
  
  /** CPU architecture (x86_64, ARM64, ARMv7) */
  architecture: string
  
  /** Estimated storage type (SSD, HDD, eMMC, UNKNOWN) */
  storageType: StorageType
  
  /** Operating system platform */
  platform: NodeJS.Platform
  
  /** OS release version */
  osRelease: string
}

/**
 * Storage device types
 */
export type StorageType = 'SSD' | 'HDD' | 'eMMC' | 'UNKNOWN'

/**
 * Performance profile levels based on hardware capabilities
 */
export type PerformanceProfileLevel = 'low-end' | 'standard' | 'high-end'

/**
 * Performance profile configuration
 * Defines resource limits and behavior based on hardware capabilities
 */
export interface PerformanceProfile {
  /** Profile level identifier */
  level: PerformanceProfileLevel
  
  /** Maximum concurrent upload operations */
  maxConcurrentUploads: number
  
  /** Maximum concurrent download operations */
  maxConcurrentDownloads: number
  
  /** Cache size in megabytes */
  cacheSizeMB: number
  
  /** Whether to enable UI animations */
  enableAnimations: boolean
  
  /** Upload/download chunk size in megabytes */
  chunkSizeMB: number
  
  /** Maximum memory usage target in megabytes */
  maxMemoryUsageMB: number
  
  /** Database cache size in megabytes */
  dbCacheSizeMB: number
  
  /** SQLite synchronous mode */
  dbSynchronousMode: 'OFF' | 'NORMAL' | 'FULL' | 'EXTRA'
  
  /** Worker pool size for CPU-intensive tasks */
  workerPoolSize: number
}

/**
 * Memory usage statistics
 */
export interface MemoryUsage {
  /** Heap used in bytes */
  heapUsed: number
  
  /** Total heap size in bytes */
  heapTotal: number
  
  /** External memory in bytes */
  external: number
  
  /** Total memory used in bytes */
  total: number
  
  /** RSS (Resident Set Size) in bytes */
  rss: number
}

/**
 * Performance measurement result
 */
export interface PerformanceMeasurement {
  /** Measurement name/identifier */
  name: string
  
  /** Duration in milliseconds */
  duration: number
  
  /** Start timestamp */
  startTime: number
  
  /** End timestamp */
  endTime: number
}

/**
 * Storage performance test result
 */
export interface StoragePerformanceTest {
  /** Storage type detected */
  storageType: StorageType
  
  /** Write speed in MB/s */
  writeSpeedMBps: number
  
  /** Test duration in milliseconds */
  testDurationMs: number
  
  /** Test data size in bytes */
  testSizeBytes: number
}
