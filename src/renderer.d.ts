export interface IpcApi {
    sendMessage: (message: { method: string; args: any[] }) => Promise<any>,
    onMessage: (callback: (message: string) => void) => void,
}

declare global {
    interface Window {
        sdk: IpcApi
    }
}
