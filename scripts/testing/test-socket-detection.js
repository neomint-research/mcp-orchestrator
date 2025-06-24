#!/usr/bin/env node

/**
 * Test Script for Rootless Docker Socket Detection
 *
 * This script tests the dynamic UID detection and socket path discovery
 * functionality without requiring a full Docker environment.
 * Moved to scripts/testing/ for better organization per NEOMINT-RESEARCH guidelines.
 */

const { Discovery } = require('../../src/core/backend/discovery');
const fs = require('fs');

// Colors for output
const colors = {
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    reset: '\x1b[0m'
};

function printColor(color, message) {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

function checkSuccess(condition, message) {
    if (condition) {
        printColor('green', `✓ ${message}`);
        return true;
    } else {
        printColor('red', `✗ ${message}`);
        return false;
    }
}

async function testSocketDetection() {
    printColor('blue', 'MCP Orchestrator - Socket Detection Test');
    printColor('blue', '=====================================');

    let passed = 0;
    let total = 0;

    // Test 1: UID Detection
    printColor('blue', '\n1. Testing UID Detection...');
    total++;

    try {
        const uid = await Discovery.getCurrentUID();
        const isValidUID = typeof uid === 'number' && uid > 0;
        
        if (checkSuccess(isValidUID, `UID detection (detected: ${uid})`)) {
            passed++;
        }
    } catch (error) {
        checkSuccess(false, `UID detection failed: ${error.message}`);
    }

    // Test 2: Socket Path Generation
    printColor('blue', '\n2. Testing Socket Path Generation...');
    total++;

    try {
        const paths = await Discovery.getPossibleRootlessSocketPaths();
        const hasValidPaths = Array.isArray(paths) && paths.length > 0;
        
        if (checkSuccess(hasValidPaths, `Socket path generation (found ${paths.length} paths)`)) {
            passed++;
            
            // Show the paths
            printColor('blue', 'Generated socket paths:');
            paths.forEach(path => {
                const exists = fs.existsSync(path);
                const status = exists ? '(exists)' : '(not found)';
                console.log(`  - ${path} ${status}`);
            });
        }
    } catch (error) {
        checkSuccess(false, `Socket path generation failed: ${error.message}`);
    }

    // Test 3: Environment Variable Integration
    printColor('blue', '\n3. Testing Environment Variable Integration...');
    total++;

    try {
        // Test with custom environment variables
        process.env.UID = '9999';
        process.env.DOCKER_ROOTLESS_SOCKET_PATH = '/custom/test.sock';
        
        const discovery = new Discovery();
        const hasCustomSocket = discovery.config.dockerRootlessSocket === '/custom/test.sock';
        
        if (checkSuccess(hasCustomSocket, 'Environment variable integration')) {
            passed++;
        }
        
        // Clean up
        delete process.env.UID;
        delete process.env.DOCKER_ROOTLESS_SOCKET_PATH;
    } catch (error) {
        checkSuccess(false, `Environment variable integration failed: ${error.message}`);
    }

    // Test 4: Socket Validation (Mock)
    printColor('blue', '\n4. Testing Socket Validation Logic...');
    total++;

    try {
        // Test with non-existent socket
        const result = await Discovery.validateDockerSocket('/nonexistent/socket');
        const hasValidResponse = result && typeof result.valid === 'boolean' && result.reason;
        
        if (checkSuccess(hasValidResponse, 'Socket validation logic')) {
            passed++;
            printColor('blue', `Validation result: ${result.valid ? 'valid' : 'invalid'} - ${result.reason}`);
        }
    } catch (error) {
        checkSuccess(false, `Socket validation failed: ${error.message}`);
    }

    // Test 5: Discovery Configuration
    printColor('blue', '\n5. Testing Discovery Configuration...');
    total++;

    try {
        const discovery = new Discovery();
        const hasValidConfig = discovery.config &&
                              discovery.config.dockerMode === 'rootless' &&
                              discovery.config.dockerRootlessSocket;

        if (checkSuccess(hasValidConfig, 'Discovery configuration')) {
            passed++;
            printColor('blue', `Docker mode: ${discovery.config.dockerMode}`);
            printColor('blue', `Rootless socket: ${discovery.config.dockerRootlessSocket}`);
        }
    } catch (error) {
        checkSuccess(false, `Discovery configuration failed: ${error.message}`);
    }

    // Test 6: Dynamic UID in Default Path
    printColor('blue', '\n6. Testing Dynamic UID in Default Path...');
    total++;

    try {
        process.env.UID = '5555';
        const discovery = new Discovery();
        const hasCorrectUID = discovery.config.dockerRootlessSocket.includes('5555');
        
        if (checkSuccess(hasCorrectUID, 'Dynamic UID in default path')) {
            passed++;
        }
        
        delete process.env.UID;
    } catch (error) {
        checkSuccess(false, `Dynamic UID test failed: ${error.message}`);
    }

    // Summary
    printColor('blue', '\n=====================================');
    printColor('blue', 'Test Summary');
    printColor('blue', '=====================================');
    
    const successRate = Math.round((passed / total) * 100);
    
    if (passed === total) {
        printColor('green', `✓ All tests passed! (${passed}/${total})`);
        printColor('green', '🎉 Socket detection implementation is working correctly!');
    } else {
        printColor('yellow', `⚠ ${passed}/${total} tests passed (${successRate}%)`);
        if (passed > total * 0.8) {
            printColor('yellow', '✓ Most functionality is working, minor issues detected');
        } else {
            printColor('red', '✗ Significant issues detected, please review implementation');
        }
    }

    // Environment info
    printColor('blue', '\nEnvironment Information:');
    console.log(`  Node.js: ${process.version}`);
    console.log(`  Platform: ${process.platform}`);
    console.log(`  Architecture: ${process.arch}`);
    
    if (process.getuid) {
        console.log(`  Current UID: ${process.getuid()}`);
    } else {
        console.log(`  Current UID: Not available (Windows)`);
    }
    
    const uid = process.env.UID || 'not set';
    console.log(`  UID env var: ${uid}`);

    return passed === total;
}

// Run the test
if (require.main === module) {
    testSocketDetection()
        .then(success => {
            process.exit(success ? 0 : 1);
        })
        .catch(error => {
            printColor('red', `Test execution failed: ${error.message}`);
            console.error(error);
            process.exit(1);
        });
}

module.exports = { testSocketDetection };
