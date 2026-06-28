import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
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
  final TextEditingController _urlInputCtrl = TextEditingController();

  final List<FocusNode> focusNodes = [];
  int currentFocusIndex = 0;

  @override
  void initState() {
    super.initState();
    loadSavedSourceUrl();
  }

  Future<void> loadSavedSourceUrl() async {
    final sp = await SharedPreferences.getInstance();
    String? savedUrl = sp.getString("iptv_source_url");
    if (savedUrl != null && savedUrl.isNotEmpty) {
      sourceUrl = savedUrl;
      _urlInputCtrl.text = savedUrl;
    }
    loadM3uSource();
  }

  Future<void> saveSourceUrl(String url) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString("iptv_source_url", url);
    setState(() => sourceUrl = url);
  }

  Future<void> loadLocalM3UFile() async {
    setState(() => isLoading = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("未选择文件")));
        return;
      }

      PlatformFile file = result.files.first;
      String rawText = await file.xFile.readAsString();
      await parseM3uContent(rawText);
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("读取文件失败：$e")));
      }
    }
  }

  Future<void> parseM3uContent(String rawText) async {
    RegExp reg = RegExp(
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
      for (var f in focusNodes) {
        f.dispose();
      }
      focusNodes.clear();
      for (int i = 0; i < channelList.length; i++) {
        focusNodes.add(FocusNode());
      }
      isLoading = false;
    });
    if (focusNodes.isNotEmpty) {
      focusNodes[0].requestFocus();
      currentFocusIndex = 0;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("加载完成，共${tempList.length}个频道")));
  }

  Future<void> loadM3uSource() async {
    setState(() => isLoading = true);
    try {
      final resp = await http.get(Uri.parse(sourceUrl));
      await parseM3uContent(resp.body);
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("在线源加载失败：$e")));
      }
    }
  }

  void showImportSourceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("导入直播源"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlInputCtrl,
              decoration: const InputDecoration(hintText: "粘贴在线M3U链接"),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await loadLocalM3UFile();
                },
                child: const Text("选择本地 .m3u/.m3u8 文件"),
              ),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              String newUrl = _urlInputCtrl.text.trim();
              if (newUrl.isEmpty) return;
              await saveSourceUrl(newUrl);
              Navigator.pop(ctx);
              loadM3uSource();
            },
            child: const Text("加载在线链接"),
          )
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
          if (currentFocusIndex < channelList.length - 1) {
            setState(() => currentFocusIndex += 1);
            focusNodes[currentFocusIndex].requestFocus();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          if (currentFocusIndex > 0) {
            setState(() => currentFocusIndex -= 1);
            focusNodes[currentFocusIndex].requestFocus();
          }
          return KeyEventResult.handled;
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
        if (hasFocus) setState(() => currentFocusIndex = index);
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
            icon: const Icon(Icons.folder_open),
            onPressed: showImportSourceDialog,
            tooltip: "导入直播源（在线/本地文件）",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadM3uSource,
            tooltip: "刷新在线源",
          )
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Expanded(
            child: playingChannel == null
                ? const Center(child: Text("遥控器上下切换频道，OK确认播放\n右上角文件夹导入在线/本地M3U"))
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
