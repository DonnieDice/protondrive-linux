/**
 * Performance Profiler
 * 
 * Detects system hardware capabilities and creates appropriate performance profiles.
 * Implements adaptive resource management for universal hardware compatibility.
 */

import * as os from 'os'
import * as fs from 'fs'
import * as path from 'path'
import { app } from 'electron'
import {
  SystemCapabilities,
  StorageType,
  PerformanceProfile,
  PerformanceProfileLevel,
  StoragePerformanceTest
} from '@shared/types/system'
import logger from '@shared/utils/logger'

/**
 * Detect system capabilities
 */
export function getSystemCapabilities(): SystemCapabilities {
  const totalRAM = Math.round(os.totalmem() / (1024 * 1024)) // Convert to MB
  const freeRAM = Math.round(os.freemem() / (1024 * 1024))
  const availableRAM = freeRAM
  const cpuCores = os.cpus().length
  const architecture = os.arch()
  const platform = os.platform()
  const osRelease = os.release()
  
  logger.info('System capabilities detected', {
    totalRAM,
    availableRAM,
    cpuCores,
    architecture,
    platform,
    osRelease
  })
  
  return {
    totalRAM,
    availableRAM,
    cpuCores,
    architecture,
    storageType: 'UNKNOWN', // Will be detected separately
    platform,
    osRelease
  }
}

/**
 * Detect storage type by testing write performance
 * SSD: <100ms for 10MB sync write
 * HDD: >150ms for 10MB sync write
 */
export async function detectStorageType(): Promise<StoragePerformanceTest> {
  const testSizeBytes = 10 * 1024 * 1024 // 10MB
  const testData = Buffer.alloc(testSizeBytes)
  const testFile = path.join(app.getPath('temp'), `storage-test-${Date.now()}.tmp`)
  
  try {
    const startTime = performance.now()
    
    // Write test data
    fs.writeFileSync(testFile, testData)
    
    // Force sync to disk
    const fd = fs.openSync(testFile, 'r+')
    fs.fsyncSync(fd)
    fs.closeSync(fd)
    
    const endTime = performance.now()
    const testDurationMs = endTime - startTime
    const writeSpeedMBps = (testSizeBytes / (1024 * 1024)) / (testDurationMs / 1000)
    
    // Cleanup
    try {
      fs.unlinkSync(testFile)
    } catch (err) {
      logger.warn('Failed to cleanup storage test file', { error: err })
    }
    
    // Determine storage type based on performance
    let storageType: StorageType
    if (testDurationMs < 100) {
      storageType = 'SSD'
    } else if (testDurationMs > 150) {
      storageType = 'HDD'
    } else {
      storageType = 'UNKNOWN'
    }
    
    logger.info('Storage type detected', {
      storageType,
      testDurationMs,
      writeSpeedMBps: writeSpeedMBps.toFixed(2)
    })
    
    return {
      storageType,
      writeSpeedMBps,
      testDurationMs,
      testSizeBytes
    }
  } catch (error) {
    logger.error('Storage detection failed', { error })
    return {
      storageType: 'UNKNOWN',
      writeSpeedMBps: 0,
      testDurationMs: 0,
      testSizeBytes
    }
  }
}

/**
 * Create performance profile based on system capabilities
 */
export function createPerformanceProfile(
  capabilities: SystemCapabilities
): PerformanceProfile {
  const { totalRAM, cpuCores, storageType } = capabilities
  
  let level: PerformanceProfileLevel
  let profile: PerformanceProfile
  
  // Determine profile level based on RAM
  if (totalRAM < 4096) {
    level = 'low-end'
    profile = createLowEndProfile(cpuCores, storageType)
  } else if (totalRAM < 8192) {
    level = 'standard'
    profile = createStandardProfile(cpuCores, storageType)
  } else {
    level = 'high-end'
    profile = createHighEndProfile(cpuCores, storageType)
  }
  
  logger.info('Performance profile created', {
    level,
    totalRAM,
    cpuCores,
    storageType,
    profile
  })
  
  return profile
}

/**
 * Low-end profile (2-4GB RAM)
 * Optimized for minimal resource usage
 */
function createLowEndProfile(
  cpuCores: number,
  storageType: StorageType
): PerformanceProfile {
  return {
    level: 'low-end',
    maxConcurrentUploads: 1,
    maxConcurrentDownloads: 2,
    cacheSizeMB: 50,
    enableAnimations: false,
    chunkSizeMB: 5,
    maxMemoryUsageMB: 100,
    dbCacheSizeMB: storageType === 'HDD' ? 4 : 8,
    dbSynchronousMode: storageType === 'HDD' ? 'NORMAL' : 'FULL',
    workerPoolSize: Math.max(1, Math.floor(cpuCores / 2))
  }
}

/**
 * Standard profile (4-8GB RAM)
 * Balanced performance and resource usage
 */
function createStandardProfile(
  cpuCores: number,
  storageType: StorageType
): PerformanceProfile {
  return {
    level: 'standard',
    maxConcurrentUploads: 3,
    maxConcurrentDownloads: 5,
    cacheSizeMB: 100,
    enableAnimations: true,
    chunkSizeMB: 5,
    maxMemoryUsageMB: 150,
    dbCacheSizeMB: storageType === 'HDD' ? 4 : 8,
    dbSynchronousMode: storageType === 'HDD' ? 'NORMAL' : 'FULL',
    workerPoolSize: Math.max(1, Math.floor(cpuCores / 2))
  }
}

/**
 * High-end profile (8GB+ RAM)
 * Maximum performance
 */
function createHighEndProfile(
  cpuCores: number,
  storageType: StorageType
): PerformanceProfile {
  return {
    level: 'high-end',
    maxConcurrentUploads: 5,
    maxConcurrentDownloads: 10,
    cacheSizeMB: 200,
    enableAnimations: true,
    chunkSizeMB: 10,
    maxMemoryUsageMB: 200,
    dbCacheSizeMB: storageType === 'HDD' ? 8 : 16,
    dbSynchronousMode: storageType === 'HDD' ? 'NORMAL' : 'FULL',
    workerPoolSize: Math.min(cpuCores - 1, 4)
  }
}

/**
 * Get complete system profile
 * Detects capabilities and creates appropriate performance profile
 */
export async function getSystemProfile(): Promise<{
  capabilities: SystemCapabilities
  storageTest: StoragePerformanceTest
  profile: PerformanceProfile
}> {
  const capabilities = getSystemCapabilities()
  const storageTest = await detectStorageType()
  
  // Update capabilities with detected storage type
  capabilities.storageType = storageTest.storageType
  
  const profile = createPerformanceProfile(capabilities)
  
  return {
    capabilities,
    storageTest,
    profile
  }
}
