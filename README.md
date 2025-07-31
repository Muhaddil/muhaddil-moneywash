# muhaddil-moneywash

## Description

**muhaddil-moneywash** is a simple and configurable money laundering system for FiveM servers using ESX. It allows players to wash black money at specific locations on the map using a special card. It includes multilanguage support (Spanish, English, and French), notifications, animations, and context menus.

---

## Features

- Configurable black money washing.
- Uses a special item (`moneywash_card`) to access the system.
- Interactive process with progress bar/circle and animations.
- Support for adding/removing wash locations in real-time (admin only).
- Localized notifications and messages.
- Easy configuration via `config.lua`.
- Support for ESX and ox_lib.

---

## Installation

1. **Download or clone** this repository into your resources folder.
1. 2. **Make sure you have the following resources installed**:
- [es_extended (ESX)](https://github.com/esx-framework/esx-legacy)
- [ox_lib](https://github.com/overextended/ox_lib)

3. **Add the resource to your `server.cfg`**:
```lua
start muhaddil-moneywash
```

---

## Configuration

Edit the `config.lua` file to customize the system:

- `Config.percentage`: Percentage of the washing commission (random between 20 and 30 by default).
- `Config.itemname`: Name of the item required to wash money (default: `moneywash_card`).
- `Config.progressType`: Type of progress bar (`bar`, `circle`, or `none`).
- `Config.showNotification`: Show notifications to the user (true/false).
- `Config.returnCard`: Return the card after the process (true/false).
- `Config.zones`: Initial wash locations (more can be added in-game).

---

## Commands

- `/addmoneywash [job]`
Adds a new wash location at the player's current position (admin only).
Input a job to be a job-locked moneywash, if not, it will be public.

- `/delmoneywashmenu`
Opens the menu to delete wash locations (admin only).

---

## Main Files

- `client/client.lua`: Client-side logic, menus, animations, and notifications.
- `server/server.lua`: Server-side logic, validations, and location management.
- `config.lua`: General system configuration.
- `moneywashers.json`: Stores the wash locations.
- `locales/*.json`: Language files (es, en, fr).
- `fxmanifest.lua`: Resource manifest.

---

## Localization

The system supports multiple languages. You can edit the files in the `locales/` folder to customize the texts.

---

## License

This resource is licensed under the MIT License. See the `LICENSE` file for more details.

---

## Credits

Developed by **Muhaddil**.

---