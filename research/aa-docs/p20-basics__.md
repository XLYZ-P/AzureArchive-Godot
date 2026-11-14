# 自定义资源
分类: 进阶 | id: p20-basics_自定义资源 | updated: 2024-02-08



## 自定义资源

自定义资源涉及两种文件夹：

- #overrides/ 文件夹

- #projects/ 内与项目文件同名的文件夹

二者的结构完全一致，但前者生效于所有项目和存档，后者仅生效于对应项目和存档，并且后者更易于移植。方便起见，我们称二者为全局自定义文件夹和本地自定义文件夹，对应自定义资源为全局自定义资源和本地自定义资源。

### 自动自定义

点击对应选择器左上角背包按钮即可。（0.5.0及以上版本功能）

 自动自定义并不是会帮助制作自定义角色的功能 ，是方便快速导入功能!你仍需要自己制作的角色文件。

自定义角色的按钮

例如 音乐自定义

弹出图片自定义

由于Android、iOS权限问题，AzureArchive可能不能正确操作资源文件。如果发生这种情况，请手动自定义。

特殊地，如果仅仅需要为现存角色创建别名（修改名字、昵称），只要在角色选择器内选中一个原生角色，点击左上角设置名片按钮。选中本地自定义角色时，这个按钮也可以用于删除这个角色。

自动自定义的资源属于本地自定义资源。

### 需要无立绘发言角色办法

点击对话框人名位置

进去选择一个空白角色

然后点击左上角自定义按钮

按上述操作即可获得一个无立绘发言角色。

### 手动自定义

 最后有下载地址 

开始之前，请确保已经熟悉JSON格式规范！

新建自定义资源文件夹（如果没有的话）。

然后，在自定义资源文件夹内，新建“manifest.json”，并在其中写入：

{
  "CharacterOverrides": [],
  "VoiceOverrides": [],
  "PopupOverrides": [],
  "SoundOverrides": [],
  "BgOverrides": [],
  "BgEffectOverrides": [],
  "BgSpineOverrides": [],
  "BgmOverrides": []
}

### 自定义弹出图片/音效/背景图片

在“PopupOverrides”、“SoundOverrides”、“BgOverrides”中添加文件相应相对于“overrides”文件夹的路径（带扩展名）即可。

弹出图片和背景图片支持PNG格式的图片，音效支持OGG、MP3、WAV格式。

例如，在“overrides”文件夹内有“koharu.png”，“overrides/yuzu”文件夹内有“0721.png”，我们想将二者作为弹出图片，只需修改“PopupOverrides”字段如下：

{
  "...": "...",
  "PopupOverrides": [
    "koharu.webp",
    "yuzu/0721.webp"
  ],
  "...": "..."
}

### 新角色，有立绘

{
  "...": "...",
  "CharacterOverrides": [
    {
      "Identifier": "角色标识，请不要与现有的重复",
      "Name": "角色名字，会显示在剧情中",
      "Nickname": "角色昵称，是名字右边的小字",
      "SpinePortraitPath": "spine 立绘文件相对 overrides 文件夹路径",
      "SmallPortraitPath": "PNG 格式角色头像相对 overrides 文件夹路径"
    }
  ],
  "...": "..."
}

立绘动画名称规范：待机状态“Idle_01”，眨眼“Eye_Close_01”（可以没有），表情使用两位数字名称（“00”“01”...“99”）。眨眼动画仅在无表情和“01”时播放。

立绘文件（xx.skel，xx.atlas，xx.webp）的文件名除后缀外必须一致，“SpinePortraitPath”字段下的文件路径不包含后缀！

角色头像需要特定的分辨率和裁切才可以正常显示，详情参考示例。

Spine Runtime不支持3.8.75版本的.skel文件，若必须使用这个版本，请自寻解决方案。

所有字段不要留空！

### 新角色，无立绘

{
  "...": "...",
  "CharacterOverrides": [
    {
      "Identifier": "角色标识，请不要与现有的重复",
      "Name": "角色名字，会显示在剧情中",
      "Nickname": "角色昵称，是名字右边的小字",
      "CharacterReference": "???"
    }
  ],
  "...": "..."
}

没错就是“???”，无需修改“CharacterReference”字段

### 现有角色，修改名字和昵称

{
  "...": "...",
  "CharacterOverrides": [
    {
      "Identifier": "角色标识，请不要与现有的重复",
      "Name": "角色名字，会显示在剧情中",
      "Nickname": "角色昵称，是名字右边的小字",
      "CharacterReference": "目标角色的 ID"
    }
  ],
  "...": "..."
}

### 样例下载

https://cloak3-my.sharepoint.com/:u:/g/personal/foxxlight_cloak3_onmicrosoft_com/EV9XseU69-FBuSyL5FL2Ua8Bfro0_9CxY3omlQkBWJWd_g?e=C6yCzl
