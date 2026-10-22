#!/usr/bin/env python3
"""Патч: Play/Pause + выбор скорости для анимации GPS-трека на карте.

Скорости: 0.5x / 1x / 2x / 4x. При смене скорости позиция маркера
сохраняется (AnimationController.forward(from: currentValue)).
"""
from pathlib import Path

TARGET = Path("lib/screens/map_screen.dart")
BACKUP = TARGET.with_suffix(".dart.bak")

# ---------------------------------------------------------------------------
# 1. Поля state
# ---------------------------------------------------------------------------
OLD_FIELDS = """  late AnimationController _animController;
  LatLng? _currentAnimatedPos;
  double _currentAngle = 0.0;
  Track? _selectedTrack;
  static const _colors = <Color>["""

NEW_FIELDS = """  late AnimationController _animController;
  LatLng? _currentAnimatedPos;
  double _currentAngle = 0.0;
  Track? _selectedTrack;
  bool _isPlaying = false;
  double _speed = 1.0;
  static const Duration _baseDuration = Duration(seconds: 30);
  static const List<double> _speeds = [0.5, 1.0, 2.0, 4.0];
  static const _colors = <Color>["""

# ---------------------------------------------------------------------------
# 2. initState — duration через _baseDuration + status listener
# ---------------------------------------------------------------------------
OLD_INIT = """    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 30));
    _animController.addListener(() {"""

NEW_INIT = """    _animController = AnimationController(vsync: this, duration: _baseDuration);
    _animController.addStatusListener((status) {
      if (!mounted) return;
      if (status == AnimationStatus.completed) {
        setState(() => _isPlaying = false);
      }
    });
    _animController.addListener(() {"""

# ---------------------------------------------------------------------------
# 3. _showTrack — сброс проигрывания и позиции при смене трека
# ---------------------------------------------------------------------------
OLD_SHOW = """  void _showTrack(Track track) {
    setState(() {
      _selectedTrack = track;
      _currentAnimatedPos = null;
      _animController.stop();
    });
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(track.points.map((p) => p.position).toList()),
      padding: const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }"""

NEW_SHOW = """  void _showTrack(Track track) {
    setState(() {
      _selectedTrack = track;
      _currentAnimatedPos = null;
      _isPlaying = false;
    });
    _animController.stop();
    _animController.value = 0;
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(track.points.map((p) => p.position).toList()),
      padding: const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }

  void _togglePlay() {
    if (_selectedTrack == null) return;
    if (_isPlaying) {
      _animController.stop();
      setState(() => _isPlaying = false);
      return;
    }
    if (_animController.value >= 1.0) {
      _animController.value = 0;
    }
    _animController.forward();
    setState(() => _isPlaying = true);
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(_selectedTrack!.points.map((p) => p.position).toList()),
      padding: const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }

  void _setSpeed(double s) {
    if (s == _speed) return;
    final wasPlaying = _isPlaying;
    if (wasPlaying) _animController.stop();
    final currentValue = _animController.value;
    setState(() {
      _speed = s;
      _animController.duration = Duration(
        milliseconds: (_baseDuration.inMilliseconds / s).round(),
      );
    });
    if (wasPlaying) {
      _animController.forward(from: currentValue);
    }
  }"""

# ---------------------------------------------------------------------------
# 4. Замена большой кнопки PLAY на панель проигрывателя
# ---------------------------------------------------------------------------
OLD_PLAY_BTN = """        if (_selectedTrack != null)
          Positioned(
            left: 20,
            bottom: 120,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 8,
              ),
              onPressed: () {
                _animController.forward(from: 0);
                _mapController.fitCamera(CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(_selectedTrack!.points.map((p) => p.position).toList()),
                  padding: const EdgeInsets.all(48),
                  maxZoom: 17,
                ));
              },
              icon: const Icon(Icons.play_arrow, size: 36),
              label: const Text('PLAY', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),"""

NEW_PLAYER_BAR = """        if (_selectedTrack != null)
          Positioned(
            left: 12,
            right: 76,
            bottom: 116,
            child: Card(
              color: Colors.black87,
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _animController.value,
                        minHeight: 2,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          iconSize: 32,
                          color: Colors.blue,
                          tooltip: _isPlaying ? 'Пауза' : 'Играть',
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                          ),
                          onPressed: _togglePlay,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _speeds
                                  .map(
                                    (s) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: ChoiceChip(
                                        label: Text('${s}x'.replaceAll('.0x', 'x')),
                                        selected: (s - _speed).abs() < 0.01,
                                        onSelected: (_) => _setSpeed(s),
                                        showCheckmark: false,
                                        labelStyle: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                        selectedColor: Colors.blue,
                                        backgroundColor: Colors.grey.shade800,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),"""

# ---------------------------------------------------------------------------
# 5. Кнопка закрытия трека — сброс проигрывания
# ---------------------------------------------------------------------------
OLD_CLOSE = """            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedTrack = null;
                _currentAnimatedPos = null;
                _animController.stop();
              }),
            ),"""

NEW_CLOSE = """            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedTrack = null;
                _currentAnimatedPos = null;
                _isPlaying = false;
                _animController.stop();
              }),
            ),"""

# ---------------------------------------------------------------------------

def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"[!] Не найден блок: {label}")
    if text.count(old) > 1:
        raise SystemExit(f"[!] Блок '{label}' встречается более одного раза")
    return text.replace(old, new, 1)

def main() -> None:
    if not TARGET.exists():
        raise SystemExit(f"Не найден файл: {TARGET}")
    if not BACKUP.exists():
        BACKUP.write_text(TARGET.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"Бэкап: {BACKUP}")
    else:
        print(f"Бэкап уже существует: {BACKUP}")

    text = TARGET.read_text(encoding="utf-8")
    text = replace_once(text, OLD_FIELDS,    NEW_FIELDS,    "state fields")
    text = replace_once(text, OLD_INIT,      NEW_INIT,      "initState")
    text = replace_once(text, OLD_SHOW,      NEW_SHOW,      "_showTrack + методы")
    text = replace_once(text, OLD_PLAY_BTN,  NEW_PLAYER_BAR, "PLAY-кнопка → плеер")
    text = replace_once(text, OLD_CLOSE,     NEW_CLOSE,     "закрытие трека")

    TARGET.write_text(text, encoding="utf-8")
    lines = text.count("\n") + 1
    print(f"Записан {TARGET} ({lines} строк)")

if __name__ == "__main__":
    main()
