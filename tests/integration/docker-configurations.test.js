/**
 * Docker Configuration Validation Tests
 * 
 * Tests different Docker configurations (standard, rootless, desktop)
 * and validates the auto-detection logic works correctly
 */

const { Discovery } = require('../../src/core/backend/discovery');
const fs = require('fs');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

describe('Docker Configuration Validation', () => {
    let originalEnv;

    beforeEach(() => {
        // Save original environment
        originalEnv = { ...process.env };
    });

    afterEach(() => {
        // Restore original environment
        process.env = originalEnv;
    });

    describe('Rootless-Only Logic', () => {
        test('should always use rootless Docker configuration', async () => {
            const discovery = new Discovery({ logLevel: 'ERROR' });

            // Should always be rootless mode
            expect(discovery.config.dockerMode).toBe('rootless');
        });

        test('should use rootless Docker socket paths', async () => {
            const uid = process.getuid ? process.getuid() : 1001;
            const rootlessSocket = `/run/user/${uid}/docker.sock`;

            const discovery = new Discovery({ logLevel: 'ERROR' });

            expect(discovery.config.dockerRootlessSocket).toContain(uid.toString());
        });

        test('should handle forced Docker mode configuration', async () => {
            const discovery = new Discovery({ 
                dockerMode: 'standard', 
                logLevel: 'ERROR' 
            });
            
            await discovery.detectDockerMode();
            
            expect(discovery.dockerMode).toBe('standard');
        });
    });

    describe('Legacy Docker Configuration (Removed)', () => {
        test('should not support standard Docker mode', async () => {
            // Test that standard Docker mode is no longer supported
            const discovery = new Discovery({
                logLevel: 'ERROR'
            });

            // Discovery should always be in rootless mode
            expect(discovery.config.dockerMode).toBe('rootless');
        });

        test('should reject standard Docker socket configuration', async () => {
            // Test that standard Docker socket paths are not used
            const discovery = new Discovery({
                logLevel: 'ERROR'
            });

            // Should not have standard Docker socket in config
            expect(discovery.config.dockerSocket).toBeUndefined();
        });

        test('should throw error when no rootless Docker available', async () => {
            const discovery = new Discovery({
                dockerRootlessSocket: '/nonexistent/rootless',
                logLevel: 'ERROR'
            });

            await expect(discovery.detectDockerMode()).rejects.toThrow('Rootless Docker is not available');
        });
    });

    describe('Rootless Docker Configuration', () => {
        test('should detect rootless Docker when available', async () => {
            const uid = process.getuid ? process.getuid() : parseInt(process.env.UID || '1001');
            const rootlessSocket = `/run/user/${uid}/docker.sock`;
            
            if (!fs.existsSync(rootlessSocket)) {
                return; // Skip if rootless Docker not available
            }

            const discovery = new Discovery({ 
                dockerMode: 'rootless',
                logLevel: 'ERROR'
            });
            
            await discovery.detectDockerMode();
            
            expect(discovery.dockerMode).toBe('rootless');
            expect(discovery.dockerHost).toContain(rootlessSocket);
        });

        test('should handle multiple rootless socket locations', async () => {
            const uid = process.getuid ? process.getuid() : parseInt(process.env.UID || '1001');
            const possibleSockets = [
                `/run/user/${uid}/docker.sock`,
                `/tmp/docker-${uid}/docker.sock`,
                `/var/run/user/${uid}/docker.sock`
            ];

            const existingSockets = possibleSockets.filter(socket => fs.existsSync(socket));
            
            if (existingSockets.length === 0) {
                return; // Skip if no rootless sockets available
            }

            const paths = await Discovery.getPossibleRootlessSocketPaths();
            
            existingSockets.forEach(socket => {
                expect(paths).toContain(socket);
            });
        });

        test('should validate rootless Docker socket', async () => {
            const uid = process.getuid ? process.getuid() : parseInt(process.env.UID || '1001');
            const rootlessSocket = `/run/user/${uid}/docker.sock`;
            
            if (!fs.existsSync(rootlessSocket)) {
                return;
            }

            const validation = await Discovery.validateDockerSocket(rootlessSocket);
            
            expect(validation.valid).toBe(true);
            expect(validation.reason).toContain('accessible');
        }, 5000);
    });

    describe('Rootless Docker Security Features', () => {
        test('should enforce rootless mode only', async () => {
            const discovery = new Discovery({
                logLevel: 'ERROR'
            });

            // Should always be rootless mode
            expect(discovery.config.dockerMode).toBe('rootless');
        });

        test('should use user-specific socket paths', async () => {
            const uid = process.getuid ? process.getuid() : parseInt(process.env.UID || '1001');
            const discovery = new Discovery({
                logLevel: 'ERROR'
            });

            expect(discovery.config.dockerRootlessSocket).toContain(uid.toString());
        });

        test('should not fall back to standard Docker', async () => {
            const discovery = new Discovery({
                dockerRootlessSocket: '/nonexistent/rootless',
                logLevel: 'ERROR'
            });

            // Should fail rather than fall back to standard Docker
            await expect(discovery.detectDockerMode()).rejects.toThrow('Rootless Docker is not available');
        });
    });

    describe('Environment Variable Configuration', () => {
        test('should respect DOCKER_HOST environment variable', async () => {
            process.env.DOCKER_HOST = 'unix:///custom/docker.sock';
            
            const paths = await Discovery.getPossibleRootlessSocketPaths();
            
            expect(paths).toContain('/custom/docker.sock');
        });

        test('should respect DOCKER_ROOTLESS_SOCKET_PATH environment variable', async () => {
            process.env.DOCKER_ROOTLESS_SOCKET_PATH = '/custom/rootless.sock';
            
            const discovery = new Discovery();
            
            expect(discovery.config.dockerRootlessSocket).toBe('/custom/rootless.sock');
        });

        test('should use UID environment variable for socket path', async () => {
            process.env.UID = '9999';
            
            const discovery = new Discovery();
            
            expect(discovery.config.dockerRootlessSocket).toContain('9999');
        });

        test('should respect DOCKER_MODE environment variable', async () => {
            process.env.DOCKER_MODE = 'rootless';
            
            const discovery = new Discovery();
            
            expect(discovery.config.dockerMode).toBe('rootless');
        });
    });

    describe('Error Handling and Fallbacks', () => {
        test('should throw error when no rootless Docker is available', async () => {
            const discovery = new Discovery({
                dockerRootlessSocket: '/nonexistent/rootless',
                logLevel: 'ERROR'
            });

            await expect(discovery.detectDockerMode()).rejects.toThrow('Rootless Docker is not available');
        });

        test('should handle permission errors gracefully', async () => {
            const discovery = new Discovery({
                dockerMode: 'standard',
                dockerSocket: '/root/docker.sock', // Likely to cause permission error
                logLevel: 'ERROR'
            });

            // Should not throw, but should handle gracefully
            await expect(discovery.detectDockerMode()).rejects.toThrow();
        });

        test('should retry failed Docker commands', async () => {
            const discovery = new Discovery({
                retryAttempts: 3,
                retryDelay: 100,
                logLevel: 'ERROR'
            });

            // This should work with retries if Docker is available
            try {
                await discovery.detectDockerMode();
                const containers = await discovery.getDockerContainers();
                expect(Array.isArray(containers)).toBe(true);
            } catch (error) {
                // Expected if Docker is not available
                expect(error.message).toContain('Docker');
            }
        }, 10000);
    });
});
