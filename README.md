# AwakeToggle

A menu-bar switch that keeps your Mac awake **with the lid closed.**

One click to toggle. No commands to remember. 52KB, and it does exactly one thing.

<!-- TODO: menu-bar screenshot -->

**[⬇️ Download AwakeToggle.zip](https://github.com/machinefriendly/awaketoggle/releases/latest/download/AwakeToggle.zip)** · macOS 12+ · Intel and Apple silicon

📖 Background: [Keep Your MacBook Awake With the Lid Closed](https://www.machinefriendly.com/blog/keep-macbook-awake-lid-closed-awaketoggle) — why `caffeinate` doesn't work for this.

---

## Usage

- **Left-click the icon** — toggle instantly
- **Right-click the icon** — open the menu
- **Closed-laptop icon** = stay-awake is on
- **Open-laptop icon** = normal sleep

The UI follows your system language: **English, 中文, or Français** (anything else falls back to English).

Toggling shows the standard macOS admin password prompt. That's the system's own authorization dialog — the app never sees or stores your password, and it deliberately does *not* install a privileged helper or add a passwordless-sudo rule to make the prompt go away. A permanent hole in your auth config isn't worth saving one click.

It doesn't phone home, collect data, run a background service, or launch at login.

---

## Why you'll see "Apple could not verify this app is free of malware"

**This is not a malware detection.** macOS shows this for *any* app that hasn't been through Apple's **notarization**, regardless of whether it's safe. Notarization requires an Apple Developer account at **$99/year**.

I didn't buy one. AwakeToggle is a 52KB tool I wrote for myself and gave away — a yearly subscription to hand it out for free doesn't add up. The warning is the honest cost of that, so treat it like any unsigned binary from a stranger: **don't take my word for it.**

### Don't trust me — read it

- The **entire app** is [one Swift file, ~240 lines](AwakeToggle.swift). A two-minute read, not a code audit.
- The only privileged thing it does is `pmset -a disablesleep 0/1` — Apple's own power-management command.
- **No network access, no data collection, no background service, no login item.**
- [Build it yourself](#build-it-yourself) in one command and get the same app.

A notarized app can still do whatever it likes — the certificate proves someone paid Apple, not that the code is good. 240 readable lines prove more than my $99 would.

### Opening it

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

The whole trick is one line:

```swift
do shell script "/usr/bin/pmset -a disablesleep 1" with administrator privileges
```

`pmset` ships with macOS. `disablesleep 1` stops the system sleeping when the lid closes. The app is just a switch for it, so you don't open a terminal every time.

`caffeinate` can't do this: it creates a *power assertion*, which holds off **idle** sleep. A lid close is an explicit sleep request, and no assertion overrides it. That's why `pmset` needs `sudo` and `caffeinate` doesn't.

> ### ⚠️ Heat and battery
> Sleep stays disabled until you turn it back off — **a reboot doesn't reset it.** A Mac still running inside a closed bag has nowhere to dump heat and will drain flat. Watch the icon and switch it off when you're done. This is the reason there's a visible menu-bar indicator instead of a fire-and-forget script.

---

## Requests

It does one thing today. If you want more — scheduled windows, auto-off below a battery threshold, launch at login — **[open an issue](https://github.com/machinefriendly/awaketoggle/issues/new)**. I'd rather hear a real use case than guess.

If enough people use it, I'll reconsider the developer certificate so the warning goes away.

---

## 中文说明

**合上盖子,Mac 也不休眠。** 菜单栏点一下就切换,52KB,只做这一件事。界面跟随系统语言(中文 / English / Français)。

### 为什么会看到「Apple 无法验证此 App 不含恶意软件」

**这不是说 App 有病毒。** macOS 对任何没经过 Apple「公证」的软件都会弹这个,不管它安不安全。公证需要 Apple 开发者账号,**每年 99 美元**。

我没买。这是我写给自己用的小工具,免费送出来,没理由每年为它掏 99 美元。所以这个警告是正常的 —— 但也别光信我:

- **全部源码就在这里**:[`AwakeToggle.swift`](AwakeToggle.swift),约 240 行,两分钟读完
- 唯一需要权限的操作就是 `pmset -a disablesleep`(macOS 自带命令)
- **不联网 · 不收集数据 · 不装后台服务 · 不开机自启**
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
