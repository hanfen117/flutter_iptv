import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;
import 'models/channel.dart';

void main() {
  runApp(const MyIptvApp());
}

class MyIptvApp extends StatelessWidget {
  const MyIptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter IPTV TV版',
      theme: ThemeData.dark(useMaterial3: true),
      home: const IptvHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class IptvHomePage extends StatefulWidget {
  const IptvHomePage({super.key});

  @override
  State<IptvHomePage> createState() => _IptvHomePageState();
}

class _IptvHomePageState extends State<IptvHomePage> {
  List<Channel> channelList = [];
  Channel? playingChannel;
  VlcPlayerController? vlcController;
  bool isLoading = true;
  String sourceUrl = "https://iptv-org.github.io/iptv/index.m3u";

  // 焦点管理
  final List<FocusNode> focusNodes = [];
  int currentFocusIndex = 0;

  @override
  void initState() {
    super.initState();
    loadM3uSource();
  }

  // 加载M3U并创建对应焦点节点
  Future<void> loadM3uSource() async {
    setState(() => isLoading = true);
    try {
      final resp = await http.get(Uri.parse(sourceUrl));
      final rawText = resp.body;
      final reg = RegExp(
        r'#EXTINF:-1 tvg-name="([^"]+)"( tvg-logo="([^"]+)")? group-title="([^"]+)".*\n([^\n#]+)',
      );
      List<Channel> tempList = [];
      for (var match in reg.allMatches(rawText)) {
        tempList.add(Channel(
          name: match.group(1)!,
          logo: match.group(3) ?? "",
          group: match.group(4)!,
          url: match.group(5)!.trim(),
        ));
      }
      setState(() {
        channelList = tempList;
        // 清空旧焦点
        for (var f in focusNodes) {
          f.dispose();
        }
        focusNodes.clear();
        // 每个频道生成一个焦点
        for (int i = 0; i < channelList.length; i++) {
          focusNodes.add(FocusNode());
        }
        isLoading = false;
      });
      // 默认选中第一条
      if (focusNodes.isNotEmpty) {
        focusNodes[0].requestFocus();
        currentFocusIndex = 0;
      }
    } catch (e) {
      setState(() => isLoading = false);
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("源加载失败：$e")),
        );
      }
    }
  }

  // 遥控器按键处理
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        // 向下
        case LogicalKeyboardKey.arrowDown:
          if (currentFocusIndex < channelList.length - 1) {
            setState(() => currentFocusIndex += 1);
            focusNodes[currentFocusIndex].requestFocus();
          }
          return KeyEventResult.handled;
        // 向上
        case LogicalKeyboardKey.arrowUp:
          if (currentFocusIndex > 0) {
            setState(() => currentFocusIndex -= 1);
            focusNodes[currentFocusIndex].requestFocus();
          }
          return KeyEventResult.handled;
        // OK确认播放当前焦点频道
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
          playChannel(channelList[currentFocusIndex]);
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> playChannel(Channel ch) async {
    if (vlcController != null) {
      await vlcController!.stop();
      await vlcController!.dispose();
    }
    setState(() => playingChannel = ch);
    vlcController = VlcPlayerController.network(
      ch.url,
      hwAccel: HwAccelLevel.auto,
      autoPlay: true,
    );
    await vlcController!.initialize();
  }

  @override
  void dispose() {
    vlcController?.dispose();
    for (var f in focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Widget buildChannelItem(int index) {
    final ch = channelList[index];
    bool isFocused = currentFocusIndex == index;
    return Focus(
      focusNode: focusNodes[index],
      onKeyEvent: _handleKeyEvent,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          setState(() => currentFocusIndex = index);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isFocused ? Colors.blueAccent.withOpacity(0.4) : Colors.transparent,
          border: isFocused ? Border.all(color: Colors.blue, width: 2) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: ListTile(
          title: Text(ch.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(ch.group, style: const TextStyle(fontSize: 10)),
          selected: playingChannel?.url == ch.url,
          onTap: () => playChannel(ch),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(playingChannel?.name ?? "IPTV TV播放器"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadM3uSource,
          )
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧焦点频道列表
          SizedBox(
            width: 260,
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: channelList.length,
                    itemBuilder: (ctx, idx) => buildChannelItem(idx),
                  ),
          ),
          const VerticalDivider(width: 1),
          // 播放区域
          Expanded(
            child: playingChannel == null
                ? const Center(child: Text("遥控器上下切换频道，OK确认播放"))
                : VlcPlayer(
                    controller: vlcController!,
                    aspectRatio: 16 / 9,
                    placeholder: const Center(child: CircularProgressIndicator()),
                  ),
          )
        ],
      ),
    );
  }
}
