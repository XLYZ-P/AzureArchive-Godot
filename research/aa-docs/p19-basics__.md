# 数据目录
分类: 进阶 | id: p19-basics_数据目录 | updated: 2024-06-30



## 目录结构
数据目录数据目录当中存储了您可能需要关注的几乎所有文件。

也许您早在安装环节就已经接触过这个目录了，但是我们还要介绍一次！

 |  | 平台 | 数据目录位置

 | Windows | C:\Users\<用户名>\AppData\LocalLow\foxxlight\AzureArchive\data

 | Android | /storage/emulated/0/Android/data/com.foxxlight.AzureArchive/files/data（推荐使用NP管理器等类似软件定位、编辑）

 | iOS | 我的iPhone(iPad)/AzureArchive/data（文件App内）

### 数据目录成员

#### assets/

存储资源文件的位置，除 Step 2C: 离线安装 外，一般来说不需要修改。

#### overrides/

自定义资源目录，详自定义资源 。

#### projects/

项目文件（.aap）存放位置，并且有与之同名的自定义资源文件夹。

如果要移植工程文件，请务必附带相应的 projects 文件夹！ 

#### saves/

存档文件（.aas）存放位置，可能有与之同名的自定义资源文件夹。

如果要移植工程文件，请务必附带相应的 saves 文件夹！ 

#### settings/

存放设置文件，如果你知道你在做什么，可以进行修改。（改炸了可以删除再由AzureArchive重新创建）

#### manualInstall/

### 有关移植文件 备份文件

AA是可以将任意一端的项目文件转移到任意一端设备上的!

你只需将你的AAP以及AAS和其同名文件夹放入相应的位置即可

如需备份文件请将整个Date文件夹一起备份。

手动安装文件夹，详见手动安装。
