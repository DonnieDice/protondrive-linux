import * as ProtonDriveSDK from '@protontech/drive-sdk';
import {
    ProtonDriveClientContructorParameters,
    Telemetry,
    Logger,
    HttpClient,
    EntitiesCache,
    CryptoCache,
    Account,
    OpenPGPCrypto,
    SRP,
    Config,
    LatestEventIdProvider,
    MaybeNode,
} from 'sdk-main/js/sdk/src/interface';
import logger from '../shared/utils/logger'; // Our implemented logger
import { appConfig } from '../shared/config/app-config'; // Our implemented appConfig

// --- Mocks for ProtonDriveClientContructorParameters (Temporary for development) ---
// Using console directly for clearer debugging
class HttpClientMock implements HttpClient {
    async get<T>(url: string, options?: any): Promise<T> { logger.debug(`HttpClientMock: GET ${url}`); return {} as T; }
    async post<T>(url: string, data?: any, options?: any): Promise<T> { logger.debug(`HttpClientMock: POST ${url}`); return {} as T; }
    async put<T>(url: string, data?: any, options?: any): Promise<T> { logger.debug(`HttpClientMock: PUT ${url}`); return {} as T; }
    async delete<T>(url: string, options?: any): Promise<T> { logger.debug(`HttpClientMock: DELETE ${url}`); return {} as T; }
}

class EntitiesCacheMock implements EntitiesCache {
    async get<T>(key: string): Promise<T | undefined> { logger.debug(`EntitiesCacheMock: GET ${key}`); return undefined; }
    async put<T>(key: string, value: T): Promise<void> { logger.debug(`EntitiesCacheMock: PUT ${key}`); }
    async delete(key: string): Promise<void> { logger.debug(`EntitiesCacheMock: DELETE ${key}`); }
}

class CryptoCacheMock implements CryptoCache {
    async get<T>(key: string): Promise<T | undefined> { logger.debug(`CryptoCacheMock: GET ${key}`); return undefined; }
    async put<T>(key: string, value: T): Promise<void> { logger.debug(`CryptoCacheMock: PUT ${key}`); }
    async delete(key: string): Promise<void> { logger.debug(`CryptoCacheMock: DELETE ${key}`); }
    async deleteByNodeId(nodeId: string): Promise<void> { logger.debug(`CryptoCacheMock: DELETE by node ID ${nodeId}`); }
    async deleteByShareId(shareId: string): Promise<void> { logger.debug(`CryptoCacheMock: DELETE by share ID ${shareId}`); }
}

class AccountMock implements Account {
    get apiToken(): string { return 'mock_api_token'; }
    get memberId(): string { return 'mock_member_id'; }
    get email(): string { return 'mock@proton.me'; }
    get name(): string { return 'Mock User'; }
    get currency(): string { return 'USD'; }
    async getAddressKeys(): Promise<any[]> { logger.debug('AccountMock: getAddressKeys'); return []; }
    async getPrimaryAddress(): Promise<any> { logger.debug('AccountMock: getPrimaryAddress'); return {}; }
}

// Minimal placeholder for OpenPGPCrypto
class OpenPGPCryptoMock implements OpenPGPCrypto {
    async decrypt(data: any): Promise<any> { logger.debug('OpenPGPCryptoMock: decrypt'); return data; }
    async encrypt(data: any): Promise<any> { logger.debug('OpenPGPCryptoMock: encrypt'); return data; }
    async getPublicKey(): Promise<any> { logger.debug('OpenPGPCryptoMock: getPublicKey'); return {}; }
    async getPrivateKey(): Promise<any> { logger.debug('OpenPGPCryptoMock: getPrivateKey'); return {}; }
    async sign(data: any): Promise<any> { logger.debug('OpenPGPCryptoMock: sign'); return data; }
    async verify(data: any, signature: any): Promise<boolean> { logger.debug('OpenPGPCryptoMock: verify'); return true; }
    async getItemKey(itemKey: any): Promise<any> { logger.debug('OpenPGPCryptoMock: getItemKey'); return {}; }
    async getItemKeyPacket(itemKeyPacket: any): Promise<any> { logger.debug('OpenPGPCryptoMock: getItemKeyPacket'); return {}; }
    async getFileKey(fileKey: any): Promise<any> { logger.debug('OpenPGPCryptoMock: getFileKey'); return {}; }
    async getFileKeyPacket(fileKeyPacket: any): Promise<any> { logger.debug('OpenPGPCryptoMock: getFileKeyPacket'); return {}; }
    async getAuth(): Promise<any> { logger.debug('OpenPGPCryptoMock: getAuth'); return {}; }
}

// Minimal placeholder for SRP
class SRPMock implements SRP {
    async createProof(username: string, password: string): Promise<any> { logger.debug('SRPMock: createProof'); return {}; }
    async verifyProof(username: string, password: string, salt: string, serverEphemeral: string): Promise<any> { logger.debug('SRPMock: verifyProof'); return {}; }
}

// Actual Config implementation using appConfig
class SdkConfig implements Config {
    // These values should ideally come from appConfig or be configurable
    baseUrl: string = process.env.PROTON_API_URL || 'https://api.proton.me'; // Fallback to a default if not in env
    language: string = 'en'; // Hardcoded for now, can be made dynamic later
    clientUid: string = 'protondrive-linux-client'; // Unique identifier for this application
}

// Actual Telemetry implementation using our logger
class SdkTelemetry implements Telemetry {
    getLogger(name: string): Logger {
        // Adapt our winston logger to the SDK's Logger interface
        return {
            debug: (message: string, context?: any) => logger.debug(message, { sdkModule: name, ...context }),
            info: (message: string, context?: any) => logger.info(message, { sdkModule: name, ...context }),
            warn: (message: string, context?: any) => logger.warn(message, { sdkModule: name, ...context }),
            error: (error: Error, context?: any) => logger.error(error.message, { sdkModule: name, stack: error.stack, ...context }),
            log: (level: string, message: string, context?: any) => {
                // Map SDK's log levels to Winston's
                switch (level) {
                    case 'debug': logger.debug(message, { sdkModule: name, ...context }); break;
                    case 'info': logger.info(message, { sdkModule: name, ...context }); break;
                    case 'warn': logger.warn(message, { sdkModule: name, ...context }); break;
                    case 'error': logger.error(message, { sdkModule: name, ...context }); break;
                    default: logger.info(message, { sdkModule: name, level, ...context });
                }
            },
        };
    }
    log(level: string, message: string, context?: any): void {
        // Direct logging from the top-level Telemetry instance
        (this.getLogger('ProtonDriveSDK') as any)[level](message, context);
    }
    error(error: Error, context?: any): void {
        this.getLogger('ProtonDriveSDK').error(error, context);
    }
}

class LatestEventIdProviderMock implements LatestEventIdProvider {
    async getLatestEventId(): Promise<number | undefined> { logger.debug('LatestEventIdProviderMock: getLatestEventId'); return undefined; }
    async setLatestEventId(id: number): Promise<void> { logger.debug(`LatestEventIdProviderMock: Set event ID to ${id}`); }
}
// --- End Mocks ---

class SdkBridge {
    private client: ProtonDriveSDK.ProtonDriveClient;
    private telemetry: SdkTelemetry; // Use our actual Telemetry
    private sdkLogger: Logger; // Use the SDK's logger interface

    constructor() {
        this.telemetry = new SdkTelemetry();
        this.sdkLogger = this.telemetry.getLogger('SdkBridge');

        // Instantiate ProtonDriveClient with mocks where services are not yet implemented
        const clientConfig: ProtonDriveClientContructorParameters = {
            httpClient: new HttpClientMock(),
            entitiesCache: new EntitiesCacheMock(),
            cryptoCache: new CryptoCacheMock(),
            account: new AccountMock(),
            openPGPCryptoModule: new OpenPGPCryptoMock(),
            srpModule: new SRPMock(),
            config: new SdkConfig(), // Use our actual Config
            telemetry: this.telemetry, // Use our actual Telemetry
            latestEventIdProvider: new LatestEventIdProviderMock(),
        };

        this.client = new ProtonDriveSDK.ProtonDriveClient(clientConfig);
        this.sdkLogger.info('Proton Drive SDK Bridge initialized with ProtonDriveClient (using some mocks).');
    }

    public start(): void {
        this.sdkLogger.info('Proton Drive SDK Bridge start called.');
        // In a real scenario, this might initiate authentication or background sync.
    }

    public async sendMessage(message: { method: string; args: any[] }): Promise<any> {
        this.sdkLogger.info(`Proton Drive SDK Bridge received message: ${JSON.stringify(message)}`);
        const { method, args } = message;

        if (typeof (this.client as any)[method] === 'function') {
            this.sdkLogger.info(`Proton Drive SDK Bridge calling client method: ${method} with args: ${JSON.stringify(args)}`);
            const result = await (this.client as any)[method](...args);
            this.sdkLogger.info(`Proton Drive SDK Bridge received result from ${method}: ${JSON.stringify(result)}`);
            // Handle AsyncGenerator results
            if (result && typeof result[Symbol.asyncIterator] === 'function') {
                const allResults = [];
                for await (const item of result) {
                    allResults.push(item);
                }
                this.sdkLogger.info(`Proton Drive SDK Bridge collected AsyncGenerator results: ${JSON.stringify(allResults)}`);
                return allResults;
            }
            return result;
        } else {
            this.sdkLogger.warn(`Method ${method} not found on ProtonDriveClient.`);
            return Promise.resolve(`Error: Method ${method} not found.`);
        }
    }

    public onMessage(callback: (message: string) => void): void {
        this.sdkLogger.info('Proton Drive SDK Bridge onMessage registered. (Mock implementation does not emit messages)');
        // If the JS SDK provides an event emitter, you would hook it up here.
    }

    public stop(): void {
        this.sdkLogger.info('Proton Drive SDK Bridge stop called.');
        // Cleanup for mock if any.
    }
}

export const sdkBridge = new SdkBridge();