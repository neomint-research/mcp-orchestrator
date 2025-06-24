/**
 * Docker Rootless Mode Discovery Tests
 * 
 * Tests the rootless Docker socket detection and validation logic
 */

const { Discovery } = require('../../src/core/backend/discovery');
const fs = require('fs');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

// Mock fs and exec for testing
jest.mock('fs');
jest.mock('child_process');

describe('Discovery - Rootless Docker Support', () => {
    let mockExecAsync;
    let mockFs;

    beforeEach(() => {
        jest.clearAllMocks();
        mockExecAsync = execAsync;
        mockFs = fs;
        
        // Reset process.env and process.getuid
        delete process.env.UID;
        delete process.env.HOME;
        delete process.env.DOCKER_HOST;
        delete process.env.DOCKER_ROOTLESS_SOCKET_PATH;
    });

    describe('getCurrentUID', () => {
        test('should return UID from environment variable', async () => {
            process.env.UID = '1234';
            const uid = await Discovery.getCurrentUID();
            expect(uid).toBe(1234);
        });

        test('should return UID from process.getuid if available', async () => {
            process.getuid = jest.fn().mockReturnValue(5678);
            const uid = await Discovery.getCurrentUID();
            expect(uid).toBe(5678);
        });

        test('should execute id -u command as fallback', async () => {
            mockExecAsync.mockResolvedValue({ stdout: '9999\n' });
            const uid = await Discovery.getCurrentUID();
            expect(uid).toBe(9999);
            expect(mockExecAsync).toHaveBeenCalledWith('id -u');
        });

        test('should return fallback UID 1001 on error', async () => {
            mockExecAsync.mockRejectedValue(new Error('Command failed'));
            const uid = await Discovery.getCurrentUID();
            expect(uid).toBe(1001);
        });
    });

    describe('getPossibleRootlessSocketPaths', () => {
        beforeEach(() => {
            // Mock getCurrentUID to return a known value
            jest.spyOn(Discovery, 'getCurrentUID').mockResolvedValue(1234);
            process.env.HOME = '/home/testuser';
        });

        test('should return standard rootless socket paths', async () => {
            mockFs.existsSync.mockReturnValue(false);
            
            const paths = await Discovery.getPossibleRootlessSocketPaths();
            
            expect(paths).toContain('/run/user/1234/docker.sock');
            expect(paths).toContain('/tmp/docker-1234/docker.sock');
            expect(paths).toContain('/var/run/user/1234/docker.sock');
            expect(paths).toContain('/home/testuser/.docker/run/docker.sock');
        });

        test('should include environment variable paths', async () => {
            process.env.DOCKER_HOST = 'unix:///custom/docker.sock';
            process.env.DOCKER_ROOTLESS_SOCKET_PATH = '/custom/rootless.sock';
            mockFs.existsSync.mockReturnValue(false);
            
            const paths = await Discovery.getPossibleRootlessSocketPaths();
            
            expect(paths).toContain('/custom/docker.sock');
            expect(paths).toContain('/custom/rootless.sock');
        });

        test('should filter to existing socket files', async () => {
            const existingSocket = '/run/user/1234/docker.sock';
            mockFs.existsSync.mockImplementation(path => path === existingSocket);
            mockFs.statSync.mockImplementation(path => {
                if (path === existingSocket) {
                    return { isSocket: () => true };
                }
                throw new Error('File not found');
            });
            
            const paths = await Discovery.getPossibleRootlessSocketPaths();
            
            expect(paths).toContain(existingSocket);
            expect(paths.length).toBeGreaterThan(0);
        });

        test('should return fallback paths when no sockets exist', async () => {
            mockFs.existsSync.mockReturnValue(false);
            
            const paths = await Discovery.getPossibleRootlessSocketPaths();
            
            expect(paths).toContain('/run/user/1234/docker.sock');
            expect(paths).toContain('/tmp/docker-1234/docker.sock');
        });
    });

    describe('validateDockerSocket', () => {
        test('should return invalid if socket does not exist', async () => {
            mockFs.existsSync.mockReturnValue(false);
            
            const result = await Discovery.validateDockerSocket('/nonexistent/socket');
            
            expect(result.valid).toBe(false);
            expect(result.reason).toContain('does not exist');
        });

        test('should return invalid if path is not a socket', async () => {
            mockFs.existsSync.mockReturnValue(true);
            mockFs.statSync.mockReturnValue({ isSocket: () => false });
            
            const result = await Discovery.validateDockerSocket('/not/a/socket');
            
            expect(result.valid).toBe(false);
            expect(result.reason).toContain('not a socket');
        });

        test('should return valid if Docker responds successfully', async () => {
            mockFs.existsSync.mockReturnValue(true);
            mockFs.statSync.mockReturnValue({ isSocket: () => true });
            mockExecAsync.mockResolvedValue({ stdout: '20.10.0' });
            
            const result = await Discovery.validateDockerSocket('/valid/socket');
            
            expect(result.valid).toBe(true);
            expect(result.reason).toContain('accessible');
        });

        test('should return invalid if Docker command fails', async () => {
            mockFs.existsSync.mockReturnValue(true);
            mockFs.statSync.mockReturnValue({ isSocket: () => true });
            mockExecAsync.mockRejectedValue(new Error('Docker not responding'));
            
            const result = await Discovery.validateDockerSocket('/invalid/socket');
            
            expect(result.valid).toBe(false);
            expect(result.reason).toContain('Docker command failed');
        });
    });

    describe('detectDockerMode with rootless support', () => {
        let discovery;

        beforeEach(() => {
            discovery = new Discovery(); // Always rootless mode
            jest.spyOn(Discovery, 'getPossibleRootlessSocketPaths').mockResolvedValue([
                '/run/user/1234/docker.sock',
                '/tmp/docker-1234/docker.sock'
            ]);
        });

        test('should detect rootless Docker when socket is valid', async () => {
            jest.spyOn(Discovery, 'validateDockerSocket').mockImplementation(async (path) => {
                if (path === '/run/user/1234/docker.sock') {
                    return { valid: true, reason: 'Socket accessible' };
                }
                return { valid: false, reason: 'Not accessible' };
            });

            await discovery.detectDockerMode();

            expect(discovery.dockerMode).toBe('rootless');
            expect(discovery.dockerHost).toBe('unix:///run/user/1234/docker.sock');
        });

        test('should throw error if rootless not available - no fallback', async () => {
            jest.spyOn(Discovery, 'validateDockerSocket').mockImplementation(async (path) => {
                return { valid: false, reason: 'Not accessible' };
            });

            await expect(discovery.detectDockerMode()).rejects.toThrow('Rootless Docker is not available');
        });

        test('should try multiple rootless socket paths', async () => {
            const validateSpy = jest.spyOn(Discovery, 'validateDockerSocket').mockImplementation(async (path) => {
                if (path === '/tmp/docker-1234/docker.sock') {
                    return { valid: true, reason: 'Socket accessible' };
                }
                return { valid: false, reason: 'Not accessible' };
            });

            await discovery.detectDockerMode();

            expect(validateSpy).toHaveBeenCalledWith('/run/user/1234/docker.sock');
            expect(validateSpy).toHaveBeenCalledWith('/tmp/docker-1234/docker.sock');
            expect(discovery.dockerMode).toBe('rootless');
            expect(discovery.dockerHost).toBe('unix:///tmp/docker-1234/docker.sock');
        });
    });

    describe('Integration with environment variables', () => {
        test('should use DOCKER_ROOTLESS_SOCKET_PATH from environment', () => {
            process.env.DOCKER_ROOTLESS_SOCKET_PATH = '/custom/rootless.sock';
            
            const discovery = new Discovery();
            
            expect(discovery.config.dockerRootlessSocket).toBe('/custom/rootless.sock');
        });

        test('should use DOCKER_SOCKET_PATH from environment', () => {
            process.env.DOCKER_SOCKET_PATH = '/custom/docker.sock';
            
            const discovery = new Discovery();
            
            expect(discovery.config.dockerSocket).toBe('/custom/docker.sock');
        });

        test('should use dynamic UID in default rootless socket path', () => {
            process.env.UID = '5555';
            
            const discovery = new Discovery();
            
            expect(discovery.config.dockerRootlessSocket).toContain('5555');
        });
    });
});
