import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/auth_store.dart';
import '../core/local_library_store.dart';
import '../core/catalog_store.dart';
import '../models/song.dart';
import 'admin_screen.dart';
import 'player_screen.dart';
import 'library_screen.dart';
import 'create_8d_screen.dart';
import 'music_library_hub_screen.dart';
import 'eightd_library_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthStore auth;
  final LocalLibraryStore localLibrary;
  final bool showAdminControls;
  const HomeScreen({super.key, required this.auth, required this.localLibrary, this.showAdminControls = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const apkDownloadUrl = String.fromEnvironment('APK_DOWNLOAD_URL',
      defaultValue: '/downloads/catws-songs.apk');
  final search = TextEditingController();
  late Future<CatalogSnapshot> future;
  Song? currentSong;
  bool showSearch = false;
  String activeMood = '';
  List<String> categories = const ['Podcasts', 'Feel good', 'Relax', 'Romance'];
  List<Song> loadedSongs = [];
  CatalogStatus catalogStatus = CatalogStatus.loading;
  Timer? refreshTimer;
  Timer? searchTimer;

  static const bg = Color(0xFFFFFAF7);
  static const ink = Color(0xFF403634);
  static const accent = Color(0xFF984D45);
  static const chip = Color(0xFFFCE5E1);
  static const nav = Color(0xFFFFE9E5);

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_authChanged);
    WidgetsBinding.instance.addObserver(this);
    refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    refresh();
    _loadCategories();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    searchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_authChanged);
    search.dispose();
    super.dispose();
  }

  void _authChanged() {
    if (!mounted) return;
    setState(() {});
    final notice = widget.auth.takeNotice();
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(notice)));
      });
    }
  }

  void refresh() {
    final request = widget.auth.api.loadCatalog(
      q: search.text,
      category: activeMood,
      onStatus: (snapshot) {
        if (!mounted) return;
        setState(() {
          catalogStatus = snapshot.status;
          if (snapshot.songs.isNotEmpty) loadedSongs = snapshot.songs;
          if (currentSong == null && snapshot.songs.isNotEmpty) {
            currentSong = snapshot.songs.first;
          }
        });
      },
    );
    setState(() {
      future = request;
      catalogStatus = CatalogStatus.loading;
    });
    request.then((snapshot) {
      if (!mounted) return;
      setState(() {
        loadedSongs = snapshot.songs;
        if (currentSong == null && snapshot.songs.isNotEmpty) currentSong = snapshot.songs.first;
      });
    }, onError: (_) {});
  }

  void searchChanged(String value) {
    searchTimer?.cancel();
    setState(() => activeMood = '');
    searchTimer = Timer(const Duration(milliseconds: 350), refresh);
  }

  Future<void> _loadCategories() async {
    try {
      final values = await widget.auth.api.categories();
      if (!mounted || values.isEmpty) return;
      setState(() => categories = values);
    } catch (_) {
      // Keep the curated chips when the catalog is temporarily unavailable.
    }
  }

  void applyMood(String value) {
    setState(() {
      activeMood = activeMood == value ? '' : value;
      search.clear();
    });
    refresh();
  }

  Future<void> openSong(Song song) async {
    setState(() => currentSong = song);
    final queue = loadedSongs.isEmpty ? <Song>[song] : loadedSongs;
    final idx = queue.indexWhere((s) => s.id == song.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PlayerScreen(
                api: widget.auth.api,
                queue: queue,
                initialIndex: idx < 0 ? 0 : idx,
                localLibrary: widget.localLibrary,
                remoteLibraryEnabled: widget.auth.loggedIn,
              )),
    );
  }

  Future<void> openLibrary([int initialIndex = 0]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => LibraryScreen(
                api: widget.auth.api,
                localLibrary: widget.localLibrary,
                remoteLibraryEnabled: widget.auth.loggedIn,
                initialIndex: initialIndex,
              )),
    );
  }

  Future<void> openMusicLibraryHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MusicLibraryHubScreen(
                api: widget.auth.api,
                localLibrary: widget.localLibrary,
                showPrivateEightD: widget.auth.loggedIn,
              )),
    );
  }

  Future<void> openEightDLibrary() async {
    if (!widget.auth.loggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('My 8D Songs requires an account.')));
      }
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => EightDLibraryScreen(api: widget.auth.api)),
    );
  }

  Future<void> openAdmin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              AdminScreen(api: widget.auth.api, onChanged: refresh)),
    );
    refresh();
  }

  Future<void> openAdminLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => LoginScreen(auth: widget.auth, adminOnly: true)),
    );
    if (mounted) setState(() {});
  }

  Future<void> openCreate8D() async {
    if (!widget.auth.loggedIn) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Create8DScreen(api: widget.auth.api)),
    );
  }

  Future<void> downloadApp() async {
    final configured = Uri.tryParse(apkDownloadUrl);
    final downloadUri = configured == null
        ? null
        : configured.hasScheme
            ? configured
            : Uri.base.resolve(apkDownloadUrl);
    if (downloadUri == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('APK download is unavailable right now.')));
      return;
    }
    final opened =
        await launchUrl(downloadUri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('APK download is unavailable right now.')));
    }
  }

  void accountSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFBF9),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  widget.auth.loggedIn
                      ? 'Hi, ${widget.auth.username}'
                      : 'Catws Songs',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900, color: ink)),
              const SizedBox(height: 4),
              Text(
                  widget.auth.loggedIn
                      ? (widget.showAdminControls && widget.auth.isAdmin
                          ? 'Admin account'
                          : 'Signed-in account')
                      : 'Public listening — no account required',
                  style: const TextStyle(color: Color(0xFF8B7771))),
              const SizedBox(height: 18),
              if (widget.showAdminControls && widget.auth.isAdmin)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      backgroundColor: chip,
                      child: Icon(Icons.admin_panel_settings_outlined,
                          color: accent)),
                  title: const Text('Admin panel',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    openAdmin();
                  },
                ),
              if (widget.showAdminControls && !widget.auth.isAdmin)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      backgroundColor: chip,
                      child: Icon(Icons.admin_panel_settings_outlined,
                          color: accent)),
                  title: const Text('Admin login',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    openAdminLogin();
                  },
                ),
              if (widget.auth.loggedIn)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      backgroundColor: chip,
                      child: Icon(Icons.logout_rounded, color: accent)),
                  title: const Text('Logout',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.auth.logout();
                  },
                ),
              if (widget.auth.loggedIn)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      backgroundColor: chip,
                      child: Icon(Icons.switch_account_outlined,
                          color: accent)),
                  title: const Text('Switch account',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Login as a different user'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await widget.auth.logout();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void moreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFBF9),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetTile(Icons.refresh_rounded, 'Refresh music', () {
                Navigator.pop(sheetContext);
                refresh();
              }),
              _sheetTile(Icons.download_rounded, 'Download Android app', () {
                Navigator.pop(sheetContext);
                downloadApp();
              }),
              _sheetTile(Icons.favorite_border_rounded, 'Liked songs', () {
                Navigator.pop(sheetContext);
                openLibrary(0);
              }),
              _sheetTile(Icons.queue_music_rounded, 'Playlists', () {
                Navigator.pop(sheetContext);
                openLibrary(1);
              }),
              _sheetTile(Icons.spatial_audio_rounded, '8D Songs & Playlists',
                  () {
                Navigator.pop(sheetContext);
                if (widget.auth.loggedIn) {
                  openEightDLibrary();
                } else {
                  openMusicLibraryHub();
                }
              }),
              _sheetTile(Icons.history_rounded, 'Recently played', () {
                Navigator.pop(sheetContext);
                openLibrary(2);
              }),
              if (widget.auth.loggedIn)
                _sheetTile(Icons.spatial_audio_outlined, 'Create your 8D song',
                    () {
                  Navigator.pop(sheetContext);
                  openCreate8D();
                }),
              _sheetTile(Icons.person_outline_rounded, 'Account', () {
                Navigator.pop(sheetContext);
                accountSheet();
              }),
              if (widget.showAdminControls && widget.auth.isAdmin)
                _sheetTile(Icons.admin_panel_settings_outlined, 'Admin panel',
                    () {
                  Navigator.pop(sheetContext);
                  openAdmin();
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading:
          CircleAvatar(backgroundColor: chip, child: Icon(icon, color: accent)),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF8B7771)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async => refresh(),
              color: accent,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _topBar()),
                  SliverToBoxAdapter(child: _moodChips()),
                  if (showSearch) SliverToBoxAdapter(child: _searchBox()),
                  SliverToBoxAdapter(
                    child: FutureBuilder<CatalogSnapshot>(
                      future: future,
                      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          if (catalogStatus == CatalogStatus.connecting && loadedSongs.isEmpty) {
            return _errorState('Connecting to Catws Songs...');
          }
          if (loadedSongs.isNotEmpty) {
            return _catalogSections(
              loadedSongs,
              showConnecting: catalogStatus == CatalogStatus.connecting,
            );
          }
          return const Padding(
                            padding: EdgeInsets.only(top: 90),
                            child: Center(
                                child:
                                    CircularProgressIndicator(color: accent)),
                          );
                        }
                        if (snap.hasError) {
                          return _errorState('Connecting to Catws Songs...');
                        }
                        final snapshot = snap.data;
                        final songs = snapshot?.songs ?? const <Song>[];
                        if (snapshot != null && snapshot.isConnecting && songs.isEmpty) {
                          return _errorState('Connecting to Catws Songs...');
                        }
                        if (songs.isEmpty) {
                          return _errorState(
                            activeMood.isNotEmpty
                                ? 'No songs found in “$activeMood”.'
                                : search.text.trim().isEmpty
                                    ? 'No songs available yet.'
                                    : 'No songs matched “${search.text.trim()}”.',
                          );
                        }
                        return _catalogSections(songs);
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (!keyboardVisible)
              Positioned(left: 0, right: 0, bottom: 0, child: _bottomDock()),
          ],
        ),
      ),
    );
  }

  Widget _catalogSections(List<Song> songs, {bool showConnecting = false}) {
    final featured = songs.where((s) => s.isFeatured).toList();
    final hot = featured.isNotEmpty ? featured : songs;
    final dance = songs.take(8).toList();
    final newReleases = songs.reversed.take(8).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 210),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showConnecting)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text('Connecting to Catws Songs...',
                  style: TextStyle(color: Color(0xFF8B7771), fontWeight: FontWeight.w700)),
            ),
          _section(
            eyebrow: 'DANCE YOUR STRESS AWAY',
            title: 'Dancing on your own',
            songs: dance,
          ),
          _section(
            eyebrow: "MUSIC THAT'S HOT AND HAPPENING",
            title: "India's biggest hits",
            songs: hot,
          ),
          _section(
            eyebrow: 'FRESH FOR YOU',
            title: 'New releases',
            songs: newReleases,
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Catws Music',
              style: TextStyle(
                  fontSize: 31,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: ink,
                  letterSpacing: .4),
            ),
          ),
          _topIcon(Icons.history_rounded, () => openLibrary(2)),
          _topIcon(Icons.trending_up_rounded, refresh),
          _topIcon(Icons.group_outlined, accountSheet),
          _topIcon(Icons.settings_outlined, () {
            if (widget.showAdminControls && widget.auth.isAdmin) {
              openAdmin();
            } else {
              accountSheet();
            }
          }),
        ],
      ),
    );
  }

  Widget _topIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 29, color: const Color(0xFF655753)),
      splashRadius: 24,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _moodChips() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final mood = categories[index];
          final selected = activeMood == mood;
          return InkWell(
            onTap: () => applyMood(mood),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFD8D1) : chip,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected
                        ? accent.withOpacity(.30)
                        : Colors.transparent),
              ),
              child: Text(mood,
                  style: const TextStyle(
                      fontSize: 17,
                      color: Color(0xFF6E605C),
                      fontWeight: FontWeight.w500)),
            ),
          );
        },
      ),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: TextField(
        controller: search,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: searchChanged,
        onSubmitted: (_) => refresh(),
        decoration: InputDecoration(
          hintText: 'Search songs or artists',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: refresh),
          filled: true,
          fillColor: const Color(0xFFFFEEE9),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _section(
      {required String eyebrow,
      required String title,
      required List<Song> songs}) {
    if (songs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(eyebrow,
                style: const TextStyle(
                    fontSize: 15,
                    letterSpacing: .25,
                    color: ink,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 29,
                    height: 1.1,
                    color: accent,
                    fontWeight: FontWeight.w400)),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 225,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 22),
              itemBuilder: (context, index) => _albumTile(songs[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumTile(Song song) {
    return SizedBox(
      width: 148,
      child: InkWell(
        onTap: () => openSong(song),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    song.coverUrl,
                    width: 148,
                    height: 148,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 148,
                      height: 148,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFF6A3B36), Color(0xFFD68C7D)]),
                      ),
                      child: const Icon(Icons.music_note_rounded,
                          color: Colors.white, size: 50),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.28),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54)),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, color: ink, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(song.artist,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.25, color: Color(0xFF8D7770))),
          ],
        ),
      ),
    );
  }

  Widget _errorState(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 90, 28, 250),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.music_off_rounded,
                size: 54, color: Color(0xFFC89E94)),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF806C67), fontSize: 16, height: 1.4)),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh')),
          ],
        ),
      ),
    );
  }

  Widget _bottomDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00FFFAF7), bg]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentSong != null) _miniPlayer(currentSong!),
          if (currentSong != null) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 66,
                  decoration: BoxDecoration(
                      color: nav,
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFDAD4),
                            borderRadius: BorderRadius.circular(26)),
                        child: const Row(children: [
                          Icon(Icons.home_rounded,
                              color: Color(0xFF6D5751), size: 29),
                          SizedBox(width: 8),
                          Text('Home',
                              style: TextStyle(
                                  color: Color(0xFF6D5751),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600))
                        ]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search_rounded,
                            color: Color(0xFF6D5751), size: 30),
                        onPressed: () =>
                            setState(() => showSearch = !showSearch),
                      ),
                      IconButton(
                        icon: const Icon(Icons.library_music_outlined,
                            color: Color(0xFF6D5751), size: 30),
                        onPressed: openMusicLibraryHub,
                      ),
                      IconButton(
                        tooltip: 'Create 8D',
                        icon: const Icon(Icons.spatial_audio_outlined,
                            color: Color(0xFF6D5751), size: 30),
                        onPressed: openCreate8D,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                borderRadius: BorderRadius.circular(36),
                onTap: moreSheet,
                child: Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFCC80),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(.10),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]),
                  child: const Icon(Icons.more_horiz_rounded,
                      color: Color(0xFF674E25), size: 31),
                ),
              ),
              const SizedBox(width: 5),
              IconButton(
                onPressed: () =>
                    currentSong == null ? null : openSong(currentSong!),
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: accent, size: 34),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniPlayer(Song song) {
    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
      decoration: BoxDecoration(
          color: const Color(0xFFFFE8E4),
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]),
      child: Row(
        children: [
          ClipOval(
            child: Image.network(
              song.coverUrl,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  width: 54,
                  height: 54,
                  color: const Color(0xFFD8B4AB),
                  child: const Icon(Icons.music_note_rounded,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF8F746D), fontSize: 13)),
              ],
            ),
          ),
          IconButton(
              onPressed: () => openSong(song),
              icon: const Icon(Icons.skip_previous_rounded,
                  color: ink, size: 30)),
          IconButton(
              onPressed: () => openSong(song),
              icon: const Icon(Icons.play_arrow_rounded, color: ink, size: 34)),
          IconButton(
              onPressed: () => openSong(song),
              icon: const Icon(Icons.skip_next_rounded, color: ink, size: 30)),
        ],
      ),
    );
  }
}
