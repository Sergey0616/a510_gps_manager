import re

filepath = 'lib/screens/map_screen.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Добавляем изоляцию выбранного трека при старте
old_init = """    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TracksProvider>().reloadFromDisk();
    });"""
new_init = """    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<TracksProvider>().reloadFromDisk();
      if (!mounted) return;
      
      if (widget.initialTrackId != null) {
        final provider = context.read<TracksProvider>();
        try {
          final track = provider.tracks.firstWhere((t) => t.id == widget.initialTrackId);
          _showTrack(track);
        } catch (_) {}
      }
    });"""
c = c.replace(old_init, new_init)

# 2. Меняем отрисовку всех треков на отрисовку ТОЛЬКО выбранного (если он выбран)
old_build_loop = """    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final color = _colors[i % _colors.length];
      final positions = track.points.map((point) => point.position).toList();
      if (positions.length >= 2) polylines.add(Polyline(points: positions, color: color, strokeWidth: 4));
      markers.add(Marker(point: positions.first, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.trip_origin, color: Colors.green, size: 28))));
      markers.add(Marker(point: positions.last, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.location_on, color: Colors.red, size: 30))));
    }"""
new_build_loop = """    // Если трек выбран — рисуем только его. Если нет — рисуем все.
    final displayTracks = _selectedTrack != null ? [_selectedTrack!] : tracks;

    for (var i = 0; i < displayTracks.length; i++) {
      final track = displayTracks[i];
      final color = _colors[i % _colors.length];
      final positions = track.points.map((point) => point.position).toList();
      
      if (positions.length >= 2) polylines.add(Polyline(points: positions, color: color, strokeWidth: 4));
      
      // Показываем маркеры только если трек не выбран (чтобы не засорять карту)
      if (_selectedTrack == null) {
        markers.add(Marker(point: positions.first, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.trip_origin, color: Colors.green, size: 28))));
        markers.add(Marker(point: positions.last, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.location_on, color: Colors.red, size: 30))));
      }
    }"""
c = c.replace(old_build_loop, new_build_loop)

# 3. Убираем дублирование отрисовки в PolylineLayer и MarkerLayer
old_layers = """            PolylineLayer(polylines: _selectedTrack != null ? [Polyline(points: _selectedTrack!.points.map((p) => p.position).toList(), strokeWidth: 4.0, color: Colors.blue)] : polylines),
            MarkerLayer(
              markers: _selectedTrack != null
                  ? [
                      Marker(point: _selectedTrack!.points.first.position, width: 36, height: 36, child: const Icon(Icons.trip_origin, color: Colors.green, size: 28)),
                      Marker(point: _selectedTrack!.points.last.position, width: 36, height: 36, child: const Icon(Icons.location_on, color: Colors.red, size: 30)),
                      if (_currentAnimatedPos != null)"""
new_layers = """            PolylineLayer(polylines: polylines),
            MarkerLayer(
              markers: _selectedTrack != null
                  ? [
                      ...markers,
                      if (_currentAnimatedPos != null)"""
c = c.replace(old_layers, new_layers)

# 4. Добавляем кнопку "Смотреть видео" в карточку выбранного трека
old_card = """          Positioned(left: 12, right: 76, bottom: 20, child: Card(child: ListTile(
            title: Text(DateFormat('dd.MM.yyyy HH:mm').format(_selectedTrack!.startLocal)),
            subtitle: Text('${_selectedTrack!.distanceKm.toStringAsFixed(2)} км · макс. ${_selectedTrack!.maxSpeedKmh.toStringAsFixed(0)} км/ч'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedTrack = null;
                _currentAnimatedPos = null;
                _animController.stop();
              }),
            ),
          ))),"""
new_card = """          Positioned(left: 12, right: 76, bottom: 20, child: Card(child: ListTile(
            title: Text(DateFormat('dd.MM.yyyy HH:mm').format(_selectedTrack!.startLocal)),
            subtitle: Text('${_selectedTrack!.distanceKm.toStringAsFixed(2)} км · макс. ${_selectedTrack!.maxSpeedKmh.toStringAsFixed(0)} км/ч'),
            leading: IconButton(
              icon: const Icon(Icons.play_circle, color: Colors.blue, size: 30),
              onPressed: () {
                final videos = _selectedTrack!.videoNames.toList();
                if (videos.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Для этого трека нет видео')));
                } else {
                  Navigator.of(context).pushNamed('/video', arguments: videos.first);
                }
              },
              tooltip: 'Смотреть видео',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedTrack = null;
                _currentAnimatedPos = null;
                _animController.stop();
              }),
            ),
          ))),"""
c = c.replace(old_card, new_card)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: Карта обновлена (изоляция треков + кнопка видео)")
