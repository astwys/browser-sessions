enum CmdlineFixtures {
    static let playwrightPipe = "/Users/me/Library/Caches/ms-playwright/chromium-1124/chrome-mac/Chromium.app/Contents/MacOS/Chromium --remote-debugging-pipe --user-data-dir=/var/folders/playwright_chromiumdev_profile-abc"
    static let remoteDebuggingOnly = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222"
    static let headlessOnly = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --user-data-dir=/tmp/chrome-profile"
    static let crashpad = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/chrome_crashpad_handler --monitor-self"
    static let puppeteer = "/Users/me/.cache/puppeteer/chrome/mac_arm-120/chrome-mac/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing --enable-automation"
    static let parentPlaywright = "node /repo/node_modules/.bin/playwright test"
    static let psOutput = """
    101|1|12|/Applications/Google Chrome.app/Contents/MacOS/Google Chrome|/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222
    102|101|4|/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/chrome_crashpad_handler|chrome_crashpad_handler --monitor-self
    """
    static let whitespacePSOutput = """
      201     1 Mon Jun 22 15:54:30 2026 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/profile
      202   201 Mon Jun 22 15:54:31 2026 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/chrome_crashpad_handler --monitor-self
    """
}
