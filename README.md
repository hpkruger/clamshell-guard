# AwakeToggle

A menu-bar controller that keeps your Mac awake **with the lid closed.**

This local fork provides three modes:

- **ON** — always prevent sleep
- **AUTO** — prevent sleep while the macOS Codex app is running one or more tasks
- **OFF** — use normal macOS sleep behaviour

<!-- TODO: menu-bar screenshot -->

macOS 12+ · Intel and Apple silicon

📖 Background: [Keep Your MacBook Awake With the Lid Closed](https://www.machinefriendly.com/blog/keep-macbook-awake-lid-closed-awaketoggle) — why `caffeinate` doesn't work for this.

---

## Installation

AUTO mode has three separate pieces: the app in `/Applications`, a narrowly
scoped sudoers rule for changing the sleep setting without repeated password
prompts, and Codex hooks that report when tasks start and stop.

### 1. Build and install the app

Install the Xcode Command Line Tools if needed, then run:

```bash
xcode-select --install
./build.sh
ditto AwakeToggle.app /Applications/AwakeToggle.app
open /Applications/AwakeToggle.app
```

`./build.sh` creates a universal Intel/Apple-silicon app and
`AwakeToggle.zip`. You can drag the app into **Applications** instead of using
`ditto`.

The Codex hook configuration below deliberately uses the absolute path
`/Applications/AwakeToggle.app`. Install the app there before enabling AUTO.

If macOS blocks the first launch because this locally built app is not
notarized, follow the [Opening an unnotarized build](#opening-an-unnotarized-build)
steps below.

### 2. Allow only AwakeToggle's two `pmset` changes without a password

AwakeToggle runs these two commands:

```bash
/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1
/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0
```

The `-n` flag means “never show a password prompt.” The command succeeds only
when sudoers already permits it; otherwise AwakeToggle leaves the setting
unchanged.

First find your short macOS username:

```bash
id -un
```

Open a dedicated sudoers file with the syntax-checking editor:

```bash
sudo visudo -f /etc/sudoers.d/awaketoggle-pmset
```

Add this as one line, replacing `yourusername` with the output from `id -un`:

```text
yourusername ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

Save and exit, then validate the file:

```bash
sudo visudo -cf /etc/sudoers.d/awaketoggle-pmset
```

It should report `parsed OK`. Confirm that the OFF operation works without a
cached password:

```bash
sudo -k
sudo -n /usr/bin/pmset -a disablesleep 0
```

If the second command asks for a password or prints `a password is required`,
do not broaden the rule: reopen the file with `visudo` and check the username,
absolute path, and arguments.

> Earlier local installations used
> `yourusername ALL=(root) NOPASSWD: /usr/bin/pmset`. That works, and still does
> not disable authentication for other programs, but it permits every `pmset`
> option. The two-command rule above is safer because it matches only the exact
> ON and OFF operations used by AwakeToggle.

### 3. Install the Codex hooks for AUTO mode

The repository includes [`codex-hooks.example.json`](codex-hooks.example.json).
If `~/.codex/hooks.json` does **not** exist yet:

```bash
mkdir -p ~/.codex
cp codex-hooks.example.json ~/.codex/hooks.json
chmod 600 ~/.codex/hooks.json
```

If the file already exists, do not overwrite it. Merge the example's
`UserPromptSubmit`, `Stop`, and `SessionEnd` entries into the corresponding
arrays under your existing top-level `hooks` object. Keep any hooks already
present.

The three commands invoke the helper bundled inside the app:

```text
"/Applications/AwakeToggle.app/Contents/MacOS/AwakeToggleHook" start
"/Applications/AwakeToggle.app/Contents/MacOS/AwakeToggleHook" stop
"/Applications/AwakeToggle.app/Contents/MacOS/AwakeToggleHook" session-end
```

Restart the macOS Codex app after creating or changing `hooks.json`. Open
Codex's `/hooks` screen, inspect these exact commands, and trust them. Codex
intentionally refuses to run a newly added non-managed hook until you approve
its definition.

The helper accepts start events only when it was launched by the official
macOS Codex app (`com.openai.codex`). It writes no task content—only the
session/turn identifiers, Codex app-server process ID, and start time needed to
track active tasks.

### 4. Test AUTO

1. Start AwakeToggle and select **AUTO**.
2. Start a new task in the macOS Codex app.
3. AwakeToggle should show `AUTO · 1 active Codex task`.
4. When the task finishes, AwakeToggle waits 10 seconds and returns to
   `AUTO · No active Codex tasks`.

You can inspect the underlying state at any time:

```bash
/usr/bin/pmset -g | /usr/bin/grep SleepDisabled
```

`SleepDisabled 1` means keep-awake is active; `0` means macOS may sleep
normally. Tasks that were already running before the hooks were installed,
trusted, and loaded are not retroactively detected.

### 5. Optional: launch at login

Open the AwakeToggle menu and enable **Launch on Login**. This uses
`SMAppService`, macOS's native login-item API. If macOS reports that approval is
required, approve AwakeToggle under **System Settings → General → Login
Items**.

---

## Usage

- **Click the icon** — open the mode menu
- **Closed-laptop icon** = stay-awake is on
- **Open-laptop icon** = normal sleep
- **Launch on Login** — start AwakeToggle automatically after signing in

The UI follows your system language: **English, 中文, or Français** (anything else falls back to English).

This installation uses a narrowly scoped sudoers rule so only the two exact
`/usr/bin/pmset -a disablesleep` changes can run without another password
prompt. AwakeToggle uses absolute paths and never receives or stores your
password.

It doesn't phone home or collect data. Launch at login is optional and uses
macOS's native login-item service.

### AUTO mode

AUTO uses Codex's `UserPromptSubmit`, `Stop`, and `SessionEnd` hooks. The bundled
`AwakeToggleHook` helper writes a small marker for each active Codex turn under:

```text
~/Library/Application Support/AwakeToggle/active-turns
```

AwakeToggle checks these markers every two seconds. It enables keep-awake while
at least one task is active, supports concurrent tasks, and waits 10 seconds
after the last task ends before allowing sleep.

The helper accepts start events only when its parent process belongs to the
official macOS Codex app (`com.openai.codex`). It has no network code.

The required user-level Codex configuration is shown in
[`codex-hooks.example.json`](codex-hooks.example.json). Copy or merge those
entries into `~/.codex/hooks.json`, restart Codex, then review and trust the
commands in Codex's `/hooks` screen. Codex intentionally will not execute a new
non-managed hook until you approve its exact definition.

---

## Why you'll see "Apple could not verify this app is free of malware"

**This is not a malware detection.** macOS shows this for *any* app that hasn't been through Apple's **notarization**, regardless of whether it's safe. Notarization requires an Apple Developer account at **$99/year**.

I didn't buy one. AwakeToggle is a small tool I wrote for myself and gave away
— a yearly subscription to hand it out for free doesn't add up. The warning is
the honest cost of that, so treat it like any unsigned binary from a stranger:
**don't take my word for it.**

### Don't trust me — read it

- The menu-bar app is in [`AwakeToggle.swift`](AwakeToggle.swift), and the small
  Codex hook helper is in [`AwakeToggleHook.swift`](AwakeToggleHook.swift).
- The only privileged thing it does is `pmset -a disablesleep 0/1` — Apple's own power-management command.
- **No network access or data collection.**
- [Build it yourself](#build-it-yourself) in one command and get the same app.

A notarized app can still do whatever it likes — the certificate proves someone
paid Apple, not that the code is good. The readable source is the more useful
security evidence here.

### Opening an unnotarized build

1. Unzip and drag `AwakeToggle.app` into **Applications**
2. Double-click → blocked → click **Done** (⚠️ **not** "Move to Trash")
3. Open **System Settings → Privacy & Security**, scroll down to "AwakeToggle was blocked"
4. Click **Open Anyway** → confirm once more
5. Done. It won't ask again.

> On macOS 15+, the old right-click → Open trick no longer works — Apple removed it. The route above is the only one now, which is why many tutorials you'll find are out of date.

---

## Build it yourself

Only the Xcode command line tools, no full Xcode install:

```bash
xcode-select --install     # if you haven't already
git clone https://github.com/machinefriendly/awaketoggle.git
cd awaketoggle
./build.sh
```

Produces a universal binary (Intel + Apple silicon) targeting macOS 12+, ad-hoc signed and packaged into the same zip I ship.

---

## What it actually does

The power-management operation is:

```bash
sudo -n /usr/bin/pmset -a disablesleep 1
```

Turning keep-awake off uses the same command with `0`.

`pmset` ships with macOS. `disablesleep 1` stops the system sleeping when the lid closes. The app is just a switch for it, so you don't open a terminal every time.

`caffeinate` can't do this: it creates a *power assertion*, which holds off **idle** sleep. A lid close is an explicit sleep request, and no assertion overrides it. That's why `pmset` needs `sudo` and `caffeinate` doesn't.

> ### ⚠️ Heat and battery
> Sleep stays disabled until you turn it back off — **a reboot doesn't reset it.** A Mac still running inside a closed bag has nowhere to dump heat and will drain flat. Watch the icon and switch it off when you're done. This is the reason there's a visible menu-bar indicator instead of a fire-and-forget script.

---

## Uninstalling or reverting the configuration

1. Select **OFF** and disable **Launch on Login** in AwakeToggle.
2. Confirm normal sleep is restored:

   ```bash
   sudo /usr/bin/pmset -a disablesleep 0
   ```

3. Remove the three AwakeToggle entries from `~/.codex/hooks.json`. Delete the
   entire file only if it contains no other hooks.
4. Remove the dedicated sudoers file:

   ```bash
   sudo rm /etc/sudoers.d/awaketoggle-pmset
   ```

   If you used a differently named file, remove only that exact file.
5. Quit AwakeToggle and move `/Applications/AwakeToggle.app` to the Trash.
6. Optional task markers can be removed from
   `~/Library/Application Support/AwakeToggle/active-turns`.

Restoring `disablesleep 0` before deleting the app matters because the macOS
power setting can outlive the process that changed it.

---

## Requests

If you want more — scheduled windows or auto-off below a battery threshold —
**[open an issue](https://github.com/machinefriendly/awaketoggle/issues/new)**.
I'd rather hear a real use case than guess.

If enough people use it, I'll reconsider the developer certificate so the warning goes away.

---

## 中文说明

**合上盖子，Mac 也不休眠。** 菜单栏提供 **开启 / 自动 / 关闭**
三种模式；自动模式会在 macOS Codex App 有任务运行时阻止休眠。界面跟随系统语言
（中文 / English / Français）。

### 为什么会看到「Apple 无法验证此 App 不含恶意软件」

**这不是说 App 有病毒。** macOS 对任何没经过 Apple「公证」的软件都会弹这个,不管它安不安全。公证需要 Apple 开发者账号,**每年 99 美元**。

我没买。这是我写给自己用的小工具,免费送出来,没理由每年为它掏 99 美元。所以这个警告是正常的 —— 但也别光信我:

- **全部源码就在这里**：菜单栏 App 为
  [`AwakeToggle.swift`](AwakeToggle.swift)，Codex hook 辅助程序为
  [`AwakeToggleHook.swift`](AwakeToggleHook.swift)
- 唯一需要权限的操作就是 `pmset -a disablesleep`(macOS 自带命令)
- **不联网 · 不收集数据**；登录时启动为可选设置
- 不放心可以自己 `./build.sh` 编译,结果一模一样

### 怎么打开

1. 解压,把 `AwakeToggle.app` 拖进「应用程序」
2. 双击 → 被拦下 → 点 **「完成」**(⚠️ 不要点「移到废纸篓」)
3. **系统设置 → 隐私与安全性** → 往下滚 → 点 **「仍要打开」** → 再确认一次
4. 搞定,以后不会再问

macOS 15 以后,右键→打开的老办法已经被 Apple 取消了,只能走上面这条路。

> **⚠️ 注意散热和电量:** 开启后要手动关掉才恢复,重启也不会重置。合盖不休眠意味着机器在包里继续跑,热量散不出去,电量也会耗光。菜单栏图标就是为了让你随时看见它开着。

有需求欢迎 **[提 Issue](https://github.com/machinefriendly/awaketoggle/issues/new)**。用的人多了,我会考虑买开发者证书做公证,到时候警告就没有了。

---

## License

MIT — do whatever you want. See [LICENSE](LICENSE).

Made by [MachineFriendly](https://machinefriendly.com)
