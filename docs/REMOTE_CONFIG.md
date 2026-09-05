# Support link

Edit `docs/config.json` on `main` and change `supportLinkEnabled` to `true`
to enable the optional Buy Me a Coffee link. Commit the change and wait for
GitHub Pages deployment. Set it to `false` to disable it again.

Published endpoint: https://lucasscariot.github.io/herdie/config.json

The maker page fetches on opening and when the app returns to the foreground.
Failed requests, malformed responses, and unknown or non-US StoreKit storefronts
hide the link. There is no persistent enabled cache. An already open page refreshes
every minute; GitHub Pages CDN propagation can introduce additional delay.

The destination is fixed in the app, not supplied by the remote document.
No credentials or analytics identifiers are sent. GitHub receives ordinary HTTPS
request metadata. The website and X links are always available.

Disclose the support link, US storefront restriction, and remote flag in App Review
notes. Do not use the flag to conceal functionality during review. Support provides
no additional features or digital benefits.
