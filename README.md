# Tricky Addon - Update Target List
## This fork use the action.sh to replace the webui
### thanks to KOWX712

Configure Tricky Store target.txt directly with `action.sh` (no WebUI required).

[![Latest Release](https://img.shields.io/github/v/release/KOWX712/Tricky-Addon-Update-Target-List?label=Release&logo=github)](https://github.com/KOWX712/Tricky-Addon-Update-Target-List/releases/latest)
[![Nightly Release](https://custom-icon-badges.demolab.com/badge/Nightly-canary_build-640064?logo=nightly-logo)](https://nightly.link/KOWX712/Tricky-Addon-Update-Target-List/workflows/build/main?status=completed)

> [!WARNING]
> This module is **not** a part of the Tricky Store module. DO NOT report any issues to Tricky Store if encountered.

## Requirements
- [Tricky store](https://github.com/5ec1cff/TrickyStore) module installed

## Instructions
### KernelSU & Apatch
- Open module action and use terminal menu (`action.sh`)

### Magisk
- Use action button to run script menu (`action.sh`)

### What Can This Module Do
| Feature                                                                                                                                                                      | Status |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----: |
| Configure target.txt with app name display                                                                                                                                   |   ✅    |
| Long press to choose `!` or `?` mode for the app. [Auto](https://github.com/5ec1cff/TrickyStore/releases/tag/1.1.0)<br>Use this only  when the app cannot work without this. |   ✅    |
| Select apps from Magisk DenyList `optional`                                                                                                                                  |   ✅    |
| Deselect [unnecessary apps](https://github.com/KOWX712/Tricky-Addon-Update-Target-List/blob/main/more-exclude.json) `optional`                                               |   ✅    |
| Set verifiedBootHash `optional`                                                                                                                                              |   ✅    |
| Auto config [security patch](https://github.com/5ec1cff/TrickyStore?tab=readme-ov-file#customize-security-patch-level-121), customizable in WebUI                            |   ✅    |
| Provide AOSP Keybox `optional`                                                                                                                                               |   ✅    |
| Import custom Keybox from device storage                                                                                                                                     |   ✅    |
| Add system apps `not recommended`                                                                                                                                            |   ✅    |
| Valid Keybox `not guaranteed`                                                                                                                                                |   ❌    |
| Periodically add all app to target.txt                                                                                                                                       |   ❌    |

## Action Script Menu
`module/action.sh` now provides a terminal menu for the core operations previously handled in WebUI:
- Generate `target.txt` from installed apps (reads exclusion patterns in `ExcludeList.txt`)
- Merge Magisk DenyList to `target.txt`
- Set verified boot hash from `VerifiedBootHash.txt` template
- Auto security patch configuration
- Set default AOSP keybox or import local keybox via DocumentsUI
- Online update keybox from multiple sources (Yurikey / TA-UTL / IntegrityBox)
- Hardware key navigation in action menu (Vol- next with loop, Vol+ confirm/continue; fallback to text input if unavailable)

## Localization
- Read [Translation Guide](https://github.com/KOWX712/Tricky-Addon-Update-Target-List/blob/main/webui/public/locales/GUIDE.md)

## Acknowledgement
- [j-hc/zygisk-detach](https://github.com/j-hc/zygisk-detach) - KSU WebUI template
- [markedjs/marked](https://github.com/markedjs/marked) - Markdown Support
- [TMLP-Team/keyboxGenerator](https://github.com/TMLP-Team/keyboxGenerator) - Unknown keybox.xml generator

## Links
[![release](https://custom-icon-badges.demolab.com/badge/-Download-F25278?style=for-the-badge&logo=download&logoColor=white)](https://github.com/KOWX712/Tricky-Addon-Update-Target-List/releases)
[![issue](https://custom-icon-badges.demolab.com/badge/-Open%20Issue-palegreen?style=for-the-badge&logoColor=black&logo=issue-opened)](https://github.com/KOWX712/Tricky-Addon-Update-Target-List/issues)
[![changelog](https://custom-icon-badges.demolab.com/badge/-Update%20History-orange?style=for-the-badge&logo=history&logoColor=white)](https://github.com/KOWX712/Tricky-Addon-Update-Target-List/blob/main/changelog.md)
[![Telegram](https://custom-icon-badges.demolab.com/badge/-KOW's%20little%20world-blue?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/kowchannel)
