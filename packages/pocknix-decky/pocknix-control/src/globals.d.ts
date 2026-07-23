export {};

declare global {
  interface Window {
    SteamClient?: any;
    appDetailsStore?: any;
    appStore?: any;
    collectionStore?: any;
    Router?: any;
  }
}
