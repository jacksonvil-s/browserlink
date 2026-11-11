# Version 1.4.0

**Added:**
- Major overhauls to link security system. Now classified in 3 categories.
	- Serious warnings are displayed prominately with a 3 second delay
	- Medium warnings displays a dismissable warning
	- Advisories do not block anything
	- Preferences now reorganised into seriousness
- New security cateogories:
	- Download links (.dmg/.zip/.exe)
	- URL shortners (bit.ly)
	- "@ trick" where paypal.com@evil-site.xyz directs to evil site
- Brand new logic for link queueing
	- If an app spams you with links, it will start to queue and display 1 by 1.
	- You can dismiss all at once
- Implement sparkle quiet notice (as a menu bar logo)
- Browsers can now be disabled
- New browser support:
	- DuckDuckGo Browser
	- Dia
- Numbers added in browser chooser.

**Fixed:**
- Rare crashing caused by rapidly opening new chooser panels
	- Animations now more subtle


> [!important]
> This app version is unsigned. You must trust the app manually to use it. If you don't already know how to do this, you are probably not the target audience.
