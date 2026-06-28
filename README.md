# Flutter IPTV TV Player
跨平台IPTV播放器，完美适配Android手机/电视盒子，支持遥控器焦点导航

## 功能列表
1. 在线M3U/M3U8直播源导入，自动本地缓存
2. 本地.m3u/.m3u8文件读取（U盘/本地存储）
3. VLC硬解播放主流HLS直播流
4. Android TV遥控器上下切台、OK确认播放
5. GitHub Actions自动编译Release安装包

## 本地运行
1. flutter pub get
2. flutter run
- 安卓设备：flutter run
- Windows桌面：flutter run -d windows

## TV遥控器操作
- 上下方向键：切换频道焦点，蓝色边框高亮
- OK/确认键：播放当前选中频道
- 右上角文件夹图标：导入在线链接 / 本地M3U文件

## 开源协议
MIT
