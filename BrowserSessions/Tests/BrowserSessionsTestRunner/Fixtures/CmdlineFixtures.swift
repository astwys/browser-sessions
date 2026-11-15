enum CmdlineFixtures {
    static let playwrightPipe = "/Users/me/Library/Caches/ms-playwright/chromium-1124/chrome-mac/Chromium.app/Contents/MacOS/Chromium --remote-debugging-pipe --user-data-dir=/var/folders/playwright_chromiumdev_profile-abc"
    static let remoteDebuggingOnly = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222"
    static let headlessOnly = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --user-data-dir=/tmp/chrome-profile"
    static let crashpad = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/chrome_crashpad_handler --monitor-self"
    static let puppeteer = "/Users/me/.cache/puppeteer/chrome/mac_arm-120/chrome-mac/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing --enable-automation"
    static let parentPlaywright = "node /repo/node_modules/.bin/playwright test"
}
