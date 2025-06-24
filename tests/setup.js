/**
 * Jest Test Setup
 * 
 * Global test configuration and utilities for MCP Orchestrator test suites
 * Integrates with the centralized test reporting infrastructure
 */

const fs = require('fs').promises;
const path = require('path');

// Global test configuration
global.TEST_CONFIG = {
  timeout: 30000,
  retries: 3,
  reportingEnabled: true,
  baseReportDir: path.join(__dirname, '..', 'temp', 'reports'),
  dockerRootlessMode: process.env.DOCKER_MODE === 'rootless' || process.env.ROOTLESS_MODE === 'true'
};

// Ensure test reporting directories exist
beforeAll(async () => {
  if (global.TEST_CONFIG.reportingEnabled) {
    const reportDirs = [
      'unit-tests',
      'integration-tests', 
      'e2e-tests',
      'resilience-tests',
      'docker-tests'
    ];

    for (const dir of reportDirs) {
      const fullPath = path.join(global.TEST_CONFIG.baseReportDir, dir);
      try {
        await fs.access(fullPath);
      } catch (error) {
        await fs.mkdir(fullPath, { recursive: true });
      }
    }
  }
});

// Global test utilities
global.testUtils = {
  /**
   * Wait for a condition to be true with timeout
   */
  waitFor: async (condition, timeout = 10000, interval = 100) => {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      if (await condition()) {
        return true;
      }
      await new Promise(resolve => setTimeout(resolve, interval));
    }
    throw new Error(`Condition not met within ${timeout}ms`);
  },

  /**
   * Create a test timestamp
   */
  timestamp: () => new Date().toISOString().replace(/[:.]/g, '-'),

  /**
   * Check if Docker rootless mode is available
   */
  isDockerRootlessAvailable: async () => {
    try {
      const { exec } = require('child_process');
      const { promisify } = require('util');
      const execAsync = promisify(exec);
      
      const uid = process.getuid ? process.getuid() : 1001;
      const socketPath = `/run/user/${uid}/docker.sock`;
      
      await fs.access(socketPath);
      return true;
    } catch (error) {
      return false;
    }
  },

  /**
   * Get rootless Docker socket path (rootless mode only)
   */
  getDockerSocketPath: () => {
    const uid = process.getuid ? process.getuid() : 1001;
    return `/run/user/${uid}/docker.sock`;
  }
};

// Enhanced error reporting for Docker rootless tests
if (global.TEST_CONFIG.dockerRootlessMode) {
  console.log('🐳 Running tests in Docker rootless mode');
  console.log(`📁 Socket path: ${global.testUtils.getDockerSocketPath()}`);
}

// Test result reporting hook
afterEach(async () => {
  if (global.TEST_CONFIG.reportingEnabled && expect.getState().currentTestName) {
    const testResult = {
      testName: expect.getState().currentTestName,
      timestamp: new Date().toISOString(),
      dockerMode: global.TEST_CONFIG.dockerRootlessMode ? 'rootless' : 'standard',
      status: expect.getState().assertionCalls > 0 ? 'completed' : 'skipped'
    };

    // This would be enhanced to write actual test results
    // For now, it just logs the test completion
    if (process.env.VERBOSE_TESTING) {
      console.log(`📊 Test completed: ${testResult.testName} (${testResult.status})`);
    }
  }
});
