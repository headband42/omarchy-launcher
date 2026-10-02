# X headlines

Tile id `x`. Guest trends need no account. Today's News and the notification
badge use a signed-in session from the default browser.

## Place

Place picks which guest trends the tile shows. Today's News is one feed
wherever the tile is set, so the tile names the place only over trends. The
× beside the place in settings clears it back to Worldwide.

## Today's News

Open the tile's settings and choose **Import from browser**. That reads
`auth_token` and `ct0` for x.com from whichever browser Omarchy has set as
the default, and writes them to `~/.config/ande.launcher/x-cookies.json`
(mode 0600, outside this repo). Stay signed in to X in that browser.

The same import from a terminal:

```bash
python3 widgets/x/export-browser-cookies.py --yes
```

Supported browsers, matching `omarchy default browser`:

| Browser | Id | Profile |
| --- | --- | --- |
| Chromium | `chromium` | `~/.config/chromium` |
| Chrome | `chrome` | `~/.config/google-chrome` |
| Brave | `brave` | `~/.config/BraveSoftware/Brave-Browser` |
| Brave Origin | `brave-origin` | `~/.config/BraveSoftware/Brave-Origin` |
| Edge | `edge` | `~/.config/microsoft-edge` |
| Firefox | `firefox` | `~/.mozilla/firefox` or `~/.config/mozilla/firefox` |
| Zen | `zen` | `~/.config/zen` or `~/.zen` |

Chromium-family cookies are decrypted with the keyring password (`secret-tool`
or `secretstorage`). Edge on Linux uses Chromium's Safe Storage entry. Brave
Origin uses Brave's. Firefox and Zen store cookie values in `cookies.sqlite`.
`openssl` must be on `PATH`.

A profile outside those directories can be passed with `--profile`. Delete
`x-cookies.json` to go back to guest trends.

## Files

| Path | Role |
| --- | --- |
| `widgets/x/x.py` | Fetch and cache |
| `widgets/x/sample.py` | CLI for the tile |
| `widgets/x/export-browser-cookies.py` | Session import |
| `widgets/x/Widget.qml` / `Settings.qml` | Tile and settings |
| `~/.config/ande.launcher/x-cookies.json` | Your session (do not commit) |
| `~/.cache/ande.launcher/x/` | Headline cache |
