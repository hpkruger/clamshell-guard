# AwakeToggle

一个菜单栏开关:**合上盖子,Mac 也不休眠。**

点一下图标就切换,不用记命令、不用改系统设置。52KB,只做这一件事。

<!-- 建议在这里放一张菜单栏截图 -->

**[⬇️ 下载 AwakeToggle.zip](https://github.com/machinefriendly/awaketoggle/releases/latest)** · macOS 12 或更新 · Intel 和 Apple 芯片都支持

---

## 怎么用

- **左键点图标** — 直接切换
- **右键点图标** — 打开菜单(带开关和退出)
- **图标是合盖的笔记本** = 常驻在线已开启
- **图标是开盖的笔记本** = 正常休眠

切换时会弹一次系统密码框。这是 macOS 自己的授权对话框,因为改电源设置需要管理员权限。这个 App 不保存你的密码,也没有安装任何后台服务。

---

## 为什么会看到「Apple 无法验证此 App 不含恶意软件」?

**先说结论:这不是说 App 有病毒。**

macOS 对任何没经过 Apple「公证」(notarization)的软件都会弹这个提示,不管它实际上安不安全。而公证需要 Apple 开发者账号,**每年 99 美元**。

### 为什么我没买?

AwakeToggle 是我写给自己用的小工具——52KB,只做一件事。既然免费送出来,就没理由每年为它掏 99 美元。所以你会看到这个警告,**这是正常的**。

### 不用信我,自己验证

- 📖 **全部源码就在这个仓库里** → [`AwakeToggle.swift`](AwakeToggle.swift) · 一共约 180 行,两分钟读完
- ⚙️ 它只执行一条 macOS 自带的命令:`pmset -a disablesleep 0/1`
- 🔒 **不联网 · 不收集任何数据 · 不装后台服务 · 不开机自启**
- 🔨 不放心?[自己编译](#自己编译),结果和我发的一模一样

### 怎么打开

1. 解压,把 `AwakeToggle.app` 拖进「应用程序」
2. 双击 → 被拦下 → 点 **「完成」**(⚠️ 不要点「移到废纸篓」)
3. 打开 **系统设置 → 隐私与安全性**,往下滚,找到「AwakeToggle 已被阻止使用」
4. 点 **「仍要打开」** → 再确认一次
5. 搞定,以后不会再问

---

## 自己编译

只需要 Xcode 命令行工具,不需要装完整的 Xcode:

```bash
xcode-select --install     # 如果还没装过
git clone https://github.com/machinefriendly/awaketoggle.git
cd awaketoggle
./build.sh
```

编出来的 `AwakeToggle.app` 是通用二进制(Intel + Apple 芯片),最低支持 macOS 12。

---

## 它到底做了什么

全部的魔法就这一行([AwakeToggle.swift](AwakeToggle.swift)):

```swift
do shell script "/usr/bin/pmset -a disablesleep 1" with administrator privileges
```

`pmset` 是 macOS 自带的电源管理命令,`disablesleep 1` 让系统在合盖时不进入睡眠。这个 App 只是给它做了个开关,省得你每次开终端敲命令。

> **注意:** 开启后合盖不休眠,机器会继续跑。用电池时请留意电量,并保证散热(别把发热的机器闷在包里)。不用的时候记得关掉。

---

## 有别的需求?告诉我

这个小工具现在只做一件事。如果你有其他想法——更复杂的功能、别的没被解决的痛点——欢迎 **[提个 Issue](https://github.com/machinefriendly/awaketoggle/issues/new)**。

如果用的人多起来、功能也做丰富了,我会考虑买开发者证书做公证,到时候这个警告就没有了。

---

## License

MIT — 随便用,随便改。见 [LICENSE](LICENSE)。

Made by [MachineFriendly](https://machinefriendly.com)
