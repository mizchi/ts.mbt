export interface Page {
  url(): string;
}
export interface ConsoleMessage {
  text(): string;
}
export interface Browser {
  on(event: 'close', listener: (browser: Browser) => void): this;
  on(event: 'console', listener: (message: ConsoleMessage) => void): this;
  on(event: 'page', listener: (page: Page) => void): this;
  once(event: 'close', listener: (browser: Browser) => void): this;
  once(event: 'page', listener: (page: Page) => void): this;
  newPage(): Page;
}
export declare function launch(): Browser;
