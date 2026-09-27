# X trending-headlines widget

Tile id `x`. Guest trends work with no account. Optional signed-in cookies unlock
Today's News articles and a notification badge count.

**Never commit secrets.** Session cookies (`auth_token`, `ct0`) stay under
`~/.config/ande.launcher/` (outside this repo).

## Cookie-less (default)

Assign the X widget to a tile. It polls Explore-adjacent trends via X's public
web bearer + guest activate. Place (WOEID) and max headlines are in tile Settings.

## Optional signed-in cookies (option 3)

### 1. Sign in to X in a local browser

Use Chromium, Google Chrome, Brave, or Firefox on this machine. Stay signed in.

### 2. Close that browser (recommended)

Chromium locks its Cookies SQLite DB while running. Closing avoids copy/lock errors.

### 3. Run the local export helper

From the plugin checkout (this repo):

```bash
python3 widgets/x/export-browser-cookies.py
```

Confirm the consent prompt (or pass `-y`). The script writes:

```
~/.config/ande.launcher/x-cookies.json
```

Mode `0600`, JSON shape:

```json
{
  "auth_token": "…",
  "ct0": "…"
}
```

Useful flags:

```bash
python3 widgets/x/export-browser-cookies.py --list
python3 widgets/x/export-browser-cookies.py --browser chrome
python3 widgets/x/export-browser-cookies.py --browser brave -y
python3 widgets/x/export-browser-cookies.py --browser firefox --profile ~/.mozilla/firefox/<profile>
python3 widgets/x/export-browser-cookies.py -o ~/.config/ande.launcher/x-cookies.json
```

### 4. Point the tile at the file (usually automatic)

The widget already tries `~/.config/ande.launcher/x-cookies.json` when Settings
leaves the cookies path empty. In tile Settings you can also tap **Use default
path**, or paste another path (Netscape `cookies.txt` or the same JSON shape).

Re-open the launcher (or wait for the next poll). You should see Today's News
when the GraphQL feed accepts the session, and a badge when unread count works.
Trends still work if news stays blocked.

### 5. Refresh cookies when the session expires

Re-run the export helper after signing in again. Delete the JSON file (or Clear
cookies path) to go back to guest-only trends.

## Browsers supported

| Browser | Linux | macOS |
| --- | --- | --- |
| Google Chrome | Yes | Yes (Keychain) |
| Chromium | Yes | Yes (Keychain) |
| Brave | Yes | Yes (Keychain) |
| Firefox | Yes (cookies.sqlite) | Yes |

Chromium-family cookies are encrypted. On Linux the script uses Liberator via
`secretstorage` / `keyring` / `secret-tool` when available, then falls back to
the legacy `peanuts` key. AES unwrap uses `openssl`. On macOS it reads
`… Safe Storage` from Keychain (`security find-generic-password`).

Optional packages (Linux, recommended):

```bash
pip install --user secretstorage
# or: keyring
```

`openssl` must be on `PATH`.

## Limitations

- **You** run the helper on your own machine; the launcher never scrapes a remote
  browser or uploads cookies.
- Windows is not supported by this helper.
- Flatpak/snap browser profiles may live outside the usual `~/.config` paths —
  pass `--profile` to the Cookies DB or profile directory.
- If Chrome uses a newer cookie cipher the script does not understand, export
  fails; use Firefox or a Netscape cookies export from a cookie manager instead.
- Firefox containers / NSS-encrypted cookie values are not handled; normal
  profile `cookies.sqlite` plaintext values are.
- Today's News GraphQL and badge endpoints can change or require additional
  cookies; trends remain the cookie-less fallback.
- Re-export after password changes, logout, or long idle sessions.

## Files

| Path | Role |
| --- | --- |
| `widgets/x/x.py` | Fetch + cache model (stdlib) |
| `widgets/x/sample.py` | CLI for `Widget.qml` |
| `widgets/x/export-browser-cookies.py` | User-run cookie export |
| `widgets/x/Widget.qml` / `Settings.qml` | UI |
| `~/.config/ande.launcher/x-cookies.json` | Your secrets (gitignored name) |
| `~/.cache/ande.launcher/x/` | Headline cache |
